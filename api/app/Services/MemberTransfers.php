<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;

/** Permanent sender-scoped receipts, committed atomically with both ledger sides. */
class MemberTransfers
{
    public static function send(User $from, string $clientId, string $username, int $amount, ?string $note): array
    {
        $username = ltrim(trim($username), '@');
        $note = $note === '' ? null : $note;
        $fingerprint = hash('sha256', json_encode([$username, $amount, $note], JSON_THROW_ON_ERROR));
        $receipt = static fn () => DB::table('wallet_transfers')->where('user_id', $from->id)->where('client_id', $clientId)->first();
        $present = static function ($r) use ($fingerprint): array {
            if (! hash_equals($r->fingerprint, $fingerprint)) {
                throw new HttpException(409, 'This transfer key already belongs to different details.');
            }
            return ['transfer' => ['public_id' => $r->public_id, 'client_id' => $r->client_id,
                'recipient_id' => $r->recipient_id, 'amount' => (int) $r->amount,
                'balance_after' => (int) $r->balance_after, 'status' => 'completed']];
        };
        if ($old = $receipt()) return $present($old);
        $to = User::where('username', $username)->first();
        if (! $to) throw new HttpException(404, 'No member with that username.');

        return DB::transaction(function () use ($from, $to, $clientId, $fingerprint, $amount, $note, $receipt, $present) {
            // The same ordered participant locks as Wallet::transfer, before receipt/FK insertion.
            // Concurrent same-key or opposite-direction requests cannot debit twice or invert lock order.
            User::whereIn('id', [$from->id, $to->id])->orderBy('id')->lockForUpdate()->get();
            if ($old = $receipt()) return $present($old);
            Wallet::transfer($from, $to, $amount, $note);
            $id = (string) Str::uuid();
            DB::table('wallet_transfers')->insert([
                'user_id' => $from->id, 'client_id' => $clientId, 'fingerprint' => $fingerprint,
                'public_id' => $id, 'recipient_id' => $to->public_id, 'amount' => $amount,
                'balance_after' => (int) $from->fresh()->coin_balance, 'created_at' => now(), 'updated_at' => now(),
            ]);
            return $present($receipt());
        }, 3);
    }
}
