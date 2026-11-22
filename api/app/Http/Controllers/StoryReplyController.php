<?php

namespace App\Http\Controllers;

use App\Events\MessageSent;
use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\User;
use App\Support\StoryAudience;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Text-only reply. No story bytes, caption, URL or lasting story access is copied. */
class StoryReplyController extends ChatController
{
    public function reply(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'client_id' => ['required', 'string', 'min:16', 'max:64'],
        ]);
        abort_if(trim($data['body']) === '', 422, 'Write a message first.');
        $replyKey = $data['client_id'];
        // Scope replay to this story without storing its identifier or media.
        $data['client_id'] = hash('sha256', 'story-reply:'.$id.':'.$replyKey);
        $me = $request->user();
        [$message, $replayed] = DB::transaction(function () use ($me, $id, $data) {
            $story = DB::table('stories')->where('public_id', $id)->lockForUpdate()->first();
            abort_unless($story && (int) $story->user_id !== (int) $me->id, 404);
            $owner = User::find($story->user_id);
            abort_unless($owner, 404);
            abort_if($this->cannotContact($me, $owner->id), 404);
            $key = min($me->id, $owner->id).':'.max($me->id, $owner->id);
            // The unique direct key handles another request creating this chat.
            $convo = Conversation::where('direct_key', $key)->lockForUpdate()->first();
            if ($convo) {
                abort_unless($convo->hasMember($me) && $convo->hasMember($owner), 404);
                $dupe = $convo->messages()->withTrashed()->where('user_id', $me->id)->where('client_id', $data['client_id'])->first();
                if ($dupe) {
                    abort_if($dupe->trashed() || $dupe->kind !== 'storyreply' || $dupe->id <= (int) ($convo->members()->where('users.id', $me->id)->first()?->pivot->history_from_id ?? 0), 410);

                    return [$dupe, true];
                }
            }
            abort_unless(Carbon::parse($story->expires_at)->isFuture() && StoryAudience::visible($story, $me->id), 404);
            if (! $convo) {
                $convo = Conversation::createOrFirst(['direct_key' => $key], ['type' => 'direct', 'created_by' => $me->id]);
                $convo = Conversation::whereKey($convo->id)->lockForUpdate()->firstOrFail();
                if ($convo->wasRecentlyCreated || ! $convo->members()->exists()) {
                    $convo->members()->attach([$me->id => ['role' => 'owner'], $owner->id => ['role' => 'member']]);
                }
                abort_unless($convo->hasMember($me) && $convo->hasMember($owner), 404);
            }
            // A concurrent ordinary-chat creation may have won the unique key.
            // The replay key still belongs to the original sender/conversation.
            $dupe = $convo->messages()->withTrashed()->where('user_id', $me->id)->where('client_id', $data['client_id'])->first();
            if ($dupe) {
                abort_if($dupe->trashed() || $dupe->kind !== 'storyreply' || $dupe->id <= (int) ($convo->members()->where('users.id', $me->id)->first()?->pivot->history_from_id ?? 0), 410);

                return [$dupe, true];
            }
            // Recheck after the conversation lock, like ordinary chat sends.
            abort_if($this->cannotContact($me, $owner->id), 404);
            $message = $convo->messages()->create(['user_id' => $me->id, 'body' => $data['body'], 'kind' => 'storyreply', 'client_id' => $data['client_id']]);
            $convo->update(['last_message_at' => $message->created_at]);
            $convo->members()->updateExistingPivot($me->id, ['last_read_message_id' => $message->id]);

            return [$message, false];
        });
        $message->load('user', 'conversation');
        if (! $replayed) {
            try {
                broadcast(new MessageSent($message))->toOthers();
            } catch (\Throwable $e) {
                report($e);
            }
            // Uses the same generic, best-effort chat notification, never reply text.
            $this->push($message->conversation, $me, $message);
        }

        return response()->json(['message' => ['client_id' => $replyKey] + Present::message($message)], $replayed ? 200 : 201);
    }
}
