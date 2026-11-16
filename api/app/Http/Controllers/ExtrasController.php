<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Reactions, stories, chat settings, typing and call history. */
class ExtrasController extends Controller
{
    public const REACTIONS = ['like', 'love', 'laugh', 'wow', 'sad', 'angry'];

    public function react(Request $request, string $postId): JsonResponse
    {
        $data = $request->validate(['type' => ['required', 'in:'.implode(',', self::REACTIONS)]]);
        $post = $this->visiblePost($request, $postId);
        DB::transaction(function () use ($request, $post, $data) {
            $row = $post->likes()->firstOrCreate(['user_id' => $request->user()->id], ['reaction' => $data['type']]);
            if ($row->wasRecentlyCreated) {
                $post->increment('likes_count');
            } else {
                $row->update(['reaction' => $data['type']]);
            }
        });

        return response()->json(Present::reactionState($post->fresh(), $request->user()));
    }

    public function unreact(Request $request, string $postId): JsonResponse
    {
        $post = $this->visiblePost($request, $postId);
        DB::transaction(function () use ($request, $post) {
            if ($post->likes()->where('user_id', $request->user()->id)->delete()) {
                $post->decrement('likes_count');
            }
        });

        return response()->json(Present::reactionState($post->fresh(), $request->user()));
    }

    // ---- stories ----

    private function hiddenIds(User $me)
    {
        return DB::table('blocks')->where('blocker_id', $me->id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $me->id)->pluck('blocker_id'));
    }

    /** Active stories from people I follow and me, grouped by author. */
    public function stories(Request $request): JsonResponse
    {
        $me = $request->user();
        $ids = $me->following()->pluck('users.id')->push($me->id)->diff($this->hiddenIds($me))->values();
        $rows = DB::table('stories')->whereIn('user_id', $ids)->where('expires_at', '>', now())->orderBy('id')->get();
        $viewed = DB::table('story_views')->where('user_id', $me->id)->whereIn('story_id', $rows->pluck('id'))->pluck('story_id')->all();
        $users = User::whereIn('id', $rows->pluck('user_id')->unique())->get()->keyBy('id');
        $groups = $rows->groupBy('user_id')->map(function ($items, $uid) use ($users, $viewed) {
            return [
                'author' => Present::user($users[$uid]),
                'all_viewed' => $items->every(fn ($s) => in_array($s->id, $viewed)),
                'items' => $items->map(fn ($s) => self::story($s, in_array($s->id, $viewed)))->values(),
            ];
        })->values()->sortBy(fn ($g) => [$g['author']['username'] === $me->username ? 0 : 1, $g['all_viewed'] ? 1 : 0])->values();

        return response()->json(['data' => $groups]);
    }

    private static function story($s, bool $viewed): array
    {
        return [
            'public_id' => $s->public_id,
            'url' => url('/api/v1/media/'.$s->media_id),
            'mime' => $s->media_mime,
            'type' => str_starts_with($s->media_mime, 'video/') ? 'video' : 'image',
            'caption' => $s->caption,
            'viewed' => $viewed,
            'created_at' => \Carbon\Carbon::parse($s->created_at)->toIso8601String(),
            'expires_at' => \Carbon\Carbon::parse($s->expires_at)->toIso8601String(),
        ];
    }

    public function storeStory(Request $request): JsonResponse
    {
        $request->validate([
            'media' => ['required', 'file', 'mimes:jpg,jpeg,png,webp,mp4,mov', 'max:25600'],
            'caption' => ['nullable', 'string', 'max:200'],
        ]);
        $file = $request->file('media');
        $blob = (string) Str::uuid();
        $mime = $file->getMimeType();
        \App\Support\MediaStore::putFile($blob, $file);
        $pid = (string) Str::uuid();
        DB::table('stories')->insert([
            'public_id' => $pid, 'user_id' => $request->user()->id, 'media_id' => $blob, 'media_mime' => $mime,
            'caption' => $request->input('caption'), 'expires_at' => now()->addHours(24),
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['story' => self::story(DB::table('stories')->where('public_id', $pid)->first(), false)], 201);
    }

    public function viewStory(Request $request, string $id): JsonResponse
    {
        $s = DB::table('stories')->where('public_id', $id)->where('expires_at', '>', now())->first();
        abort_unless($s, 404);
        abort_if($this->cannotContact($request->user(), $s->user_id), 404);
        DB::table('story_views')->insertOrIgnore(['story_id' => $s->id, 'user_id' => $request->user()->id, 'created_at' => now(), 'updated_at' => now()]);

        return response()->json(['viewed' => true]);
    }

    public function storyViewers(Request $request, string $id): JsonResponse
    {
        $s = DB::table('stories')->where('public_id', $id)->where('user_id', $request->user()->id)->first();
        abort_unless($s, 404);
        $users = User::whereIn('id', DB::table('story_views')->where('story_id', $s->id)->pluck('user_id'))->get();

        return response()->json(['data' => $users->map(fn ($u) => Present::user($u))->values()]);
    }

    public function destroyStory(Request $request, string $id): JsonResponse
    {
        $n = DB::table('stories')->where('public_id', $id)->where('user_id', $request->user()->id)->delete();
        abort_unless($n, 404);

        return response()->json(['deleted' => true]);
    }

    // ---- chat settings and typing ----

    public function settings(Request $request, string $id): JsonResponse
    {
        $convo = Conversation::where('public_id', $id)->firstOrFail();
        abort_unless($convo->hasMember($request->user()), 404);
        $data = $request->validate(['pinned' => ['sometimes', 'boolean'], 'muted' => ['sometimes', 'boolean'], 'archived' => ['sometimes', 'boolean']]);
        if ($data) {
            $convo->members()->updateExistingPivot($request->user()->id, $data);
        }
        $p = $convo->members()->where('users.id', $request->user()->id)->first()->pivot;

        return response()->json(['pinned' => (bool) $p->pinned, 'muted' => (bool) $p->muted, 'archived' => (bool) $p->archived]);
    }

    public function typing(Request $request, string $id): JsonResponse
    {
        $convo = Conversation::where('public_id', $id)->firstOrFail();
        abort_unless($convo->hasMember($request->user()), 404);
        Cache::put("typing:{$convo->id}:{$request->user()->id}", true, 6);

        return response()->json(['ok' => true]);
    }

    public static function typingUsers(Conversation $convo, User $me): array
    {
        $out = [];
        foreach ($convo->members as $m) {
            if ($m->id !== $me->id && Cache::has("typing:{$convo->id}:{$m->id}")) {
                $out[] = $m->username;
            }
        }

        return $out;
    }

    // ---- calls ----

    /** Rings the other members. Called when the app asks for a call token. */
    public static function ring(Conversation $convo, User $me, string $kind): string
    {
        $id = (string) Str::uuid();
        DB::table('calls')->insert([
            'public_id' => $id, 'conversation_id' => $convo->id, 'caller_id' => $me->id, 'kind' => $kind,
            'status' => 'ringing', 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function callRow($c, User $me): array
    {
        $convo = Conversation::with('members')->find($c->conversation_id);
        $caller = User::find($c->caller_id);
        $other = $convo->type === 'direct' ? $convo->members->firstWhere('id', '!=', $me->id) : null;

        return [
            'public_id' => $c->public_id,
            'conversation_id' => $convo->public_id,
            'title' => $convo->type === 'group' ? $convo->title : $other?->publicName(),
            'caller' => Present::user($caller),
            'direction' => $c->caller_id === $me->id ? 'outgoing' : 'incoming',
            'kind' => $c->kind,
            'status' => $c->status,
            'duration_s' => ($c->answered_at && $c->ended_at) ? \Carbon\Carbon::parse($c->answered_at)->diffInSeconds(\Carbon\Carbon::parse($c->ended_at)) : 0,
            'created_at' => \Carbon\Carbon::parse($c->created_at)->toIso8601String(),
        ];
    }

    /** Calls still ringing for me (last 40 s) that I did not start. Poll while the app is open. */
    public function incoming(Request $request): JsonResponse
    {
        $me = $request->user();
        $mine = DB::table('conversation_members')->where('user_id', $me->id)->where('muted', false)->pluck('conversation_id');
        $hidden = $this->hiddenIds($me);
        $rows = DB::table('calls')->whereIn('conversation_id', $mine)->where('caller_id', '!=', $me->id)
            ->whereNotIn('caller_id', $hidden)->where('status', 'ringing')->where('created_at', '>', now()->subSeconds(40))
            ->orderByDesc('id')->limit(1)->get();

        return response()->json(['data' => $rows->map(fn ($c) => $this->callRow($c, $me))->values()]);
    }

    public function callStatus(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['action' => ['required', 'in:answer,decline,end']]);
        $me = $request->user();
        $c = DB::table('calls')->where('public_id', $id)->first();
        abort_unless($c, 404);
        abort_unless(DB::table('conversation_members')->where('conversation_id', $c->conversation_id)->where('user_id', $me->id)->exists(), 404);
        $upd = ['updated_at' => now()];
        if ($data['action'] === 'answer' && $c->status === 'ringing') {
            $upd += ['status' => 'answered', 'answered_at' => now()];
        } elseif ($data['action'] === 'decline' && $c->status === 'ringing') {
            $upd += ['status' => 'declined', 'ended_at' => now()];
        } elseif ($data['action'] === 'end') {
            $upd += $c->status === 'ringing' ? ['status' => 'missed', 'ended_at' => now()] : ['status' => 'ended', 'ended_at' => now()];
        }
        DB::table('calls')->where('id', $c->id)->update($upd);

        return response()->json(['call' => $this->callRow(DB::table('calls')->find($c->id), $me)]);
    }

    public function history(Request $request): JsonResponse
    {
        $me = $request->user();
        $mine = DB::table('conversation_members')->where('user_id', $me->id)->pluck('conversation_id');
        // A ringing call older than 40 s was never answered.
        DB::table('calls')->whereIn('conversation_id', $mine)->where('status', 'ringing')->where('created_at', '<', now()->subSeconds(40))
            ->update(['status' => 'missed', 'ended_at' => now()]);
        $rows = DB::table('calls')->whereIn('conversation_id', $mine)->orderByDesc('id')->limit(60)->get();

        return response()->json(['data' => $rows->map(fn ($c) => $this->callRow($c, $me))->values()]);
    }
}
