<?php

namespace App\Services;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/** Shared native wake contract. No token, caller name, content or media grant. */
class CallWake
{
    public const VERSION = '1';

    /** Current eligible recipient envelopes only. Does not send or activate a provider. */
    public function recipients(string $callId): array
    {
        $call = DB::table('calls')->where('public_id', $callId)->first();
        if (! $call || $call->status !== 'ringing') {
            return [];
        }
        $created = CarbonImmutable::parse($call->created_at);
        $expires = $created->addSeconds(40);
        if ($created->isFuture() || ! $expires->isFuture()) {
            return [];
        }
        $conversation = DB::table('conversations')->where('id', $call->conversation_id)->first();
        if (! $conversation || ! in_array($call->kind, ['voice', 'video'], true)) {
            return [];
        }
        if (! DB::table('conversation_members')->where('conversation_id', $call->conversation_id)->where('user_id', $call->caller_id)->exists()) {
            return [];
        }
        $blocked = DB::table('blocks')->where('blocker_id', $call->caller_id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $call->caller_id)->pluck('blocker_id'));
        return DB::table('conversation_members as member')->join('users', 'users.id', '=', 'member.user_id')
            ->where('member.conversation_id', $call->conversation_id)->where('member.muted', false)
            ->where('member.user_id', '!=', $call->caller_id)->whereNotIn('member.user_id', $blocked)
            ->orderBy('member.user_id')->get(['users.id', 'users.public_id'])->map(fn ($user) => [
                'user_id' => $user->id,
                'data' => ['type' => 'incoming_call', 'call_version' => self::VERSION,
                    'recipient' => $user->public_id, 'call' => $call->public_id,
                    'conversation' => $conversation->public_id, 'kind' => $call->kind,
                    'issued_at' => (string) $created->timestamp, 'expires_at' => (string) $expires->timestamp],
            ])->all();
    }
}
