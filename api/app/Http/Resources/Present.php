<?php

namespace App\Http\Resources;

use App\Models\Comment;
use App\Models\Message;
use App\Models\Post;
use App\Models\User;
use Illuminate\Support\Facades\Storage;

/** Plain array presenters. The internal numeric id never leaves the API. */
class Present
{
    public static function user(User $u): array
    {
        return [
            'public_id' => $u->public_id, 'name' => $u->publicName(), 'username' => $u->username,
            'bio' => $u->bio,
            'avatar_url' => $u->avatar ? url('/api/v1/media/'.$u->avatar) : null,
        ];
    }

    /** Load reaction counts and the viewer's own reaction for a page of posts in one query. */
    public static function preload(iterable $posts, ?User $viewer = null): void
    {
        $posts = collect($posts);
        if ($posts->isEmpty()) {
            return;
        }
        $ids = $posts->pluck('id')->all();
        $uid = $viewer?->id ?? 0;
        $rows = \Illuminate\Support\Facades\DB::table('likes')->whereIn('post_id', $ids)
            ->selectRaw('post_id, reaction, count(*) as n, sum(case when user_id = ? then 1 else 0 end) as mine', [$uid])
            ->groupBy('post_id', 'reaction')->get()->groupBy('post_id');
        $counts = $rows;
        $mine = collect();
        foreach ($rows as $postId => $list) {
            foreach ($list as $r) {
                if ((int) $r->mine > 0) {
                    $mine[$postId] = $r->reaction;
                }
            }
        }
        foreach ($posts as $p) {
            $p->setAttribute('_reactions', ($counts[$p->id] ?? collect())->pluck('n', 'reaction'));
            $p->setAttribute('_mine', $mine->has($p->id) ? ($mine[$p->id] ?? '') : false);
        }
    }

    public static function post(Post $p, ?User $viewer = null): array
    {
        $pre = array_key_exists('_mine', $p->getAttributes());

        return [
            'public_id' => $p->public_id,
            'kind' => $p->kind,
            'body' => $p->body,
            'author' => self::user($p->user),
            'media' => $p->media->map(fn ($m) => [
                'type' => $m->type,
                'url' => url('/api/v1/media/'.$m->path),
                'mime' => $m->mime,
            ])->values(),
            'hashtags' => $p->hashtags->pluck('tag')->values(),
            'likes_count' => $p->likes_count,
            'comments_count' => $p->comments_count,
            'liked' => $pre ? $p->getAttribute('_mine') !== false : ($viewer ? $p->likes()->where('user_id', $viewer->id)->exists() : false),
            'my_reaction' => $pre ? ($p->getAttribute('_mine') === false ? null : $p->getAttribute('_mine')) : ($viewer ? $p->likes()->where('user_id', $viewer->id)->value('reaction') : null),
            'reactions' => $pre ? $p->getAttribute('_reactions') : $p->likes()->selectRaw('reaction, count(*) as n')->groupBy('reaction')->pluck('n', 'reaction'),
            'created_at' => $p->created_at->toIso8601String(),
        ];
    }

    public static function reactionState(Post $p, User $viewer): array
    {
        return [
            'likes_count' => $p->likes_count,
            'liked' => $p->likes()->where('user_id', $viewer->id)->exists(),
            'my_reaction' => $p->likes()->where('user_id', $viewer->id)->value('reaction'),
            'reactions' => $p->likes()->selectRaw('reaction, count(*) as n')->groupBy('reaction')->pluck('n', 'reaction'),
        ];
    }

    public static function comment(Comment $c): array
    {
        return [
            'public_id' => $c->public_id,
            'body' => $c->body,
            'author' => self::user($c->user),
            'parent_id' => $c->parent_id ? Comment::whereKey($c->parent_id)->value('public_id') : null,
            'created_at' => $c->created_at->toIso8601String(),
        ];
    }

    public static function message(Message $m): array
    {
        return [
            'public_id' => $m->public_id,
            'conversation_id' => $m->conversation->public_id,
            'body' => $m->body,
            'kind' => $m->kind ?? 'text',
            'media_url' => $m->media_id ? url('/api/v1/media/'.$m->media_id) : null,
            'media_mime' => $m->media_mime,
            'duration_ms' => $m->duration_ms,
            'reply_to' => $m->reply_to_id ? self::replyPreview($m->reply_to_id) : null,
            'sender' => self::user($m->user),
            'client_id' => $m->client_id,
            'created_at' => $m->created_at->toIso8601String(),
            'seq' => $m->id,
        ];
    }

    private static function replyPreview(int $id): ?array
    {
        $r = Message::with('user')->find($id);

        return $r ? ['public_id' => $r->public_id, 'sender' => $r->user->publicName(), 'kind' => $r->kind ?? 'text', 'body' => mb_substr((string) $r->body, 0, 80)] : null;
    }
}
