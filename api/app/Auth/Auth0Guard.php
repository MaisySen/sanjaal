<?php

namespace App\Auth;

use App\Models\User;
use Firebase\JWT\JWK;
use Firebase\JWT\JWT;
use Illuminate\Http\Request;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Throwable;

/**
 * Verifies an Auth0 RS256 access token (signature via the tenant JWKS, issuer,
 * audience, expiry) and maps its subject to a local user, creating it on first sight.
 */
class Auth0Guard
{
    public function __invoke(Request $request): ?User
    {
        $token = $request->bearerToken();
        if (! $token) {
            return null;
        }

        try {
            $claims = $this->claimsFor($token);
            if (! is_string($claims['sub'] ?? null) || trim($claims['sub']) === '' || strlen($claims['sub']) > 255) return null;
        } catch (Throwable) {
            return null;
        }

        return $this->userFor($claims['sub'], $token);
    }

    /**
     * RS256 verification is the heaviest step on a small CPU, so a token that already passed is
     * remembered for at most five minutes and never past its own expiry.
     *
     * @return array<string, mixed>
     */
    private function claimsFor(string $token): array
    {
        $key = 'jwt.'.hash('sha256', $token);
        $hit = Cache::get($key);
        if (is_array($hit) && ($hit['exp'] ?? 0) > time()) {
            return $hit;
        }
        $claims = $this->verify($token);
        $ttl = min(300, (int) ($claims['exp'] ?? 0) - time());
        if ($ttl > 0) {
            Cache::put($key, $claims, $ttl);
        }

        return $claims;
    }

    /** @return array<string, mixed> */
    private function verify(string $token): array
    {
        $domain = config('services.auth0.domain');
        $keys = JWK::parseKeySet($this->jwks($domain), 'RS256');
        JWT::$leeway = 30;
        $claims = (array) JWT::decode($token, $keys);

        if (($claims['iss'] ?? null) !== "https://{$domain}/") {
            throw new \RuntimeException('bad issuer');
        }
        $aud = (array) ($claims['aud'] ?? []);
        if (! in_array(config('services.auth0.audience'), $aud, true) || empty($claims['sub'])) {
            throw new \RuntimeException('bad audience');
        }

        return $claims;
    }

    /** @return array<string, mixed> */
    private function jwks(string $domain): array
    {
        $override = config('services.auth0.jwks');
        if (is_array($override)) {
            return $override;
        }

        return Cache::remember('auth0.jwks', 3600, function () use ($domain) {
            return Http::timeout(10)->get("https://{$domain}/.well-known/jwks.json")->throw()->json();
        });
    }

    private function userFor(string $sub, string $token): ?User
    {
        $user = User::where('auth0_sub', $sub)->first();
        if ($user) {
            return $user;
        }

        try {
            $info = Http::timeout(10)->withToken($token)
                ->get('https://'.config('services.auth0.domain').'/userinfo');
        } catch (ConnectionException) {
            return null;
        }
        $profile = $info->json();
        if (! $info->ok() || ! is_array($profile) || ($profile['sub'] ?? null) !== $sub) return null;
        $email = $profile['email'] ?? null;
        if (! is_string($email) || strlen($email) > 255 || ! filter_var(trim($email), FILTER_VALIDATE_EMAIL)) return null;
        $email = Str::lower(trim($email));

        // Email, including verified email, is not authority to replace another
        // subject. Legacy/imported rows also need deliberate account linking.
        if (User::whereRaw('LOWER(email) = ?', [$email])->exists()) return User::where('auth0_sub', $sub)->first();
        $name = is_string($profile['name'] ?? null) ? $profile['name'] : null;
        $nickname = is_string($profile['nickname'] ?? null) ? $profile['nickname'] : Str::before($email, '@');
        try {
            return User::create([
                'name' => Str::limit(User::safeName($name ?: $nickname, $nickname), 80, ''),
                'username' => $this->freshUsername($nickname),
                'email' => $email,
                'auth0_sub' => $sub,
            ]);
        } catch (\Illuminate\Database\UniqueConstraintViolationException) {
            // Concurrent first sign-in may have created this exact subject.
            // Never resolve a collision by taking the row with matching email.
            return User::where('auth0_sub', $sub)->first();
        }
    }

    private function freshUsername(string $seed): string
    {
        $base = Str::of($seed)->lower()->replaceMatches('/[^a-z0-9_.]/', '')->limit(20, '')->toString();
        $base = strlen($base) >= 3 ? $base : 'member'.$base;
        $name = $base;
        while (User::where('username', $name)->exists()) {
            $name = $base.random_int(100, 99999);
        }

        return $name;
    }
}
