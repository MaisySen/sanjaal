<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SocketAuthTest extends TestCase
{
    use RefreshDatabase;

    private function auth(array $h, string $cid)
    {
        return $this->postJson('/api/v1/broadcasting/auth', ['socket_id' => '1234.5678', 'channel_name' => 'private-conversation.'.$cid], $h);
    }

    /** The phpunit environment uses the null broadcaster, which approves every channel, so use the real driver with dummy keys. */
    public function test_only_current_members_can_join_a_conversation_channel(): void
    {
        config(['broadcasting.default' => 'reverb', 'broadcasting.connections.reverb.key' => 'k', 'broadcasting.connections.reverb.secret' => 's', 'broadcasting.connections.reverb.app_id' => '1']);
        // Channels were registered on the null driver at boot, so register them on the driver now in use.
        require base_path('routes/channels.php');
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'T', 'usernames' => ['bina']], $ha)->assertCreated()->json('conversation.public_id');

        // Positive control: a member gets a signed token.
        $ok = $this->auth($hb, $cid)->assertOk();
        $this->assertStringContainsString('auth', $ok->getContent());
        // Negative: an outsider is refused, and so is a conversation that does not exist.
        $this->auth($hc, $cid)->assertForbidden();
        $this->auth($ha, (string) \Illuminate\Support\Str::uuid())->assertForbidden();
        // Joined people can; people who leave cannot get a new token.
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $ha)->assertOk();
        $this->auth($hc, $cid)->assertOk();
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hc)->assertOk();
        $this->auth($hc, $cid)->assertForbidden();
        // No token at all is refused.
        $this->postJson('/api/v1/broadcasting/auth', ['socket_id' => '1234.5678', 'channel_name' => 'private-conversation.'.$cid])->assertUnauthorized();
    }
}
