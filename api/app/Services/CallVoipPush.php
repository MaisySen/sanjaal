<?php
namespace App\Services;

use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/** Direct APNs VoIP only. Default off and not selected by call creation. No
 * arbitrary destinations/topics, automatic retries or cancellation VoIP pushes. */
class CallVoipPush
{
    public function incomingCall(string $callId): int
    {
        if (config('services.call_wake.send_enabled') !== true || config('services.call_wake.apns_enabled') !== true) return 0;
        $keyId = config('services.call_wake.apns_key_id');
        $team = config('services.call_wake.apns_team_id');
        $bundle = config('services.call_wake.apns_bundle_id');
        $key = config('services.call_wake.apns_private_key');
        if (! is_string($keyId) || ! preg_match('/\A[A-Z0-9]{10}\z/', $keyId) ||
            ! is_string($team) || ! preg_match('/\A[A-Z0-9]{10}\z/', $team) ||
            ! is_string($bundle) || ! preg_match('/\A[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+\z/', $bundle) ||
            ! is_string($key) || $key === '') return 0;
        $wake = app(CallWake::class);
        $users = array_column($wake->recipients($callId), 'user_id');
        if ($users === []) return 0;
        try {
            // Config-scoped cache prevents stale project/key authorization reuse.
            $auth = Cache::remember('call_apns_auth_'.hash('sha256', $team.$keyId.$key), 2400,
                fn () => JWT::encode(['iss'=>$team, 'iat'=>time()], $key, 'ES256', $keyId));
        } catch (\Throwable) { return 0; }
        $sent = 0;
        foreach (DB::table('call_devices')->where('transport', 'apns_voip')->whereIn('user_id', $users)->get() as $device) {
            $row = collect($wake->recipients($callId))->firstWhere('user_id', $device->user_id);
            if (! $row || ! in_array($device->environment, ['sandbox', 'production'], true) ||
                ! preg_match('/\A[a-f0-9]{64,512}\z/', $device->token)) continue;
            $current = DB::table('call_devices')->where('id', $device->id)->where('user_id', $device->user_id)
                ->where('login_lease', $device->login_lease)->where('token_hash', $device->token_hash);
            if (! (clone $current)->exists()) continue;
            $remaining = (int) $row['data']['expires_at'] - now()->timestamp;
            if ($remaining <= 0 || $remaining > 40) continue;
            $host = $device->environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
            try {
                $response = Http::withToken($auth)->withOptions(['version'=>2.0, 'allow_redirects'=>false])
                    ->withHeaders(['apns-push-type'=>'voip', 'apns-topic'=>$bundle.'.voip',
                        'apns-priority'=>'10', 'apns-expiration'=>'0'])
                    ->timeout(min(8, $remaining))->post('https://'.$host.'/3/device/'.$device->token,
                        ['aps'=>(object)[], ...$row['data'], 'login_lease'=>$device->login_lease]);
                if ($response->successful()) $sent++;
                // No retries: provider acceptance can be ambiguous on transport loss.
                // Only a confirmed invalid registration retires this exact binding.
                elseif ($response->status() === 410 && $response->json('reason') === 'Unregistered') {
                    $invalidAt = $response->json('timestamp');
                    if (is_numeric($invalidAt) && (float) $invalidAt >= (strtotime($device->updated_at) + 1) * 1000) {
                        $current->delete();
                    }
                }
            } catch (\Throwable) { Log::warning('voip call send error'); }
        }
        return $sent;
    }
}
