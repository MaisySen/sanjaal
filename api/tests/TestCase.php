<?php

namespace Tests;

use App\Models\User;
use Firebase\JWT\JWT;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    protected static $privateKey;

    protected string $kid = 'test-key';

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.auth0.domain' => 'tenant.example.auth0.com', 'services.auth0.audience' => 'https://api.test']);
        config(['services.auth0.jwks' => $this->jwks()]);
    }

    /** The auth guard caches its user for the life of the app, so reset it between requests. */
    public function call($method, $uri, $parameters = [], $cookies = [], $files = [], $server = [], $content = null)
    {
        $this->app['auth']->forgetGuards();

        return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
    }

    protected function key()
    {
        return self::$privateKey ??= openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
    }

    protected function pem(): string
    {
        openssl_pkey_export($this->key(), $pem);

        return $pem;
    }

    protected function jwks(): array
    {
        $d = openssl_pkey_get_details($this->key());
        $b64 = fn ($v) => rtrim(strtr(base64_encode($v), '+/', '-_'), '=');

        return ['keys' => [['kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => $this->kid, 'n' => $b64($d['rsa']['n']), 'e' => $b64($d['rsa']['e'])]]];
    }

    protected function token(string $sub, array $over = [], ?string $pem = null): string
    {
        $claims = array_merge([
            'iss' => 'https://tenant.example.auth0.com/',
            'aud' => 'https://api.test',
            'sub' => $sub,
            'iat' => time() - 10,
            'exp' => time() + 600,
        ], $over);

        return JWT::encode($claims, $pem ?? $this->pem(), 'RS256', $this->kid);
    }

    /** Create a local member and return [user, auth headers]. */
    protected function hdr(string $username): array
    {
        return ['Authorization' => 'Bearer '.$this->token("auth0|$username"), 'Accept' => 'application/json'];
    }

    protected function member(string $username): array
    {
        $user = User::factory()->create(['username' => $username, 'auth0_sub' => "auth0|$username"]);

        return [$user, ['Authorization' => 'Bearer '.$this->token("auth0|$username"), 'Accept' => 'application/json']];
    }
}
