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

    /** Lets one listener speak (or stops them) by changing their permissions on the LiveKit server. */
    public static function setCanPublish(string $room, string $identity, bool $can): bool
    {
        $now = time();
        $admin = self::jwt(['iss' => config('services.livekit.key'), 'nbf' => $now, 'exp' => $now + 60, 'video' => ['roomAdmin' => true, 'room' => $room]], (string) config('services.livekit.secret'));
        $base = preg_replace('#^wss?://#', 'https://', (string) config('services.livekit.url'));
        $r = \Illuminate\Support\Facades\Http::withToken($admin)->timeout(10)->post(rtrim($base, '/').'/twirp/livekit.RoomService/UpdateParticipant', [
            'room' => $room, 'identity' => $identity,
            'permission' => ['can_subscribe' => true, 'can_publish' => $can, 'can_publish_data' => true],
        ]);

        return $r->successful();
    }

    public static function jwt(array $claims, string $secret): string
    {
        $b64 = fn (string $s) => rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
        $head = $b64(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
        $body = $b64(json_encode($claims));

        return $head.'.'.$body.'.'.$b64(hash_hmac('sha256', $head.'.'.$body, $secret, true));
    }
}
