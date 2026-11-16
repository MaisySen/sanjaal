<?php

namespace App\Services;

use App\Contracts\PayoutProvider;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Cash-out ledger and state machine. It never moves real money itself: a bound PayoutProvider does, and
 * only when enabled. Rules:
 *  - request: coins leave the balance at once (kind withdraw_hold), one row per (user, client_id) so a retry returns the same row.
 *  - cancel: only while "requested". The hold is released once (reference wd:<id>:release).
 *  - payout run: requested -> processing -> paid, or failed with the hold released once.
 *  - the provider idempotency key is the withdrawal public_id. attempts is persisted before each call; after a call
 *    that may have gone out, the next run asks lookup() first and only calls pay() again when the provider has no record.
 *  - after MAX_ATTEMPTS unresolved tries the row moves to "review": coins stay held, nothing is retried or released
 *    until an operator resolves it with wallet:resolve.
 *  - paid and failed are final. A paid request is never silently reversed here.
 */
class Withdrawals
{
    public const MIN = 500;
    public const MAX = 100000;
    public const MAX_ATTEMPTS = 5;

    public static function enabled(): bool
    {
        return app(PayoutProvider::class)->enabled();
    }

    /** @return array{0: object, 1: bool} the row and whether it was newly created */
    public static function request(User $user, int $coins, string $clientId): array
    {
        if ($coins < self::MIN || $coins > self::MAX) {
            throw new InvalidArgumentException('Cash out between '.self::MIN.' and '.self::MAX.' coins at a time.');
        }

        return DB::transaction(function () use ($user, $coins, $clientId) {
            $row = User::whereKey($user->id)->lockForUpdate()->first();
            $existing = DB::table('wallet_withdrawals')->where('user_id', $user->id)->where('client_id', $clientId)->first();
            if ($existing) {
                if ((int) $existing->coins !== $coins) {
                    throw new InvalidArgumentException('That request id was already used for a different amount.');
                }

                return [$existing, false];
            }
            if ($row->coin_balance < $coins) {
                throw new InvalidArgumentException('Not enough coins.');
            }
            $id = (string) Str::uuid();
            $balance = $row->coin_balance - $coins;
            DB::table('wallet_withdrawals')->insert([
                'public_id' => $id, 'user_id' => $user->id, 'client_id' => $clientId, 'coins' => $coins,
                'status' => 'requested', 'created_at' => now(), 'updated_at' => now(),
            ]);
            Wallet::write($row->id, 'withdraw_hold', -$coins, $balance, null, 'wd:'.$id.':hold', 'Cash out');
            $row->forceFill(['coin_balance' => $balance])->save();

            return [DB::table('wallet_withdrawals')->where('public_id', $id)->first(), true];
        });
    }

    /** The owner cancels before it is picked up. Returns false when it is no longer cancelable. */
    public static function cancel(User $user, string $publicId): bool
    {
        return DB::transaction(function () use ($user, $publicId) {
            User::whereKey($user->id)->lockForUpdate()->first();
            $w = DB::table('wallet_withdrawals')->where('public_id', $publicId)->where('user_id', $user->id)->lockForUpdate()->first();
            abort_unless($w, 404);
            if ($w->status !== 'requested') {
                return false;
            }
            self::finish($w, 'canceled', null);

            return true;
        });
    }

    /**
     * Pick up requested rows and ask the provider. Does nothing at all while the provider is disabled.
     * A provider "pending" answer leaves the row "processing"; a thrown error also leaves it "processing"
     * (unknown outcome) rather than guessing, so it is never paid twice and never released while it may have paid.
     */
    public static function run(int $limit = 20): array
    {
        $provider = app(PayoutProvider::class);
        $out = ['paid' => 0, 'failed' => 0, 'pending' => 0, 'skipped' => 0];
        if (! $provider->enabled()) {
            return $out;
        }
        $ids = DB::table('wallet_withdrawals')->whereIn('status', ['requested', 'processing'])->orderBy('id')->limit($limit)->pluck('public_id');
        foreach ($ids as $id) {
            // Claim, and persist the attempt BEFORE any provider call so a crash cannot hide that one may have gone out.
            $w = DB::transaction(function () use ($id, $provider) {
                $w = DB::table('wallet_withdrawals')->where('public_id', $id)->lockForUpdate()->first();
                if (! $w || ! in_array($w->status, ['requested', 'processing'], true)) {
                    return null;
                }
                if ($w->status === 'processing' && (int) $w->attempts >= self::MAX_ATTEMPTS) {
                    DB::table('wallet_withdrawals')->where('id', $w->id)->update(['status' => 'review', 'review_note' => 'Outcome unknown after repeated tries.', 'updated_at' => now()]);

                    return null;
                }
                DB::table('wallet_withdrawals')->where('id', $w->id)->update([
                    'status' => 'processing', 'provider' => $w->provider ?: $provider->name(),
                    'attempts' => (int) $w->attempts + 1, 'last_attempt_at' => now(), 'updated_at' => now(),
                ]);

                return $w;
            });
            if (! $w) {
                $out['skipped']++;
                continue;
            }
            try {
                $r = null;
                if ((int) $w->attempts > 0) {
                    // An earlier call may have reached the provider: look it up under the same key, do not re-send blindly.
                    $r = $provider->lookup($id);
                    if (($r['status'] ?? 'unknown') === 'unknown') {
                        $r = null;
                    }
                }
                $r ??= $provider->pay($id, (int) $w->coins);
            } catch (\Throwable) {
                $out['pending']++;
                continue;
            }
            DB::transaction(function () use ($id, $r, &$out) {
                $w = DB::table('wallet_withdrawals')->where('public_id', $id)->lockForUpdate()->first();
                if ($w->status !== 'processing') {
                    return;
                }
                if ($r['status'] === 'paid') {
                    DB::table('wallet_withdrawals')->where('id', $w->id)->update(['status' => 'paid', 'provider_ref' => $r['ref'] ?? null, 'updated_at' => now()]);
                    $out['paid']++;
                } elseif ($r['status'] === 'failed') {
                    User::whereKey($w->user_id)->lockForUpdate()->first();
                    self::finish($w, 'failed', $r['reason'] ?? 'Payout failed.');
                    $out['failed']++;
                } else {
                    DB::table('wallet_withdrawals')->where('id', $w->id)->update(['provider_ref' => $r['ref'] ?? $w->provider_ref, 'updated_at' => now()]);
                    $out['pending']++;
                }
            });
        }

        return $out;
    }

    /**
     * Operator-only (artisan, never an HTTP route): settle a row in "review" after checking the provider's own records.
     * Only review -> paid or review -> failed. Paid and failed rows are final and refuse.
     */
    public static function resolveReview(string $publicId, string $outcome, ?string $ref = null): bool
    {
        abort_unless(in_array($outcome, ['paid', 'failed'], true), 422);

        return DB::transaction(function () use ($publicId, $outcome, $ref) {
            $w0 = DB::table('wallet_withdrawals')->where('public_id', $publicId)->first();
            abort_unless($w0, 404);
            User::whereKey($w0->user_id)->lockForUpdate()->first();
            $w = DB::table('wallet_withdrawals')->where('public_id', $publicId)->lockForUpdate()->first();
            if ($w->status !== 'review') {
                return false;
            }
            if ($outcome === 'paid') {
                DB::table('wallet_withdrawals')->where('id', $w->id)->update(['status' => 'paid', 'provider_ref' => $ref ?: $w->provider_ref, 'review_note' => null, 'updated_at' => now()]);
            } else {
                self::finish($w, 'failed', 'Payout did not go through.');
            }

            return true;
        });
    }

    /** Final state for canceled/failed: release the hold once. The unique ledger reference makes a repeat a no-op. */
    private static function finish(object $w, string $status, ?string $reason): void
    {
        DB::table('wallet_withdrawals')->where('id', $w->id)->update(['status' => $status, 'failure_reason' => $reason, 'updated_at' => now()]);
        $ref = 'wd:'.$w->public_id.':release';
        if (DB::table('wallet_entries')->where('reference', $ref)->exists()) {
            return;
        }
        $u = User::whereKey($w->user_id)->lockForUpdate()->first();
        $balance = $u->coin_balance + $w->coins;
        Wallet::write($u->id, 'withdraw_release', (int) $w->coins, $balance, null, $ref, $status === 'canceled' ? 'Cash out canceled' : 'Cash out failed');
        $u->forceFill(['coin_balance' => $balance])->save();
    }

    public static function present(object $w): array
    {
        return [
            'public_id' => $w->public_id, 'coins' => (int) $w->coins, 'status' => $w->status,
            'failure_reason' => $w->failure_reason, 'created_at' => \Illuminate\Support\Carbon::parse($w->created_at)->toIso8601String(),
        ];
    }
}
