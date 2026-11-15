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
            'public_id' => $u->public_id, 'name' => $u->name, 'username' => $u->username,
            'bio' => $u->bio,
            'avatar_url' => $u->avatar ? url('/api/v1/media/'.$u->avatar) : null,
        ];
    }

    public static function post(Post $p, ?User $viewer = null): array
    {
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
            'liked' => $viewer ? $p->likes()->where('user_id', $viewer->id)->exists() : false,
            'created_at' => $p->created_at->toIso8601String(),
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
            'sender' => self::user($m->user),
            'client_id' => $m->client_id,
            'created_at' => $m->created_at->toIso8601String(),
            'seq' => $m->id,
        ];
    }
}
