<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Request/status only. No account, content, identity or financial-data deletion. */
class AccountDeletionController extends Controller
{
    private function policy(): ?array
    {
        if (config('account_deletion.enabled') !== true || config('account_deletion.completion_mechanism_verified') !== true) {
            return null;
        }
        $policy = [];
        foreach (['policy_version', 'completion_notice', 'retention_notice'] as $key) {
            $value = config('account_deletion.'.$key);
            if (! is_string($value) || trim($value) === '' || strlen($value) > ($key === 'policy_version' ? 80 : 4000)) {
                return null;
            }
            $policy[$key] = $value;
        }

        return $policy;
    }

    private function record(object $row): array
    {
        return ['public_id' => $row->public_id, 'status' => $row->status, 'requested_at' => $row->created_at,
            'policy_version' => $row->policy_version, 'completion_notice' => $row->completion_notice, 'retention_notice' => $row->retention_notice];
    }

    public function show(Request $request): JsonResponse
    {
        // Read the member's existing request even if new requests are disabled.
        $row = DB::table('account_deletion_requests')->where('user_id', $request->user()->id)->first();
        $policy = $this->policy();

        return response()->json(['available' => $policy !== null, 'policy' => $policy, 'request' => $row ? $this->record($row) : null]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate(['confirmed' => ['required', 'accepted'], 'policy_version' => ['required', 'string', 'max:80'],
            'user_id' => ['prohibited'], 'status' => ['prohibited'], 'public_id' => ['prohibited']]);
        $userId = $request->user()->id;
        [$row, $created] = DB::transaction(function () use ($userId, $data) {
            // Serialize retries for this member, including two first requests.
            DB::table('users')->where('id', $userId)->lockForUpdate()->firstOrFail();
            $existing = DB::table('account_deletion_requests')->where('user_id', $userId)->first();
            if ($existing) {
                return [$existing, false];
            }
            $policy = $this->policy();
            abort_if($policy === null, 503, 'Account deletion requests are not available yet. No request was created.');
            abort_unless(hash_equals($policy['policy_version'], $data['policy_version']), 409, 'Deletion information changed. Review it again before confirming.');
            $id = DB::table('account_deletion_requests')->insertGetId(['public_id' => (string) Str::uuid(), 'user_id' => $userId,
                'status' => 'requested', ...$policy, 'created_at' => now(), 'updated_at' => now()]);

            return [DB::table('account_deletion_requests')->where('id', $id)->first(), true];
        });

        return response()->json(['request' => $this->record($row)], $created ? 201 : 200);
    }
}
