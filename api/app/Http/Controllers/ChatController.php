<?php

namespace App\Http\Controllers;

use App\Events\MessageSent;
use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\Message;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ChatController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $me = $request->user();
        $convos = Conversation::whereHas('members', fn ($m) => $m->where('users.id', $me->id))
            ->with('members')->orderByDesc('last_message_at')->orderByDesc('id')->limit(100)->get();

        // The list costs a fixed handful of reads however many chats there are: the older per-chat last-message,
        // unread-count and blocked-author reads are batched here. Same visibility rules, nothing cached.
        $ids = $convos->pluck('id')->all();
        $member = fn () => Message::query()->join('conversation_members as cm', 'cm.conversation_id', '=', 'messages.conversation_id')
            ->where('cm.user_id', $me->id)->whereIn('messages.conversation_id', $ids)->groupBy('messages.conversation_id');
        $lastIds = $ids ? $member()->whereRaw('messages.id > coalesce(cm.history_from_id, 0)')->selectRaw('max(messages.id) as mid')->pluck('mid')->all() : [];
        $lasts = $lastIds ? Message::with('user', 'conversation')->whereIn('id', $lastIds)->get()->keyBy('conversation_id') : collect();
        $unread = $ids ? $member()->where('messages.user_id', '!=', $me->id)
            ->whereRaw('messages.id > coalesce(cm.last_read_message_id, 0)')->whereRaw('messages.id > coalesce(cm.history_from_id, 0)')
            ->selectRaw('messages.conversation_id as cid, count(*) as n')->pluck('n', 'cid') : collect();
        $hidden = $lasts->isEmpty() ? [] : Present::hiddenAuthors([$me->id]);
        // Shared-post cards and reply previews on those last messages are read together too (same finders, same soft-delete rules).
        $postIds = $lasts->pluck('shared_post_id')->filter()->unique()->all();
        $replyIds = $lasts->pluck('reply_to_id')->filter()->unique()->all();
        $pre = [
            'posts' => $postIds ? Post::with('user', 'media')->whereIn('id', $postIds)->get()->keyBy('id')->all() : [],
            'replies' => $replyIds ? Message::with('user')->whereIn('id', $replyIds)->get()->keyBy('id')->all() : [],
        ];
        $rows = $convos->map(fn ($c) => $this->present($c, $me, $lasts->get($c->id), (int) ($unread[$c->id] ?? 0), $hidden, $pre))->values();
        $rows = $request->boolean('archived') ? $rows->where('archived', true) : $rows->where('archived', false);
        // Pinned chats first, otherwise keep newest-first order.
        $rows = $rows->sortBy(fn ($r) => $r['pinned'] ? 0 : 1)->values();

        return response()->json(['data' => $rows]);
    }

    /** Join token for a voice or video call in a conversation the caller belongs to. */
    public function callToken(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if ($convo->type === 'direct') {
            $other = $convo->members()->where('users.id', '!=', $request->user()->id)->value('users.id');
            abort_if($other && $this->cannotContact($request->user(), $other), 404);
        }
        if (! \App\Services\LiveKit::configured()) {
            return response()->json(['message' => 'Calls are not available yet.'], 503);
        }
        $me = $request->user();
        $existing = null;
        if ($request->query->has('call')) {
            $selected = DB::table('calls')->where('public_id', $request->query('call'))->where('conversation_id', $convo->id)->first();
            abort_unless($selected, 404);
            abort_unless(in_array($selected->status, ['ringing', 'answered'], true), 410);
            abort_if($selected->status === 'ringing' && \Carbon\Carbon::parse($selected->created_at)->lte(now()->subSeconds(40)), 410);
            // A recipient cannot bypass answering by requesting a token directly.
            abort_if((int) $selected->caller_id !== (int) $me->id && $selected->status !== 'answered', 409);
            $existing = $selected->public_id;
        }
        $call = $existing ?: \App\Http\Controllers\ExtrasController::ring($convo, $me, $request->query('kind') === 'video' ? 'video' : 'voice');

        return response()->json([
            'call_id' => $call,
            'url' => config('services.livekit.url'),
            'room' => 'convo-'.$convo->public_id,
            'token' => \App\Services\LiveKit::token('u'.$me->id, $me->publicName(), 'convo-'.$convo->public_id),
        ]);
    }

    /** Cheap poll target for the app badge: unread chat messages across all conversations. */
    public function summary(Request $request): JsonResponse
    {
        $me = $request->user();
        $unread = DB::table('messages')
            ->join('conversation_members', 'conversation_members.conversation_id', '=', 'messages.conversation_id')
            ->where('conversation_members.user_id', $me->id)
            ->where('messages.user_id', '!=', $me->id)
            ->whereRaw('messages.id > COALESCE(conversation_members.last_read_message_id, 0)')
            ->count();

        return response()->json(['unread_messages' => $unread]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => ['required', 'in:direct,group'],
            'username' => ['required_if:type,direct', 'string'],
            'title' => ['required_if:type,group', 'nullable', 'string', 'max:80'],
            'usernames' => ['required_if:type,group', 'array', 'min:1', 'max:49'],
            'usernames.*' => ['string'],
            'member_refs' => ['sometimes', 'array', 'min:1', 'max:49'],
            'member_refs.*.public_id' => ['required_with:member_refs', 'uuid', 'distinct'],
            'member_refs.*.username' => ['required_with:member_refs', 'string', 'max:80', 'distinct'],
        ]);
        $me = $request->user();

        if ($data['type'] === 'direct') {
            $other = User::where('username', $data['username'])->first();
            if (! $other) {
                return response()->json(['message' => 'User not found.', 'errors' => ['username' => ['User not found.']]], 422);
            }
            if ($other->id === $me->id) {
                return response()->json(['message' => 'You cannot message yourself.', 'errors' => ['username' => ['You cannot message yourself.']]], 422);
            }
            abort_if($this->cannotContact($me, $other->id), 404);
            $key = min($me->id, $other->id).':'.max($me->id, $other->id);
            $existing = Conversation::where('direct_key', $key)->first();
            if ($existing) {
                return response()->json(['conversation' => $this->present($existing->load('members'), $me)]);
            }
            $convo = DB::transaction(function () use ($me, $other, $key) {
                $c = Conversation::create(['type' => 'direct', 'direct_key' => $key, 'created_by' => $me->id]);
                $c->members()->attach([$me->id => ['role' => 'owner'], $other->id => ['role' => 'member']]);

                return $c;
            });

            return response()->json(['conversation' => $this->present($convo->load('members'), $me)], 201);
        }

        if (isset($data['member_refs'])) {
            // Saved selections bind stable IDs, not whoever owns an old username
            // at creation time. No fallback to username-only resolution.
            $refs = collect($data['member_refs']);
            $names = collect($data['usernames']);
            if ($names->count() !== $names->unique()->count() || $refs->pluck('username')->sort()->values()->all() !== $names->sort()->values()->all()) {
                return response()->json(['message' => 'Selected people changed. Find them again.'], 422);
            }
            $others = User::whereIn('public_id', $refs->pluck('public_id'))->where('id', '!=', $me->id)->get();
            if ($others->count() !== $refs->count() || $refs->contains(fn ($ref) => ! $others->contains(fn ($u) => $u->public_id === $ref['public_id'] && $u->username === $ref['username']))) {
                return response()->json(['message' => 'Selected people changed. Find them again.'], 422);
            }
        } else {
            $others = User::whereIn('username', $data['usernames'])->where('id', '!=', $me->id)->get();
            if ($others->count() !== collect($data['usernames'])->unique()->reject(fn ($u) => $u === $me->username)->count()) {
                return response()->json(['message' => 'One or more users were not found.', 'errors' => ['usernames' => ['One or more users were not found.']]], 422);
            }
        }
        abort_if($others->contains(fn ($u) => $this->cannotContact($me, $u->id)), 404);
        $convo = DB::transaction(function () use ($me, $others, $data) {
            $c = Conversation::create(['type' => 'group', 'title' => $data['title'], 'created_by' => $me->id]);
            $c->members()->attach($me->id, ['role' => 'owner']);
            $c->members()->attach($others->pluck('id')->all(), ['role' => 'member']);

            return $c;
        });

        return response()->json(['conversation' => $this->present($convo->load('members'), $me)], 201);
    }

    /** Any member of a group can add people by username, up to 50 members in total. */
    public function addMembers(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if ($convo->type !== 'group') {
            return response()->json(['message' => 'Only groups have a member list.'], 422);
        }
        $data = $request->validate([
            'usernames' => ['required', 'array', 'min:1', 'max:49'],
            'usernames.*' => ['string'],
        ]);
        $me = $request->user();
        $wanted = collect($data['usernames'])->unique()->reject(fn ($u) => $u === $me->username)->values();
        $users = User::whereIn('username', $wanted)->get();
        if ($users->count() !== $wanted->count()) {
            return response()->json(['message' => 'One or more users were not found.', 'errors' => ['usernames' => ['One or more users were not found.']]], 422);
        }
        $blocked = DB::table('blocks')->where('blocker_id', $me->id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $me->id)->pluck('blocker_id'))->all();
        $over = DB::transaction(function () use ($convo, $users, $blocked) {
            // Lock the conversation row so two invitations cannot both pass the capacity check.
            Conversation::whereKey($convo->id)->lockForUpdate()->first();
            $existing = $convo->members()->pluck('users.id')->all();
            $fresh = $users->reject(fn ($u) => in_array($u->id, $existing, true) || in_array($u->id, $blocked, true));
            if (count($existing) + $fresh->count() > 50) {
                return true;
            }
            if ($fresh->isNotEmpty()) {
                // New members see messages from now on, not the history from before they joined.
                $from = (int) $convo->messages()->max('id');
                $convo->members()->attach($fresh->pluck('id')->all(), ['role' => 'member', 'history_from_id' => $from, 'last_read_message_id' => $from]);
            }

            return false;
        });
        if ($over) {
            return response()->json(['message' => 'A group can have at most 50 members.', 'errors' => ['usernames' => ['A group can have at most 50 members.']]], 422);
        }

        return response()->json(['conversation' => $this->present($convo->load('members'), $me)]);
    }

    /** Leave a group. If the owner leaves, the longest standing member becomes owner. */
    /** Only the group owner renames. The role is read after the lock, like leave(), so a handoff cannot race. */
    public function rename(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if ($convo->type !== 'group') {
            return response()->json(['message' => 'Only groups have a name.'], 422);
        }
        $data = $request->validate(['title' => ['required', 'string', 'min:1', 'max:80']]);
        $title = trim(preg_replace('/\s+/u', ' ', $data['title']));
        if ($title === '') {
            return response()->json(['message' => 'The group name cannot be empty.', 'errors' => ['title' => ['The group name cannot be empty.']]], 422);
        }
        $me = $request->user();
        $ok = DB::transaction(function () use ($convo, $me, $title) {
            Conversation::whereKey($convo->id)->lockForUpdate()->first();
            if (! $convo->members()->where('users.id', $me->id)->wherePivot('role', 'owner')->exists()) {
                return false;
            }
            $convo->forceFill(['title' => $title])->save();

            return true;
        });
        if (! $ok) {
            return response()->json(['message' => 'Only the group owner can rename it.'], 403);
        }

        return response()->json(['conversation' => $this->present($convo->fresh('members'), $me)]);
    }

    public function leave(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if ($convo->type !== 'group') {
            return response()->json(['message' => 'You can only leave a group.'], 422);
        }
        $me = $request->user();
        DB::transaction(function () use ($convo, $me) {
            Conversation::whereKey($convo->id)->lockForUpdate()->first();
            // Read the role only after the lock: another leave may have just promoted this member to owner.
            $wasOwner = $convo->members()->where('users.id', $me->id)->wherePivot('role', 'owner')->exists();
            $convo->members()->detach($me->id);
            if (! $convo->members()->exists()) {
                // Current private uploads are DB-only. Clean their bytes in the
                // same transaction; legacy B2 cleanup stays a separate review.
                $media = $convo->messages()->withTrashed()->whereNotNull('media_id')->pluck('media_id');
                DB::table('media_blobs')->whereIn('public_id', $media)->where('storage', 'db')->delete();
                $convo->messages()->delete();
                $convo->delete();

                return;
            }
            if ($wasOwner) {
                $next = $convo->members()->orderBy('conversation_members.created_at')->orderBy('users.id')->first();
                if ($next) {
                    $convo->members()->updateExistingPivot($next->id, ['role' => 'owner']);
                }
            }
        });

        return response()->json(['left' => true]);
    }

    /** ?after_seq=N returns newer messages (polling fallback); ?before_seq=N pages older. */
    public function messages(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        $from = (int) ($convo->members()->where('users.id', $request->user()->id)->first()?->pivot->history_from_id ?? 0);
        $hiddenAuthors = Present::hiddenAuthors([$request->user()->id]);
        $q = $convo->messages()->with('user', 'conversation')->where('id', '>', $from);
        if ($request->filled('after_seq')) {
            $after = (int) $request->after_seq;
            // Long poll: hold the request open (up to 20 s) until a newer message exists.
            $deadline = microtime(true) + min(max((int) $request->query('wait', 0), 0), 20);
            $convo->loadMissing('members');
            $shown = array_filter(explode(',', (string) $request->query('typing', '')));
            do {
                $msgs = (clone $q)->where('id', '>', $after)->orderBy('id')->limit(100)->get();
                $nowTyping = ExtrasController::typingUsers($convo, $request->user());
                if ($msgs->isNotEmpty() || $nowTyping != $shown || microtime(true) >= $deadline) {
                    break;
                }
                usleep(400000);
            } while (true);
        } else {
            if ($request->filled('before_seq')) {
                $q->where('id', '<', (int) $request->before_seq);
            }
            $msgs = $q->orderByDesc('id')->limit(50)->get()->reverse()->values();
        }

        $convo->load('members');
        // Shared-post cards and reply previews of the page are read together (same finders and soft-delete rules as before).
        $postIds = $msgs->pluck('shared_post_id')->filter()->unique()->all();
        $replyIds = $msgs->pluck('reply_to_id')->filter()->unique()->all();
        $pre = [
            'posts' => $postIds ? Post::with('user', 'media')->whereIn('id', $postIds)->get()->keyBy('id')->all() : [],
            'replies' => $replyIds ? Message::with('user')->whereIn('id', $replyIds)->get()->keyBy('id')->all() : [],
        ];

        return response()->json([
            'data' => $msgs->map(fn ($m) => Present::message($m, $from, $hiddenAuthors, $pre))->values(),
            'typing' => ExtrasController::typingUsers($convo, $request->user()),
        ]);
    }

    public function send(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if ($convo->type === 'direct') {
            $other = $convo->members()->where('users.id', '!=', $request->user()->id)->value('users.id');
            abort_if($other && $this->cannotContact($request->user(), $other), 404);
        }
        $data = $request->validate([
            'body' => ['required_without_all:media,shared_post', 'nullable', 'string', 'max:4000'],
            'shared_post' => ['nullable', 'uuid'],
            'client_id' => ['nullable', 'string', 'max:64'],
            'media' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp,m4a,aac,mp3,ogg,wav,mp4', 'max:10240'],
            'duration_ms' => ['nullable', 'integer', 'min:0', 'max:600000'],
            'reply_to' => ['nullable', 'uuid'],
        ]);
        $me = $request->user();
        [$msg, $replayed, $myFrom] = DB::transaction(function () use ($convo, $me, $data, $request) {
            // Leave/add also lock the conversation. Recheck membership only after
            // acquiring it so a queued send cannot act as a departed member.
            $convo = Conversation::whereKey($convo->id)->lockForUpdate()->firstOrFail();
            abort_unless($convo->hasMember($me), 404);
            if ($convo->type === 'direct') {
                $other = $convo->members()->where('users.id', '!=', $me->id)->value('users.id');
                abort_if($other && $this->cannotContact($me, $other), 404);
            }
            $myFrom = (int) ($convo->members()->where('users.id', $me->id)->first()?->pivot->history_from_id ?? 0);
            if (! empty($data['client_id'])) {
                $dupe = $convo->messages()->withTrashed()->where('user_id', $me->id)->where('client_id', $data['client_id'])->first();
                if ($dupe) {
                    abort_if($dupe->trashed() || $dupe->id <= $myFrom, 410, 'The original message is no longer available.');
                    return [$dupe, true, $myFrom];
                }
            }
            $sharedId = null;
            $kind = 'text';
            if (! empty($data['shared_post'])) {
                $sp = \App\Models\Post::where('public_id', $data['shared_post'])->first();
                abort_if(! $sp || in_array($sp->user_id, Present::hiddenAuthors([$me->id]), true), 422, 'That post is not available to share.');
                DB::table('users')->where('id', $sp->user_id)->lockForUpdate()->first();
                abort_unless(\App\Support\MemberControls::canShare($sp->user_id, $me->id), 403, 'This member has turned off sharing to chat.');
                $sharedId = $sp->id;
                $kind = 'post';
            }
            $replyTo = ! empty($data['reply_to']) ? $convo->messages()->where('public_id', $data['reply_to'])->where('id', '>', $myFrom)->value('id') : null;
            $mediaId = null;
            $mediaMime = null;
            if ($file = $request->file('media')) {
                $mediaMime = $file->getMimeType();
                $kind = str_starts_with($mediaMime, 'image/') ? 'image' : 'voice';
                $mediaId = (string) \Illuminate\Support\Str::uuid();
                // Private bytes are DB-only and commit with their message. A
                // rejected or replayed send must not leave an unreferenced blob.
                \App\Support\MediaStore::putFile($mediaId, $file, private: true);
            }
            $m = $convo->messages()->create([
                'user_id' => $me->id, 'body' => $data['body'] ?? '', 'client_id' => $data['client_id'] ?? null,
                'kind' => $kind, 'media_id' => $mediaId, 'media_mime' => $mediaMime,
                'duration_ms' => $data['duration_ms'] ?? null, 'reply_to_id' => $replyTo, 'shared_post_id' => $sharedId,
            ]);
            $convo->update(['last_message_at' => $m->created_at]);
            $convo->members()->updateExistingPivot($me->id, ['last_read_message_id' => $m->id]);
            return [$m, false, $myFrom];
        });
        $msg->load('user', 'conversation');
        if ($replayed) {
            return response()->json(['message' => Present::message($msg, $myFrom, Present::hiddenAuthors([$me->id]))]);
        }


        try {
            broadcast(new MessageSent($msg))->toOthers();
        } catch (\Throwable $e) {
            report($e); // Realtime is best effort. Clients fall back to polling.
        }

        $this->push($convo, $me, $msg);

        return response()->json(['message' => Present::message($msg)], 201);
    }

    /**
     * Best effort push to the other members who have not muted the chat and are not blocked either way.
     * The text on the lock screen is generic on purpose: no message content leaves the server in a push.
     * Runs after the response, and a failure never affects the send.
     */
    private function push(Conversation $convo, User $me, $msg): void
    {
        $blocked = DB::table('blocks')->where('blocker_id', $me->id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $me->id)->pluck('blocker_id'))->all();
        $ids = $convo->members()->where('users.id', '!=', $me->id)->wherePivot('muted', false)->pluck('users.id')
            ->reject(fn ($id) => in_array($id, $blocked))->values()->all();
        if ($ids === []) {
            return;
        }
        $title = $convo->type === 'group' && $convo->title ? $convo->title : $me->name;
        $body = match ($msg->kind) {
            'voice' => 'Voice message',
            'image' => 'Photo',
            default => 'New message',
        };
        app()->terminating(function () use ($ids, $title, $body, $convo) {
            try {
                app(\App\Services\Push::class)->toUsers($ids, $title, $body, ['type' => 'message', 'conversation' => $convo->public_id]);
            } catch (\Throwable $e) {
                report($e);
            }
        });
    }

    public function read(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        $last = (int) $convo->messages()->max('id');
        $convo->members()->updateExistingPivot($request->user()->id, ['last_read_message_id' => $last]);

        return response()->json(['last_read_seq' => $last]);
    }

    private function authorized(Request $request, string $publicId): Conversation
    {
        $convo = Conversation::where('public_id', $publicId)->firstOrFail();
        abort_unless($convo->hasMember($request->user()), 404);

        return $convo;
    }

    private function present(Conversation $c, User $me, ?Message $batchedLast = null, ?int $batchedUnread = null, ?array $hidden = null, ?array $pre = null): array
    {
        $pivot = $c->members->firstWhere('id', $me->id)?->pivot;
        $last = $batchedUnread !== null ? $batchedLast : $c->messages()->with('user', 'conversation')->where('id', '>', $pivot?->history_from_id ?? 0)->latest('id')->first();
        $other = $c->type === 'direct' ? $c->members->firstWhere('id', '!=', $me->id) : null;

        return [
            'public_id' => $c->public_id,
            'type' => $c->type,
            'title' => $c->type === 'group' ? $c->title : $other?->publicName(),
            'members' => $c->members->map(fn ($u) => Present::user($u))->values(),
            'last_message' => $last ? Present::message($last, (int) ($pivot?->history_from_id ?? 0), $hidden ?? Present::hiddenAuthors([$me->id]), $pre) : null,
            'my_role' => $c->type === 'group' ? ($pivot?->role ?? 'member') : null,
            'pinned' => (bool) ($pivot?->pinned), 'muted' => (bool) ($pivot?->muted), 'archived' => (bool) ($pivot?->archived),
            'unread' => $batchedUnread ?? $c->messages()->where('id', '>', max($pivot?->last_read_message_id ?? 0, $pivot?->history_from_id ?? 0))->where('user_id', '!=', $me->id)->count(),
        ];
    }
}
