<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Comment;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Profiles, search, avatars, notifications, blocking, reporting. */
class SocialController extends Controller
{
    public function profile(Request $request, string $username): JsonResponse
    {
        $u = User::where('username', $username)->firstOrFail();
        $viewer = $request->user();

        return response()->json(['user' => $this->card($u, $viewer) + [
            'posts_count' => Post::where('user_id', $u->id)->count(),
            'followers_count' => DB::table('follows')->where('followee_id', $u->id)->count(),
            'following_count' => DB::table('follows')->where('follower_id', $u->id)->count(),
        ]]);
    }

    public function search(Request $request): JsonResponse
    {
        $q = Str::lower(trim((string) $request->query('q', '')));
        $q = ltrim($q, '@');
        if (strlen($q) < 1) {
            return response()->json(['users' => [], 'hashtags' => []]);
        }
        $like = '%'.str_replace(['%', '_'], ['\\%', '\\_'], $q).'%';
        $viewer = $request->user();
        $users = User::whereRaw('lower(username) like ?', [$like])->orWhereRaw('lower(name) like ?', [$like])
            ->where('id', '!=', $viewer->id)->orderBy('username')->limit(20)->get()
            ->reject(fn ($u) => $this->blocked($viewer, $u))
            ->map(fn ($u) => $this->card($u, $viewer))->values();
        $tags = DB::table('hashtags')->where('tag', 'like', $like)->orderBy('tag')->limit(10)->pluck('tag');

        return response()->json(['users' => $users, 'hashtags' => $tags]);
    }

    public function avatar(Request $request): JsonResponse
    {
        $request->validate(['avatar' => ['required', 'file', 'mimes:jpg,jpeg,png,webp', 'max:5120']]);
        $file = $request->file('avatar');
        $user = $request->user();
        $id = (string) Str::uuid();
        DB::table('media_blobs')->insert([
            'public_id' => $id, 'mime' => $file->getMimeType(), 'size' => $file->getSize(),
            'data' => base64_encode(file_get_contents($file->getRealPath())),
            'created_at' => now(), 'updated_at' => now(),
        ]);
        if ($user->avatar) {
            DB::table('media_blobs')->where('public_id', $user->avatar)->delete();
        }
        $user->forceFill(['avatar' => $id])->save();

        return response()->json(['user' => Present::user($user->fresh())]);
    }

    /** Likes, comments and follows that involve the member, newest first. */
    public function notifications(Request $request): JsonResponse
    {
        $me = $request->user();
        $blockedIds = $this->blockedIds($me);
        $items = collect();

        DB::table('likes')->join('posts', 'posts.id', '=', 'likes.post_id')->join('users', 'users.id', '=', 'likes.user_id')
            ->where('posts.user_id', $me->id)->where('likes.user_id', '!=', $me->id)->whereNull('posts.deleted_at')
            ->orderByDesc('likes.id')->limit(40)
            ->get(['users.username', 'users.name', 'users.public_id as uid', 'posts.public_id as post', 'posts.body', 'likes.created_at'])
            ->each(fn ($r) => $items->push(['type' => 'like', 'actor' => $r->username, 'actor_id' => $r->uid, 'post_id' => $r->post, 'text' => Str::limit((string) $r->body, 60), 'created_at' => $this->iso($r->created_at)]));

        DB::table('comments')->join('posts', 'posts.id', '=', 'comments.post_id')->join('users', 'users.id', '=', 'comments.user_id')
            ->where('posts.user_id', $me->id)->where('comments.user_id', '!=', $me->id)->whereNull('comments.deleted_at')
            ->orderByDesc('comments.id')->limit(40)
            ->get(['users.username', 'users.public_id as uid', 'posts.public_id as post', 'comments.body', 'comments.created_at'])
            ->each(fn ($r) => $items->push(['type' => 'comment', 'actor' => $r->username, 'actor_id' => $r->uid, 'post_id' => $r->post, 'text' => Str::limit((string) $r->body, 80), 'created_at' => $this->iso($r->created_at)]));

        DB::table('follows')->join('users', 'users.id', '=', 'follows.follower_id')
            ->where('follows.followee_id', $me->id)->orderByDesc('follows.id')->limit(40)
            ->get(['users.username', 'users.public_id as uid', 'follows.created_at'])
            ->each(fn ($r) => $items->push(['type' => 'follow', 'actor' => $r->username, 'actor_id' => $r->uid, 'post_id' => null, 'text' => '', 'created_at' => $this->iso($r->created_at)]));

        $out = $items->sortByDesc('created_at')->take(50)->values();

        return response()->json(['data' => $out]);
    }

    public function block(Request $request, string $username): JsonResponse
    {
        $target = User::where('username', $username)->firstOrFail();
        abort_if($target->id === $request->user()->id, 422, 'You cannot block yourself.');
        DB::table('blocks')->insertOrIgnore(['blocker_id' => $request->user()->id, 'blocked_id' => $target->id, 'created_at' => now(), 'updated_at' => now()]);
        $request->user()->following()->detach($target->id);
        $target->following()->detach($request->user()->id);

        return response()->json(['blocked' => true]);
    }

    public function unblock(Request $request, string $username): JsonResponse
    {
        $target = User::where('username', $username)->firstOrFail();
        DB::table('blocks')->where(['blocker_id' => $request->user()->id, 'blocked_id' => $target->id])->delete();

        return response()->json(['blocked' => false]);
    }

    public function blocks(Request $request): JsonResponse
    {
        $ids = DB::table('blocks')->where('blocker_id', $request->user()->id)->pluck('blocked_id');

        return response()->json(['data' => User::whereIn('id', $ids)->orderBy('username')->get()->map(fn ($u) => Present::user($u))->values()]);
    }

    public function report(Request $request): JsonResponse
    {
        $d = $request->validate([
            'type' => ['required', 'in:post,user,comment'],
            'target' => ['required', 'string', 'max:40'],
            'reason' => ['required', 'in:spam,abuse,nudity,violence,scam,other'],
            'note' => ['nullable', 'string', 'max:300'],
        ]);
        DB::table('reports')->insert([
            'reporter_id' => $request->user()->id, 'target_type' => $d['type'], 'target_id' => $d['target'],
            'reason' => $d['reason'], 'note' => $d['note'] ?? null, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Thanks. We review every report.'], 201);
    }

    public function deleteComment(Request $request, string $commentId): JsonResponse
    {
        $c = Comment::where('public_id', $commentId)->firstOrFail();
        $post = Post::findOrFail($c->post_id);
        abort_unless($c->user_id === $request->user()->id || $post->user_id === $request->user()->id, 403, 'You cannot delete this comment.');
        DB::transaction(function () use ($c, $post) {
            $n = Comment::where('parent_id', $c->id)->count() + 1;
            Comment::where('parent_id', $c->id)->delete();
            $c->delete();
            $post->update(['comments_count' => max(0, $post->comments_count - $n)]);
        });

        return response()->json(['message' => 'Deleted.']);
    }

    private function card(User $u, User $viewer): array
    {
        return Present::user($u) + [
            'following' => $viewer->following()->where('users.id', $u->id)->exists(),
            'follows_you' => DB::table('follows')->where(['follower_id' => $u->id, 'followee_id' => $viewer->id])->exists(),
            'blocked' => DB::table('blocks')->where(['blocker_id' => $viewer->id, 'blocked_id' => $u->id])->exists(),
            'is_me' => $u->id === $viewer->id,
        ];
    }

    private function blocked(User $a, User $b): bool
    {
        return DB::table('blocks')->where(fn ($q) => $q->where(['blocker_id' => $a->id, 'blocked_id' => $b->id]))
            ->orWhere(fn ($q) => $q->where(['blocker_id' => $b->id, 'blocked_id' => $a->id]))->exists();
    }

    private function blockedIds(User $me): array
    {
        return DB::table('blocks')->where('blocker_id', $me->id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $me->id)->pluck('blocker_id'))->all();
    }

    private function iso($v): string
    {
        return \Illuminate\Support\Carbon::parse($v)->toIso8601String();
    }
}
