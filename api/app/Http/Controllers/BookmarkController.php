<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Post;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class BookmarkController extends Controller
{
    /** Private to the caller. Saving twice is a no-op. */
    public function save(Request $request, string $postId): JsonResponse
    {
        $post = Post::where('public_id', $postId)->firstOrFail();
        $me = $request->user();
        abort_if($this->blockedWith($me->id, $post->user_id), 404);
        DB::table('bookmarks')->insertOrIgnore(['user_id' => $me->id, 'post_id' => $post->id, 'created_at' => now(), 'updated_at' => now()]);

        return response()->json(['saved' => true]);
    }

    public function unsave(Request $request, string $postId): JsonResponse
    {
        $post = Post::where('public_id', $postId)->firstOrFail();
        DB::table('bookmarks')->where('user_id', $request->user()->id)->where('post_id', $post->id)->delete();

        return response()->json(['saved' => false]);
    }

    /** The caller's saved posts, newest save first. Posts by people blocked either way are left out. */
    public function index(Request $request): JsonResponse
    {
        $me = $request->user();
        $hidden = DB::table('blocks')->where('blocker_id', $me->id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $me->id)->pluck('blocker_id'))->all();
        $q = Post::with(['user', 'media', 'hashtags'])
            ->join('bookmarks', 'bookmarks.post_id', '=', 'posts.id')
            ->where('bookmarks.user_id', $me->id)
            ->select('posts.*', 'bookmarks.id as bookmark_id')
            ->orderByDesc('bookmarks.id');
        if ($hidden) {
            $q->whereNotIn('posts.user_id', $hidden);
        }
        $page = $q->cursorPaginate(15)->withQueryString();
        Present::preload($page->items(), $me);

        return response()->json([
            'data' => collect($page->items())->map(fn ($p) => Present::post($p, $me))->values(),
            'next_cursor' => $page->nextCursor()?->encode(),
        ]);
    }

    private function blockedWith(int $me, int $other): bool
    {
        return DB::table('blocks')->where(fn ($b) => $b->where('blocker_id', $me)->where('blocked_id', $other))
            ->orWhere(fn ($b) => $b->where('blocker_id', $other)->where('blocked_id', $me))->exists();
    }
}
