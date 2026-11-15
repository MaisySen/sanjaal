<?php

namespace App\Services;

/** Mints LiveKit access tokens (HS256 JWT) so members can join a call room. No SDK needed. */
class LiveKit
{
    public static function configured(): bool
    {
        return config('services.livekit.url') && config('services.livekit.key') && config('services.livekit.secret');
    }

    public static function token(string $identity, string $name, string $room, int $ttl = 3600, bool $publish = true): string
    {
        $now = time();
        $claims = [
            'iss' => config('services.livekit.key'),
            'sub' => $identity,
            'name' => $name,
            'nbf' => $now,
            'exp' => $now + $ttl,
            'video' => [
                'room' => $room,
                'roomJoin' => true,
                'canPublish' => $publish,
                'canSubscribe' => true,
                'canPublishData' => true,
            ],
        ];

        return self::jwt($claims, (string) config('services.livekit.secret'));
    }

    public static function jwt(array $claims, string $secret): string
    {
        $b64 = fn (string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        $head = $b64(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
        $body = $b64(json_encode($claims));

        return $head.'.'.$body.'.'.$b64(hash_hmac('sha256', $head.'.'.$body, $secret, true));
    }
}
