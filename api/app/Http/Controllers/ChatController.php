<?php

namespace App\Http\Controllers;

use App\Events\MessageSent;
use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\Message;
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

        $rows = $convos->map(fn ($c) => $this->present($c, $me))->values();
        $rows = $request->boolean('archived') ? $rows->where('archived', true) : $rows->where('archived', false);
        // Pinned chats first, otherwise keep newest-first order.
        $rows = $rows->sortBy(fn ($r) => $r['pinned'] ? 0 : 1)->values();

        return response()->json(['data' => $rows]);
    }

    /** Join token for a voice or video call in a conversation the caller belongs to. */
    public function callToken(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        if (! \App\Services\LiveKit::configured()) {
            return response()->json(['message' => 'Calls are not available yet.'], 503);
        }
        $me = $request->user();
        $existing = $request->query('call') ? DB::table('calls')->where('public_id', $request->query('call'))->where('conversation_id', $convo->id)->value('public_id') : null;
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

        $others = User::whereIn('username', $data['usernames'])->where('id', '!=', $me->id)->get();
        if ($others->count() !== collect($data['usernames'])->unique()->reject(fn ($u) => $u === $me->username)->count()) {
            return response()->json(['message' => 'One or more users were not found.', 'errors' => ['usernames' => ['One or more users were not found.']]], 422);
        }
        $convo = DB::transaction(function () use ($me, $others, $data) {
            $c = Conversation::create(['type' => 'group', 'title' => $data['title'], 'created_by' => $me->id]);
            $c->members()->attach($me->id, ['role' => 'owner']);
            $c->members()->attach($others->pluck('id')->all(), ['role' => 'member']);

            return $c;
        });

        return response()->json(['conversation' => $this->present($convo->load('members'), $me)], 201);
    }

    /** ?after_seq=N returns newer messages (polling fallback); ?before_seq=N pages older. */
    public function messages(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        $q = $convo->messages()->with('user', 'conversation');
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

        return response()->json([
            'data' => $msgs->map(fn ($m) => Present::message($m))->values(),
            'typing' => ExtrasController::typingUsers($convo, $request->user()),
        ]);
    }

    public function send(Request $request, string $id): JsonResponse
    {
        $convo = $this->authorized($request, $id);
        $data = $request->validate([
            'body' => ['required_without:media', 'nullable', 'string', 'max:4000'],
            'client_id' => ['nullable', 'string', 'max:64'],
            'media' => ['nullable', 'file', 'mimes:jpg,jpeg,png,webp,m4a,aac,mp3,ogg,wav,mp4', 'max:10240'],
            'duration_ms' => ['nullable', 'integer', 'min:0', 'max:600000'],
            'reply_to' => ['nullable', 'uuid'],
        ]);
        $me = $request->user();
        $kind = 'text';
        $mediaId = null;
        $mediaMime = null;
        if ($file = $request->file('media')) {
            $mediaMime = $file->getMimeType();
            $kind = str_starts_with($mediaMime, 'image/') ? 'image' : 'voice';
            $mediaId = (string) \Illuminate\Support\Str::uuid();
            \App\Support\MediaStore::putFile($mediaId, $file);
        }
        $replyTo = ! empty($data['reply_to']) ? $convo->messages()->where('public_id', $data['reply_to'])->value('id') : null;

        if (! empty($data['client_id'])) {
            $dupe = $convo->messages()->where('user_id', $me->id)->where('client_id', $data['client_id'])->first();
            if ($dupe) {
                return response()->json(['message' => Present::message($dupe->load('user', 'conversation'))]);
            }
        }

        $msg = DB::transaction(function () use ($convo, $me, $data, $kind, $mediaId, $mediaMime, $replyTo) {
            $m = $convo->messages()->create([
                'user_id' => $me->id, 'body' => $data['body'] ?? '', 'client_id' => $data['client_id'] ?? null,
                'kind' => $kind, 'media_id' => $mediaId, 'media_mime' => $mediaMime,
                'duration_ms' => $data['duration_ms'] ?? null, 'reply_to_id' => $replyTo,
            ]);
            $convo->update(['last_message_at' => $m->created_at]);
            $convo->members()->updateExistingPivot($me->id, ['last_read_message_id' => $m->id]);

            return $m;
        });
        $msg->load('user', 'conversation');

        try {
            broadcast(new MessageSent($msg))->toOthers();
        } catch (\Throwable $e) {
            report($e); // Realtime is best effort. Clients fall back to polling.
        }

        return response()->json(['message' => Present::message($msg)], 201);
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

    private function present(Conversation $c, User $me): array
    {
        $last = $c->messages()->with('user', 'conversation')->latest('id')->first();
        $pivot = $c->members->firstWhere('id', $me->id)?->pivot;
        $other = $c->type === 'direct' ? $c->members->firstWhere('id', '!=', $me->id) : null;

        return [
            'public_id' => $c->public_id,
            'type' => $c->type,
            'title' => $c->type === 'group' ? $c->title : $other?->publicName(),
            'members' => $c->members->map(fn ($u) => Present::user($u))->values(),
            'last_message' => $last ? Present::message($last) : null,
            'pinned' => (bool) ($pivot?->pinned), 'muted' => (bool) ($pivot?->muted), 'archived' => (bool) ($pivot?->archived),
            'unread' => $c->messages()->where('id', '>', $pivot?->last_read_message_id ?? 0)->where('user_id', '!=', $me->id)->count(),
        ];
    }
}
