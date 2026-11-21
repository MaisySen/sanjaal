<?php

namespace Tests\Feature;

use App\Http\Controllers\ExtrasController;
use App\Models\Conversation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Synthetic database only. No LiveKit network connection or real calls. */
class CallReconciliationTest extends TestCase
{
    use RefreshDatabase;

    private function fixtureCall(): array
    {
        [$caller, $callerHeaders] = $this->member('caller');
        [$recipient, $recipientHeaders] = $this->member('recipient');
        [, $outsiderHeaders] = $this->member('outsider');
        $conversation = $this->postJson('/api/v1/conversations', [
            'type' => 'direct', 'username' => 'recipient',
        ], $callerHeaders)->assertCreated()->json('conversation.public_id');
        $call = ExtrasController::ring(Conversation::where('public_id', $conversation)->first(), $caller, 'voice');

        return [$call, $conversation, $callerHeaders, $recipientHeaders, $outsiderHeaders];
    }

    public function test_exact_call_state_requires_membership_and_does_not_create_a_call(): void
    {
        [$call, , , $recipient, $outsider] = $this->fixtureCall();
        $count = DB::table('calls')->count();
        $this->getJson("/api/v1/calls/$call", $recipient)->assertOk()
            ->assertJsonPath('call.public_id', $call)->assertJsonPath('call.status', 'ringing')
            ->assertJsonStructure(['call' => ['ring_expires_at']]);
        $this->getJson("/api/v1/calls/$call", $outsider)->assertNotFound();
        $this->getJson('/api/v1/calls/missing-fixture', $recipient)->assertNotFound();
        $this->assertSame($count, DB::table('calls')->count());
    }

    public function test_conflicting_late_actions_cannot_overwrite_an_answer_or_terminal_state(): void
    {
        [$call, , $caller, $recipient] = $this->fixtureCall();
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'answer'], $recipient)
            ->assertOk()->assertJsonPath('call.status', 'answered');
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'decline'], $recipient)
            ->assertOk()->assertJsonPath('call.status', 'answered');
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'end'], $caller)
            ->assertOk()->assertJsonPath('call.status', 'ended');
        $ended = DB::table('calls')->where('public_id', $call)->value('ended_at');
        $this->travel(5)->seconds();
        foreach (['answer', 'decline', 'end'] as $action) {
            $this->postJson("/api/v1/calls/$call/action", ['action' => $action], $recipient)
                ->assertOk()->assertJsonPath('call.status', 'ended');
        }
        $this->assertSame($ended, DB::table('calls')->where('public_id', $call)->value('ended_at'));
    }

    public function test_expired_ring_is_never_represented_or_accepted_as_a_live_ring(): void
    {
        [$call, , , $recipient] = $this->fixtureCall();
        $this->travel(41)->seconds();
        $this->getJson("/api/v1/calls/$call", $recipient)->assertOk()->assertJsonPath('call.status', 'missed');
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'answer'], $recipient)
            ->assertOk()->assertJsonPath('call.status', 'missed');
        $this->assertNull(DB::table('calls')->where('public_id', $call)->value('answered_at'));
    }

    public function test_explicit_call_token_request_cannot_create_a_replacement_or_join_terminal_call(): void
    {
        [$call, $conversation, , $recipient] = $this->fixtureCall();
        config(['services.livekit.url' => 'wss://fixture.invalid', 'services.livekit.key' => 'fixture-key',
            'services.livekit.secret' => 'fixture-secret-not-a-real-credential']);
        $count = DB::table('calls')->count();
        $this->postJson("/api/v1/conversations/$conversation/call-token?call=missing-fixture", [], $recipient)
            ->assertNotFound();
        $this->postJson("/api/v1/conversations/$conversation/call-token?call=$call", [], $recipient)
            ->assertStatus(409);
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'decline'], $recipient)->assertOk();
        $this->postJson("/api/v1/conversations/$conversation/call-token?call=$call", [], $recipient)
            ->assertStatus(410);
        $this->assertSame($count, DB::table('calls')->count());
    }
}
