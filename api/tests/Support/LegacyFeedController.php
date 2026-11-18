<?php

namespace Tests\Support;

use App\Http\Resources\Present;
use App\Models\Hashtag;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class LegacyFeedController extends \App\Http\Controllers\Controller
{
    private const WITH = ['user', 'media', 'hashtags'];

    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'kind' => ['nullable', 'in:post,reel'],
            'scope' => ['nullable', 'in:following,all'],
            'hashtag' => ['nullable', 'string', 'max:60'],
            'username' => ['nullable', 'string', 'max:30'],
        ]);
        $viewer = $request->user();
        // Keep viewer-specific state in the same database round trip as the feed.
        // These are live correlated checks, never cached access decisions.
        $uid = $viewer->id;
        $q = Post::with(self::WITH)->select('posts.*')->orderByDesc('id')
            ->whereNotExists(fn ($b) => $b->selectRaw('1')->from('blocks')->where(fn ($w) => $w
                ->where(fn ($d) => $d->whereColumn('blocks.blocker_id', 'posts.user_id')->where('blocks.blocked_id', $uid))
                ->orWhere(fn ($d) => $d->where('blocks.blocker_id', $uid)->whereColumn('blocks.blocked_id', 'posts.user_id'))))
            ->selectRaw('exists(select 1 from bookmarks where bookmarks.post_id = posts.id and bookmarks.user_id = ?) as _saved', [$uid])
            ->selectRaw('exists(select 1 from follows where follows.follower_id = ? and follows.followee_id = posts.user_id) as _following', [$uid])
            ->selectRaw("(posts.user_id = ? or coalesce((select share_to_chat from member_controls where member_controls.user_id = posts.user_id), true)) as _can_share", [$uid])
            ->selectRaw("(posts.user_id = ? or coalesce((select comments_from from member_controls where member_controls.user_id = posts.user_id), 'everyone') = 'everyone' or ((select comments_from from member_controls where member_controls.user_id = posts.user_id) = 'following' and exists(select 1 from follows where follows.follower_id = posts.user_id and follows.followee_id = ?))) as _can_comment", [$uid, $uid]);
        if ($request->filled('kind')) {
            $q->where('kind', $request->kind);
        }
        if ($request->scope === 'following') {
            $q->where(fn ($w) => $w->whereIn('user_id', $viewer->following()->select('users.id'))->orWhere('user_id', $viewer->id));
        }
        if ($request->filled('hashtag')) {
            $tag = Str::lower(ltrim($request->hashtag, '#'));
            $q->whereHas('hashtags', fn ($h) => $h->where('tag', $tag));
        }
        if ($request->filled('username')) {
            $q->whereHas('user', fn ($u) => $u->where('username', $request->username));
        }

        $page = $q->cursorPaginate(15)->withQueryString();

        return response()->json([
            'data' => (function () use ($page, $viewer) {
                Present::preload($page->items(), $viewer);

                $items = collect($page->items());
                return $items->map(function ($p) use ($viewer) {
                    $a = Present::post($p, $viewer);
                    $a['author']['following'] = (bool) $p->getAttribute('_following');

                    return $a;
                })->values();
            })(),
            'next_cursor' => $page->nextCursor()?->encode(),
        ]);
    }
}
