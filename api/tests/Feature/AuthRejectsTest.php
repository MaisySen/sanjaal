<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The normal guard, with no E2E fixture loaded, rejects tokens that are not properly signed. */
class AuthRejectsTest extends TestCase
{
    use RefreshDatabase;

    public function test_unsigned_and_fake_tokens_are_rejected(): void
    {
        $b64 = fn ($v) => rtrim(strtr(base64_encode($v), '+/', '-_'), '=');
        $claims = ['sub' => 'auth0|e2e-synthetic', 'iss' => 'https://tenant.example.auth0.com/', 'aud' => 'https://api.test', 'exp' => time() + 600];
        $none = $b64(json_encode(['alg' => 'none', 'typ' => 'JWT'])).'.'.$b64(json_encode($claims)).'.';
        $fake = $b64(json_encode(['alg' => 'RS256', 'typ' => 'JWT'])).'.'.$b64(json_encode($claims)).'.'.$b64('not a signature');
        foreach ([$none, $fake, 'garbage'] as $t) {
            $this->getJson('/api/v1/auth/me', ['Authorization' => 'Bearer '.$t])->assertStatus(401);
        }
    }
}
