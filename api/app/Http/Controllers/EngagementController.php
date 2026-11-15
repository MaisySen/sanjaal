<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Comment;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class EngagementController extends Controller
{
    public function like(Request $request, string $postId): JsonResponse
    {
        $post = Post::where('public_id', $postId)->firstOrFail();
        DB::transaction(function () use ($request, $post) {
            $row = $post->likes()->firstOrCreate(['user_id' => $request->user()->id]);
            if ($row->wasRecentlyCreated) {
                $post->increment('likes_count');
            }
        });

        return response()->json(['liked' => true, 'likes_count' => $post->fresh()->likes_count]);
    }

    public function unlike(Request $request, string $postId): JsonResponse
    {
        $post = Post::where('public_id', $postId)->firstOrFail();
        DB::transaction(function () use ($request, $post) {
            if ($post->likes()->where('user_id', $request->user()->id)->delete()) {
                $post->decrement('likes_count');
            }
        });

        return response()->json(['liked' => false, 'likes_count' => $post->fresh()->likes_count]);
    }

    public function comments(string $postId): JsonResponse
    {
        $post = Post::where('public_id', $postId)->firstOrFail();
        $page = $post->comments()->with('user')->orderBy('id')->cursorPaginate(30);

        return response()->json([
            'data' => collect($page->items())->map(fn ($c) => Present::comment($c))->values(),
            'next_cursor' => $page->nextCursor()?->encode(),
        ]);
    }

    public function comment(Request $request, string $postId): JsonResponse
    {
        $data = $request->validate(['body' => ['required', 'string', 'max:1000'], 'parent_id' => ['nullable', 'uuid']]);
        $post = Post::where('public_id', $postId)->firstOrFail();
        $comment = DB::transaction(function () use ($request, $post, $data) {
            $parent = isset($data['parent_id']) ? $post->comments()->where('public_id', $data['parent_id'])->whereNull('parent_id')->first() : null;
            $c = $post->comments()->create(['user_id' => $request->user()->id, 'body' => $data['body'], 'parent_id' => $parent?->id]);
            $post->increment('comments_count');

            return $c;
        });

        return response()->json(['comment' => Present::comment($comment->load('user'))], 201);
    }

    public function follow(Request $request, string $username): JsonResponse
    {
        $target = User::where('username', $username)->firstOrFail();
        abort_if($target->id === $request->user()->id, 422, 'You cannot follow yourself.');
        $request->user()->following()->syncWithoutDetaching([$target->id]);

        return response()->json(['following' => true]);
    }

    public function unfollow(Request $request, string $username): JsonResponse
    {
        $target = User::where('username', $username)->firstOrFail();
        $request->user()->following()->detach($target->id);

        return response()->json(['following' => false]);
    }
}
