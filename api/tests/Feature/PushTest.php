<?php

namespace Tests\Feature;

use App\Services\Push;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PushTest extends TestCase
{
    use RefreshDatabase;

    private function fakeCreds(): string
    {
        $res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        openssl_pkey_export($res, $pem);

        return json_encode(['client_email' => 'push@test-project.iam.example', 'private_key' => $pem, 'project_id' => 'test-project']);
    }

    public function test_off_without_credentials(): void
    {
        config(['services.fcm.credentials' => null]);
        Http::fake();
        $this->assertFalse(app(Push::class)->enabled());
        $this->assertSame(0, app(Push::class)->toUsers([1], 't', 'b'));
        Http::assertNothingSent();
    }

    public function test_sends_to_devices_and_drops_stale_tokens(): void
    {
        config(['services.fcm.credentials' => $this->fakeCreds()]);
        Cache::forget('fcm_access_token');
        [$u] = $this->member('asha');
        DB::table('device_tokens')->insert([
            ['user_id' => $u->id, 'token' => 'good-token', 'platform' => 'android', 'created_at' => now(), 'updated_at' => now()],
            ['user_id' => $u->id, 'token' => 'stale-token', 'platform' => 'android', 'created_at' => now(), 'updated_at' => now()],
        ]);
        Http::fake([
            'oauth2.googleapis.com/*' => Http::response(['access_token' => 'at-1'], 200),
            'fcm.googleapis.com/*' => function ($req) {
                return $req['message']['token'] === 'stale-token'
                    ? Http::response(['error' => ['status' => 'NOT_FOUND', 'details' => [['errorCode' => 'UNREGISTERED']]]], 404)
                    : Http::response(['name' => 'ok'], 200);
            },
        ]);
        $n = app(Push::class)->toUsers([$u->id], 'Bina', 'hello', ['conversation' => 'c1']);
        $this->assertSame(1, $n);
        $this->assertDatabaseMissing('device_tokens', ['token' => 'stale-token']);
        $this->assertDatabaseHas('device_tokens', ['token' => 'good-token']);
        Http::assertSent(fn ($r) => str_contains($r->url(), 'test-project/messages:send') && $r['message']['notification']['title'] === 'Bina' && $r['message']['data']['conversation'] === 'c1');
    }

    public function test_chat_message_pushes_to_other_member_only(): void
    {
        config(['services.fcm.credentials' => $this->fakeCreds()]);
        Cache::forget('fcm_access_token');
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        foreach ([$a, $b] as $u) {
            DB::table('device_tokens')->insert(['user_id' => $u->id, 'token' => 'tok-'.$u->id, 'platform' => 'android', 'created_at' => now(), 'updated_at' => now()]);
        }
        Http::fake([
            'oauth2.googleapis.com/*' => Http::response(['access_token' => 'at-1'], 200),
            'fcm.googleapis.com/*' => Http::response(['name' => 'ok'], 200),
        ]);
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'namaste'], $ha)->assertCreated();
        Http::assertSent(fn ($r) => str_contains($r->url(), 'messages:send') && $r['message']['token'] === 'tok-'.$b->id && $r['message']['notification']['body'] === 'namaste');
        Http::assertNotSent(fn ($r) => str_contains($r->url(), 'messages:send') && $r['message']['token'] === 'tok-'.$a->id);
    }
}
