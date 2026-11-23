<?php
namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Separate native call tokens, never ordinary chat notification enrollment. */
class CallDeviceController extends Controller
{
    public function store(Request $request)
    {
        abort_unless(config('services.call_wake.registration_enabled') === true, 404);
        $data = $request->validate([
            'transport' => 'required|in:fcm,apns_voip',
            'token' => 'required|string|min:16|max:4096',
            'login_lease' => 'required|uuid',
        ]);
        if ($data['transport'] === 'apns_voip') {
            abort_unless((bool) preg_match('/\A[0-9a-fA-F]{64,512}\z/', $data['token']), 422);
            $data['token'] = strtolower($data['token']);
        }
        // Same physical token can belong only to the latest authenticated owner.
        // Old-owner removal is scoped below so it cannot remove replacement use.
        DB::table('call_devices')->updateOrInsert(['token_hash' => hash('sha256', $data['transport'].':'.$data['token'])], [
            ...$data, 'user_id' => $request->user()->id,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        return response()->json(['registered' => true]);
    }
    public function destroy(Request $request)
    {
        abort_unless(config('services.call_wake.registration_enabled') === true, 404);
        $data = $request->validate(['transport' => 'required|in:fcm,apns_voip',
            'token' => 'required|string|max:4096', 'login_lease' => 'required|uuid']);
        $token = $data['transport'] === 'apns_voip' ? strtolower($data['token']) : $data['token'];
        DB::table('call_devices')->where('user_id', $request->user()->id)
            ->where('token_hash', hash('sha256', $data['transport'].':'.$token))
            ->where('login_lease', $data['login_lease'])->delete();
        return response()->json(['removed' => true]);
    }
}
