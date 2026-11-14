<?php

namespace App\Services;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/** Internal coin ledger. 1 coin = NPR 1 of verified top up. There is no cash out. */
class Wallet
{
    public const MAX_TRANSFER = 100000;

    /** Credit coins from a verified payment. Safe to call twice with the same reference. */
    public static function credit(User $user, int $amount, string $kind, string $reference, ?string $note = null): bool
    {
        return DB::transaction(function () use ($user, $amount, $kind, $reference, $note) {
            if (DB::table('wallet_entries')->where('reference', $reference)->exists()) {
                return false;
            }
            $row = User::whereKey($user->id)->lockForUpdate()->first();
            $balance = $row->coin_balance + $amount;
            self::write($row->id, $kind, $amount, $balance, null, $reference, $note);
            $row->forceFill(['coin_balance' => $balance])->save();

            return true;
        });
    }

    public static function transfer(User $from, User $to, int $amount, ?string $note = null): void
    {
        if ($amount < 1 || $amount > self::MAX_TRANSFER) {
            throw new InvalidArgumentException('Amount must be between 1 and '.self::MAX_TRANSFER.' coins.');
        }
        if ($from->id === $to->id) {
            throw new InvalidArgumentException('You cannot send coins to yourself.');
        }
        DB::transaction(function () use ($from, $to, $amount, $note) {
            // Lock in id order so two opposite transfers cannot deadlock.
            $ids = [$from->id, $to->id];
            sort($ids);
            $rows = User::whereIn('id', $ids)->orderBy('id')->lockForUpdate()->get()->keyBy('id');
            $a = $rows[$from->id];
            $b = $rows[$to->id];
            if ($a->coin_balance < $amount) {
                throw new InvalidArgumentException('Not enough coins.');
            }
            $ref = (string) Str::uuid();
            $a->forceFill(['coin_balance' => $a->coin_balance - $amount])->save();
            $b->forceFill(['coin_balance' => $b->coin_balance + $amount])->save();
            self::write($a->id, 'transfer_out', -$amount, $a->coin_balance, $b->id, $ref.':out', $note);
            self::write($b->id, 'transfer_in', $amount, $b->coin_balance, $a->id, $ref.':in', $note);
        });
    }

    private static function write(int $uid, string $kind, int $amount, int $balance, ?int $counterparty, string $ref, ?string $note): void
    {
        DB::table('wallet_entries')->insert([
            'public_id' => (string) Str::uuid(),
            'user_id' => $uid,
            'kind' => $kind,
            'amount' => $amount,
            'balance_after' => $balance,
            'counterparty_id' => $counterparty,
            'reference' => $ref,
            'note' => $note,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }
}
