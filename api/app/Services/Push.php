<?php

namespace App\Services;

use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Sends push notifications through FCM HTTP v1 with a Google service account.
 * Off (every call returns 0) until FCM_CREDENTIALS is set. Tokens and credentials are never logged.
 */
class Push
{
    private ?array $creds = null;

    public function enabled(): bool
    {
        return $this->credentials() !== null;
    }

    /** @return int number of devices the provider accepted */
    public function toUsers(array $userIds, string $title, string $body, array $data = []): int
    {
        $creds = $this->credentials();
        if ($creds === null || $userIds === []) {
            return 0;
        }
        $tokens = DB::table('device_tokens')->join('users', 'users.id', '=', 'device_tokens.user_id')->whereIn('device_tokens.user_id', $userIds)->get(['device_tokens.token', 'users.public_id']);
        if ($tokens->isEmpty()) {
            return 0;
        }
        $access = $this->accessToken($creds);
        if ($access === null) {
            return 0;
        }
        $sent = 0;
        foreach ($tokens as $device) {
            $token = $device->token;
            // The authenticated destination read still checks current membership.
            // Caller-supplied data can never choose this recipient binding.
            $recipientData = array_merge($data, ['recipient' => $device->public_id, 'open_version' => '1']);
            try {
                $res = Http::withToken($access)->timeout(8)->post(
                    'https://fcm.googleapis.com/v1/projects/'.$creds['project_id'].'/messages:send',
                    ['message' => [
                        'token' => $token,
                        'notification' => ['title' => $title, 'body' => $body],
                        'data' => array_map('strval', $recipientData),
                        'android' => ['priority' => 'high'],
                    ]]
                );
            } catch (\Throwable) {
                Log::warning('push send error'); // transient network problem: keep the token
                continue;
            }
            if ($res->successful()) {
                $sent++;
            } elseif ($this->isUnregistered($res)) {
                DB::table('device_tokens')->where('token', $token)->delete(); // the device is gone for good
            } else {
                Log::warning('push send failed', ['status' => $res->status()]); // transient or config: keep the token
            }
        }

        return $sent;
    }

    /** Separate default-off native call path. Not called by the ring producer yet.
     * Rebuild recipient eligibility after provider auth and for every device. */
    public function incomingCall(string $callId): int
    {
        if (config('services.call_wake.send_enabled') !== true) return 0;
        $creds = $this->credentials();
        if ($creds === null) return 0;
        $access = $this->accessToken($creds);
        if ($access === null) return 0;
        $wake = app(CallWake::class);
        $rows = $wake->recipients($callId);
        $users = array_column($rows, 'user_id');
        if ($users === []) return 0;
        $sent = 0;
        $devices = DB::table('call_devices')->where('transport', 'fcm')->whereIn('user_id', $users)->get();
        foreach ($devices as $device) {
            $eligible = collect($wake->recipients($callId))->firstWhere('user_id', $device->user_id);
            // Token ownership/login lease may have changed since snapshot too.
            $current = DB::table('call_devices')->where('id', $device->id)->where('user_id', $device->user_id)
                ->where('login_lease', $device->login_lease)->where('token_hash', $device->token_hash)->exists();
            if (! $eligible || ! $current) continue;
            $seconds = (int) $eligible['data']['expires_at'] - now()->timestamp;
            if ($seconds <= 0 || $seconds > 40) continue;
            try {
                $res = Http::withToken($access)->timeout(min(8, $seconds))->post(
                    'https://fcm.googleapis.com/v1/projects/'.$creds['project_id'].'/messages:send',
                    ['message' => ['token' => $device->token, 'data' => $eligible['data'],
                        'android' => ['priority' => 'high', 'ttl' => $seconds.'s']]]);
                if ($res->successful()) $sent++;
                elseif ($this->isUnregistered($res)) {
                    DB::table('call_devices')->where('id', $device->id)->where('user_id', $device->user_id)
                        ->where('login_lease', $device->login_lease)->where('token_hash', $device->token_hash)->delete();
                }
            } catch (\Throwable) { Log::warning('native call push send error'); }
        }
        return $sent;
    }

    private function isUnregistered($res): bool
    {
        foreach ((array) $res->json('error.details', []) as $d) {
            if (($d['errorCode'] ?? '') === 'UNREGISTERED') {
                return true;
            }
        }

        return false;
    }

    private function credentials(): ?array
    {
        if ($this->creds !== null) {
            return $this->creds;
        }
        $raw = (string) config('services.fcm.credentials');
        if ($raw === '') {
            return null;
        }
        if (! str_starts_with(ltrim($raw), '{')) {
            $raw = is_readable($raw) ? (string) file_get_contents($raw) : '';
        }
        $j = json_decode($raw, true);
        if (! is_array($j) || empty($j['client_email']) || empty($j['private_key']) || empty($j['project_id'])) {
            return null;
        }

        return $this->creds = $j;
    }

    private function accessToken(array $creds): ?string
    {
        return Cache::remember('fcm_access_token', 3000, function () use ($creds) {
            $now = time();
            $jwt = JWT::encode([
                'iss' => $creds['client_email'],
                'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
                'aud' => 'https://oauth2.googleapis.com/token',
                'iat' => $now,
                'exp' => $now + 3300,
            ], $creds['private_key'], 'RS256');
            $res = Http::asForm()->timeout(8)->post('https://oauth2.googleapis.com/token', [
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion' => $jwt,
            ]);
            if (! $res->successful()) {
                Log::warning('push auth failed', ['status' => $res->status()]);

                return null;
            }

            return $res->json('access_token');
        });
    }
}
