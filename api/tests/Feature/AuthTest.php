<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_valid_token_reaches_me(): void
    {
        [$u, $h] = $this->member('asha');
        $this->getJson('/api/v1/auth/me', $h)->assertOk()->assertJsonPath('user.username', 'asha');
    }

    public function test_missing_token_is_rejected(): void
    {
        $this->getJson('/api/v1/auth/me')->assertUnauthorized();
    }

    public function test_expired_token_is_rejected(): void
    {
        $this->member('asha');
        $t = $this->token('auth0|asha', ['exp' => time() - 3600, 'iat' => time() - 7200]);
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $t"])->assertUnauthorized();
    }

    public function test_wrong_audience_and_issuer_are_rejected(): void
    {
        $this->member('asha');
        $a = $this->token('auth0|asha', ['aud' => 'https://other']);
        $i = $this->token('auth0|asha', ['iss' => 'https://evil.example/']);
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $a"])->assertUnauthorized();
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $i"])->assertUnauthorized();
    }

    public function test_token_signed_with_another_key_is_rejected(): void
    {
        $this->member('asha');
        $other = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
        openssl_pkey_export($other, $pem);
        $t = $this->token('auth0|asha', [], $pem);
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $t"])->assertUnauthorized();
    }

    public function test_tampered_token_is_rejected(): void
    {
        $this->member('asha');
        $t = $this->token('auth0|asha');
        [$h, $p, $s] = explode('.', $t);
        $p = rtrim(strtr(base64_encode(json_encode(['sub' => 'auth0|someone-else', 'iss' => 'https://tenant.example.auth0.com/', 'aud' => 'https://api.test', 'exp' => time() + 600])), '+/', '-_'), '=');
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $h.$p.$s"])->assertUnauthorized();
    }

    public function test_first_sight_creates_member_from_userinfo(): void
    {
        Http::fake(['*/userinfo' => Http::response(['sub' => 'auth0|fresh', 'email' => 'New@Example.com', 'name' => 'New Person', 'nickname' => 'newbie'])]);
        $t = $this->token('auth0|fresh');
        $this->getJson('/api/v1/auth/me', ['Authorization' => "Bearer $t"])
            ->assertOk()->assertJsonPath('user.username', 'newbie');
        $this->assertDatabaseHas('users', ['email' => 'new@example.com', 'auth0_sub' => 'auth0|fresh']);
    }

    public function test_username_can_be_changed_but_not_taken(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $this->patchJson('/api/v1/auth/me', ['username' => 'bina'], $ha)->assertUnprocessable();
        $this->patchJson('/api/v1/auth/me', ['username' => 'asha_2'], $ha)->assertOk();
    }
}
