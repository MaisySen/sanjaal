<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ChatTest extends TestCase
{
    use RefreshDatabase;

    public function test_direct_chat_send_and_poll(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');
        // Same pair returns the same conversation.
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'asha'], $hb)->assertOk()->assertJsonPath('conversation.public_id', $cid);

        $m1 = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'namaste', 'client_id' => 'c1'], $ha)->assertCreated()->json('message.seq');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'k xa', 'client_id' => 'c2'], $hb)->assertCreated();

        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonCount(2, 'data');
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=$m1", $ha)->assertJsonCount(1, 'data')->assertJsonPath('data.0.body', 'k xa');
        $this->getJson('/api/v1/conversations', $ha)->assertJsonPath('data.0.unread', 1)->assertJsonPath('data.0.title', $b->name);
        $this->getJson('/api/v1/notifications/summary', $ha)->assertOk()->assertJsonPath('unread_messages', 1);
        $this->postJson("/api/v1/conversations/$cid/read", [], $ha)->assertOk();
        $this->getJson('/api/v1/conversations', $ha)->assertJsonPath('data.0.unread', 0);
        $this->getJson('/api/v1/notifications/summary', $ha)->assertJsonPath('unread_messages', 0);
    }

    public function test_send_is_idempotent_by_client_id(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'once', 'client_id' => 'same'], $ha)->assertCreated();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'once', 'client_id' => 'same'], $ha)->assertOk();
        $this->getJson("/api/v1/conversations/$cid/messages", $ha)->assertJsonCount(1, 'data');
    }

    public function test_non_member_cannot_read_or_send(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi'], $hc)->assertNotFound();
    }

    public function test_group_chat_and_validation(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $this->member('chandra');
        $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Family', 'usernames' => ['bina', 'chandra']], $ha)
            ->assertCreated()->assertJsonCount(3, 'conversation.members');
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'nobody'], $ha)->assertUnprocessable();
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'asha'], $ha)->assertUnprocessable();
        $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'X', 'usernames' => ['ghost']], $ha)->assertUnprocessable();
    }

    public function test_long_poll_returns_empty_after_wait_when_nothing_new(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $m1 = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi', 'client_id' => 'p1'], $ha)->json('message.seq');
        $t = microtime(true);
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=$m1&wait=1", $ha)->assertOk()->assertJsonCount(0, 'data');
        $this->assertGreaterThan(0.8, microtime(true) - $t);
        $t = microtime(true);
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=0&wait=5", $ha)->assertJsonCount(1, 'data');
        $this->assertLessThan(1.0, microtime(true) - $t);
    }
    public function test_call_token_needs_membership_and_config(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chet');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');

        $this->postJson("/api/v1/conversations/$cid/call-token", [], $ha)->assertStatus(503);

        config(['services.livekit' => ['url' => 'wss://example.livekit.cloud', 'key' => 'APItest', 'secret' => 'secret-for-tests-only-0123456789abcdef']]);
        $r = $this->postJson("/api/v1/conversations/$cid/call-token", [], $ha)->assertOk()->assertJsonPath('room', "convo-$cid");
        [$h, $p, $sig] = explode('.', $r->json('token'));
        $claims = json_decode(base64_decode(strtr($p, '-_', '+/')), true);
        $this->assertSame('APItest', $claims['iss']);
        $this->assertSame("convo-$cid", $claims['video']['room']);
        $this->assertSame(rtrim(strtr(base64_encode(hash_hmac('sha256', "$h.$p", 'secret-for-tests-only-0123456789abcdef', true)), '+/', '-_'), '='), $sig);
        $this->postJson("/api/v1/conversations/$cid/call-token", [], $hc)->assertStatus(404);
    }

}
