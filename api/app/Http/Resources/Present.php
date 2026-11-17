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
        $reactionsInline = $posts->every(fn ($p) => array_key_exists('_r_mine', $p->getAttributes()));
        $rows = $reactionsInline ? collect() : \Illuminate\Support\Facades\DB::table('likes')->whereIn('post_id', $ids)
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
        $feedState = $posts->every(fn ($p) => array_key_exists('_can_comment', $p->getAttributes()) && array_key_exists('_saved', $p->getAttributes()));
        $savedIds = $feedState ? [] : \Illuminate\Support\Facades\DB::table('bookmarks')->where('user_id', $uid)->whereIn('post_id', $ids)->pluck('post_id')->all();
        $pollIds = $posts->filter(fn ($p) => is_array($p->poll_options))->pluck('id')->all();
        $pollRows = $pollIds ? \Illuminate\Support\Facades\DB::table('poll_votes')->whereIn('post_id', $pollIds)
            ->selectRaw('post_id, choice, count(*) as n, sum(case when user_id = ? then 1 else 0 end) as mine', [$uid])
            ->groupBy('post_id', 'choice')->get()->groupBy('post_id') : collect();
        $owners = $posts->pluck('user_id')->unique()->all();
        $controls = $feedState ? collect() : \Illuminate\Support\Facades\DB::table('member_controls')->whereIn('user_id', $owners)->get()->keyBy('user_id');
        $ownerFollowsViewer = $feedState ? [] : \Illuminate\Support\Facades\DB::table('follows')->whereIn('follower_id', $owners)->where('followee_id', $uid)->pluck('follower_id')->all();
        foreach ($posts as $p) {
            if (! $feedState) {
                $scope = $controls[$p->user_id]->comments_from ?? 'everyone';
                $p->setAttribute('_can_comment', $viewer && ($p->user_id === $uid || $scope === 'everyone' || ($scope === 'following' && in_array($p->user_id, $ownerFollowsViewer, true))));
                $p->setAttribute('_can_share', $viewer && ($p->user_id === $uid || !isset($controls[$p->user_id]) || (bool) $controls[$p->user_id]->share_to_chat));
                $p->setAttribute('_saved', in_array($p->id, $savedIds, true));
            }
            if (is_array($p->poll_options)) $p->setAttribute('_poll_rows', $pollRows[$p->id] ?? collect());
            if (! array_key_exists('_r_mine', $p->getAttributes())) {
                $p->setAttribute('_reactions', ($counts[$p->id] ?? collect())->pluck('n', 'reaction'));
                $p->setAttribute('_mine', $mine->has($p->id) ? ($mine[$p->id] ?? '') : false);
            }
        }
    }

    public static function post(Post $p, ?User $viewer = null): array
    {
        $pre = array_key_exists('_mine', $p->getAttributes());

        return [
            'public_id' => $p->public_id,
            'kind' => $p->kind,
            'body' => $p->body,
            'poll' => self::poll($p, $viewer),
            'author' => self::user($p->user),
            'media' => $p->media->map(fn ($m) => [
                'type' => $m->type,
                'url' => url('/api/v1/media/'.$m->path),
                'mime' => $m->mime,
                'thumbnail_url' => $m->thumbnail_path ? url('/api/v1/media/'.$m->thumbnail_path) : null,
            ])->values(),
            'hashtags' => $p->hashtags->pluck('tag')->values(),
            'likes_count' => $p->likes_count,
            'comments_count' => $p->comments_count,
            'can_comment' => array_key_exists('_can_comment', $p->getAttributes()) ? (bool) $p->getAttribute('_can_comment') : ($viewer ? \App\Support\MemberControls::canComment($p->user_id, $viewer->id) : false),
            'can_share_to_chat' => array_key_exists('_can_share', $p->getAttributes()) ? (bool) $p->getAttribute('_can_share') : ($viewer ? \App\Support\MemberControls::canShare($p->user_id, $viewer->id) : false),
            'liked' => $pre ? $p->getAttribute('_mine') !== false : ($viewer ? $p->likes()->where('user_id', $viewer->id)->exists() : false),
            'my_reaction' => $pre ? ($p->getAttribute('_mine') === false ? null : $p->getAttribute('_mine')) : ($viewer ? $p->likes()->where('user_id', $viewer->id)->value('reaction') : null),
            'reactions' => $pre ? $p->getAttribute('_reactions') : $p->likes()->selectRaw('reaction, count(*) as n')->groupBy('reaction')->pluck('n', 'reaction'),
            'saved' => array_key_exists('_saved', $p->getAttributes()) ? (bool) $p->getAttribute('_saved') : ($viewer ? \Illuminate\Support\Facades\DB::table('bookmarks')->where('user_id', $viewer->id)->where('post_id', $p->id)->exists() : false),
            'created_at' => $p->created_at->toIso8601String(),
        ];
    }

    /** Aggregate counts and only the viewer's choice. No voter identities leave this presenter. */
    public static function poll(Post $post, ?User $viewer = null): ?array
    {
        if (! is_array($post->poll_options)) return null;
        $rows = $post->getAttribute('_poll_rows');
        if ($rows === null) {
            $rows = \Illuminate\Support\Facades\DB::table('poll_votes')->where('post_id', $post->id)
                ->selectRaw('choice, count(*) as n, sum(case when user_id = ? then 1 else 0 end) as mine', [$viewer?->id ?? 0])
                ->groupBy('choice')->get();
        }
        $counts = $rows->pluck('n', 'choice');
        $mine = $rows->first(fn ($r) => (int) $r->mine > 0);

        return [
            'options' => collect($post->poll_options)->map(fn ($text, $index) => ['choice' => $index, 'text' => $text, 'votes' => (int) ($counts[$index] ?? 0)])->values(),
            'total_votes' => (int) $rows->sum('n'),
            'my_choice' => $mine ? (int) $mine->choice : null,
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

    public static function comment(Comment $c, ?array $parentPublicIds = null): array
    {
        return [
            'public_id' => $c->public_id,
            'body' => $c->body,
            'author' => self::user($c->user),
            // A page of comments passes its parents' public ids in one read; a missing id means the parent is gone, as whereKey() would say.
            'parent_id' => $c->parent_id ? ($parentPublicIds !== null ? ($parentPublicIds[$c->parent_id] ?? null) : Comment::whereKey($c->parent_id)->value('public_id')) : null,
            'created_at' => $c->created_at->toIso8601String(),
        ];
    }

    /** $replyHiddenUpTo: reply previews of messages with an id at or below it are left out (history a viewer must not see). */
    public static function message(Message $m, int $replyHiddenUpTo = 0, array $hiddenAuthors = [], ?array $preloaded = null): array
    {
        return [
            'public_id' => $m->public_id,
            'conversation_id' => $m->conversation->public_id,
            'body' => $m->body,
            'kind' => $m->kind ?? 'text',
            'media_url' => $m->media_id ? url('/api/v1/conversations/'.$m->conversation->public_id.'/messages/'.$m->public_id.'/media') : null,
            'media_mime' => $m->media_mime,
            'duration_ms' => $m->duration_ms,
            'shared_post' => $m->shared_post_id ? self::sharedPreview($m->shared_post_id, $hiddenAuthors, $preloaded) : null,
            'reply_to' => $m->reply_to_id && $m->reply_to_id > $replyHiddenUpTo ? self::replyPreview($m->reply_to_id, $preloaded) : null,
            'sender' => self::user($m->user),
            'client_id' => $m->client_id,
            'created_at' => $m->created_at->toIso8601String(),
            'seq' => $m->id,
        ];
    }

    /** A small card for a post shared in chat. Left out when the post is gone or its author is hidden from the viewer. */
    private static function sharedPreview(int $postId, array $hiddenAuthors, ?array $preloaded = null): ?array
    {
        // A caller that already read the posts for a whole page passes them in; a missing id means gone, as find() would say.
        $p = $preloaded !== null ? ($preloaded['posts'][$postId] ?? null) : Post::with('user', 'media')->find($postId);
        if (! $p || in_array($p->user_id, $hiddenAuthors, true)) {
            return null;
        }
        $img = $p->media->firstWhere('type', 'image');

        return [
            'public_id' => $p->public_id,
            'author' => self::user($p->user),
            'excerpt' => mb_substr((string) $p->body, 0, 140),
            'image_url' => $img ? url('/api/v1/media/'.$img->path) : null,
            'kind' => $p->kind,
        ];
    }

    /** Authors a set of users have blocked or been blocked by, for filtering shared previews. */
    public static function hiddenAuthors(array $userIds): array
    {
        $rows = \Illuminate\Support\Facades\DB::table('blocks')->whereIn('blocker_id', $userIds)->orWhereIn('blocked_id', $userIds)->get(['blocker_id', 'blocked_id']);

        return $rows->flatMap(fn ($r) => [$r->blocker_id, $r->blocked_id])->unique()->reject(fn ($id) => in_array($id, $userIds, true))->values()->all();
    }

    private static function replyPreview(int $id, ?array $preloaded = null): ?array
    {
        $r = $preloaded !== null ? ($preloaded['replies'][$id] ?? null) : Message::with('user')->find($id);

        return $r ? ['public_id' => $r->public_id, 'sender' => $r->user->publicName(), 'kind' => $r->kind ?? 'text', 'body' => mb_substr((string) $r->body, 0, 80)] : null;
    }
}
