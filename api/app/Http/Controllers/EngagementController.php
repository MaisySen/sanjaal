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
        $post = $this->visiblePost($request, $postId);
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
        $post = $this->visiblePost($request, $postId);
        DB::transaction(function () use ($request, $post) {
            if ($post->likes()->where('user_id', $request->user()->id)->delete()) {
                $post->decrement('likes_count');
            }
        });

        return response()->json(['liked' => false, 'likes_count' => $post->fresh()->likes_count]);
    }

    public function comments(Request $request, string $postId): JsonResponse
    {
        $post = $this->visiblePost($request, $postId);
        $hidden = Present::hiddenAuthors([$request->user()->id]);
        $page = $post->comments()->with('user')->whereNotIn('user_id', $hidden)
            ->where(fn ($q) => $q->whereNull('parent_id')->orWhereNotIn('parent_id', Comment::whereIn('user_id', $hidden)->select('id')))
            ->orderBy('id')->cursorPaginate(30);

        return response()->json([
            'data' => (function () use ($page) {
                $parents = collect($page->items())->pluck('parent_id')->filter()->unique()->all();
                $map = $parents ? Comment::whereIn('id', $parents)->pluck('public_id', 'id')->all() : [];

                return collect($page->items())->map(fn ($c) => Present::comment($c, $map))->values();
            })(),
            'next_cursor' => $page->nextCursor()?->encode(),
            'can_comment' => \App\Support\MemberControls::canComment($post->user_id, $request->user()->id),
        ]);
    }

    public function comment(Request $request, string $postId): JsonResponse
    {
        $data = $request->validate(['body' => ['required', 'string', 'max:1000'], 'parent_id' => ['nullable', 'uuid']]);
        $post = $this->visiblePost($request, $postId);
        $comment = DB::transaction(function () use ($request, $post, $data) {
            // Serialize the parent check and count with comment deletion.
            $post = Post::whereKey($post->id)->lockForUpdate()->firstOrFail();
            DB::table('users')->where('id', $post->user_id)->lockForUpdate()->first();
            abort_unless(\App\Support\MemberControls::canComment($post->user_id, $request->user()->id), 403, 'Comments are limited by this member.');
            $parent = isset($data['parent_id']) ? $post->comments()->where('public_id', $data['parent_id'])->whereNull('parent_id')->first() : null;
            abort_if(isset($data['parent_id']) && (! $parent || in_array($parent->user_id, Present::hiddenAuthors([$request->user()->id]), true)), 422, 'That comment is not available to reply to.');
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
        abort_if($this->cannotContact($request->user(), $target->id), 404);
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
