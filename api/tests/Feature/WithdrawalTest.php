<?php

namespace Tests\Feature;

use App\Contracts\PayoutProvider;
use App\Services\Wallet;
use App\Services\Withdrawals;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Cash-out ledger and state machine, against a FAKE provider. No real payout rail exists in this code. */
class WithdrawalTest extends TestCase
{
    use RefreshDatabase;

    private function fake(string $status = 'paid', bool $enabled = true, bool $throw = false): object
    {
        $p = new class($status, $enabled, $throw) implements PayoutProvider {
            public array $calls = [];

            public array $lookups = [];

            public array|\Throwable $lookupAnswer = ['status' => 'unknown'];

            public function __construct(public string $status, public bool $on, public bool $throw) {}

            public function name(): string { return 'fake'; }

            public function enabled(): bool { return $this->on; }

            public function lookup(string $id): array
            {
                $this->lookups[] = $id;
                if ($this->lookupAnswer instanceof \Throwable) {
                    throw $this->lookupAnswer;
                }

                return $this->lookupAnswer;
            }

            public function pay(string $id, int $coins): array
            {
                $this->calls[] = [$id, $coins];
                if ($this->throw) {
                    throw new \RuntimeException('timeout');
                }

                return ['status' => $this->status, 'ref' => 'F-1', 'reason' => 'bank said no'];
            }
        };
        $this->app->instance(PayoutProvider::class, $p);

        return $p;
    }

    private function funded(string $name, int $coins): array
    {
        [$u, $h] = $this->member($name);
        Wallet::credit($u, $coins, 'topup', 'seed:'.$name);

        return [$u, $h];
    }

    private function ask(array $h, int $coins, string $cid = 'client-0001')
    {
        return $this->postJson('/api/v1/wallet/withdrawals', ['coins' => $coins, 'client_id' => $cid], $h);
    }

    private function sum(int $uid): int
    {
        return (int) DB::table('wallet_entries')->where('user_id', $uid)->sum('amount');
    }

    public function test_off_by_default_nothing_is_held_and_the_run_is_a_no_op(): void
    {
        [$u, $h] = $this->funded('asha', 1000);
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('cashout.available', false);
        $this->ask($h, 600)->assertStatus(503);
        $this->assertSame(1000, (int) $u->fresh()->coin_balance);
        $this->assertSame(0, DB::table('wallet_withdrawals')->count());
        $this->assertSame(['paid' => 0, 'failed' => 0, 'pending' => 0, 'skipped' => 0], Withdrawals::run());
    }

    public function test_request_holds_coins_is_idempotent_and_validated(): void
    {
        $this->fake();
        [$u, $h] = $this->funded('asha', 1000);
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('cashout.available', true)->assertJsonPath('cashout.min', 500);

        $this->ask($h, 499)->assertStatus(422);
        $this->ask($h, 1001)->assertStatus(422)->assertJsonPath('message', 'Not enough coins.');
        $this->postJson('/api/v1/wallet/withdrawals', ['coins' => 600], $h)->assertStatus(422);

        $first = $this->ask($h, 600)->assertCreated()->assertJsonPath('balance', 400)->assertJsonPath('withdrawal.status', 'requested');
        // A retry with the same client id returns the same row and holds nothing more.
        $again = $this->ask($h, 600)->assertOk()->assertJsonPath('balance', 400);
        $this->assertSame($first->json('withdrawal.public_id'), $again->json('withdrawal.public_id'));
        $this->ask($h, 500)->assertStatus(422); // same id, different amount
        $this->assertSame(1, DB::table('wallet_withdrawals')->count());
        $this->assertSame(400, $this->sum($u->id), 'ledger sum equals balance');
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
        // A second real request cannot overspend what is left.
        $this->ask($h, 500, 'client-0002')->assertStatus(422);
    }

    public function test_cancel_releases_once_and_only_before_pickup(): void
    {
        $this->fake();
        [$u, $h] = $this->funded('asha', 1000);
        [, $ho] = $this->funded('bina', 1000);
        $id = $this->ask($h, 700)->json('withdrawal.public_id');

        $this->postJson("/api/v1/wallet/withdrawals/$id/cancel", [], $ho)->assertNotFound();
        $this->postJson("/api/v1/wallet/withdrawals/$id/cancel", [], $h)->assertOk()->assertJsonPath('balance', 1000);
        $this->postJson("/api/v1/wallet/withdrawals/$id/cancel", [], $h)->assertStatus(409);
        $this->assertSame(1000, (int) $u->fresh()->coin_balance);
        $this->assertSame(1, DB::table('wallet_entries')->where('kind', 'withdraw_release')->count());
        $this->assertSame(1000, $this->sum($u->id));
        $this->assertSame('canceled', $this->getJson('/api/v1/wallet/withdrawals', $h)->json('data.0.status'));

        // Once the provider has it, cancel is refused.
        $p = $this->fake('pending');
        $id2 = $this->ask($h, 600, 'client-0002')->json('withdrawal.public_id');
        Withdrawals::run();
        $this->postJson("/api/v1/wallet/withdrawals/$id2/cancel", [], $h)->assertStatus(409);
        $this->assertCount(1, $p->calls);
    }

    public function test_paid_keeps_the_hold_and_is_never_paid_twice(): void
    {
        $p = $this->fake('paid');
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $this->assertSame(['paid' => 1, 'failed' => 0, 'pending' => 0, 'skipped' => 0], Withdrawals::run());
        Withdrawals::run();
        $this->assertCount(1, $p->calls);
        $row = DB::table('wallet_withdrawals')->first();
        $this->assertSame('paid', $row->status);
        $this->assertSame('F-1', $row->provider_ref);
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
        $this->assertSame(0, DB::table('wallet_entries')->where('kind', 'withdraw_release')->count());
        $this->postJson("/api/v1/wallet/withdrawals/{$row->public_id}/cancel", [], $h)->assertStatus(409);
    }

    public function test_failed_payout_releases_the_hold_exactly_once(): void
    {
        $this->fake('failed');
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $this->assertSame(1, Withdrawals::run()['failed']);
        Withdrawals::run();
        $this->assertSame(1000, (int) $u->fresh()->coin_balance);
        $this->assertSame(1000, $this->sum($u->id));
        $this->assertSame(1, DB::table('wallet_entries')->where('kind', 'withdraw_release')->count());
        $w = $this->getJson('/api/v1/wallet/withdrawals', $h)->json('data.0');
        $this->assertSame('failed', $w['status']);
        $this->assertSame('bank said no', $w['failure_reason']);
    }

    public function test_unknown_outcome_never_releases_and_pending_resolves_later(): void
    {
        $p = $this->fake('paid', true, true);
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $this->assertSame(1, Withdrawals::run()['pending']);
        $this->assertSame('processing', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame(400, (int) $u->fresh()->coin_balance, 'not released while the outcome is unknown');
        $p->throw = false;
        $p->lookupAnswer = ['status' => 'paid', 'ref' => 'LATE-PAID'];
        Withdrawals::run();
        $this->assertSame('paid', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
    }

    public function test_attempt_is_recorded_and_retry_asks_the_provider_before_paying_again(): void
    {
        $p = $this->fake('paid', true, true);
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        Withdrawals::run();
        $row = DB::table('wallet_withdrawals')->first();
        $this->assertSame(1, (int) $row->attempts);
        $this->assertNotNull($row->last_attempt_at);
        $this->assertSame([], $p->lookups, 'first try has nothing to look up');
        // The provider actually took the first call: lookup says paid, so pay() must not run again.
        $p->lookupAnswer = ['status' => 'paid', 'ref' => 'REAL-9'];
        Withdrawals::run();
        $this->assertCount(1, $p->calls, 'pay called once only');
        $this->assertSame(1, count($p->lookups));
        $row = DB::table('wallet_withdrawals')->first();
        $this->assertSame('paid', $row->status);
        $this->assertSame('REAL-9', $row->provider_ref);
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
    }

    public function test_lookup_unknown_or_error_never_resends_even_if_record_is_not_found(): void
    {
        $p = $this->fake('pending', true, true);
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $id = DB::table('wallet_withdrawals')->value('public_id');
        Withdrawals::run(); // threw
        $p->lookupAnswer = new \RuntimeException('provider down');
        Withdrawals::run();
        $this->assertCount(1, $p->calls, 'cannot tell, so no second pay');
        $p->lookupAnswer = ['status' => 'unknown'];
        $p->throw = false;
        Withdrawals::run();
        $this->assertCount(1, $p->calls, 'not found can be eventual consistency, not permission to resend');
        $this->assertSame($id, $p->calls[0][0]);
        $this->assertSame('processing', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
        $p->lookupAnswer = ['status' => 'paid', 'ref' => 'LATE-1'];
        Withdrawals::run();
        $this->assertCount(1, $p->calls);
        $this->assertSame('paid', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame('LATE-1', DB::table('wallet_withdrawals')->value('provider_ref'));
    }

    public function test_repeated_unknown_outcomes_park_in_review_and_nothing_releases_or_resends(): void
    {
        $p = $this->fake('paid', true, true);
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $p->lookupAnswer = new \RuntimeException('provider down');
        for ($i = 0; $i < Withdrawals::MAX_ATTEMPTS + 2; $i++) {
            Withdrawals::run();
        }
        $row = DB::table('wallet_withdrawals')->first();
        $this->assertSame('review', $row->status);
        $this->assertSame(400, (int) $u->fresh()->coin_balance, 'coins stay held');
        $calls = count($p->calls);
        Withdrawals::run();
        Withdrawals::run();
        $this->assertCount($calls, $p->calls, 'review rows are not retried');
        $this->postJson('/api/v1/wallet/withdrawals/'.$row->public_id.'/cancel', [], $h)->assertStatus(409);
        $this->assertSame('review', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame('review', $this->getJson('/api/v1/wallet/withdrawals', $h)->json('data.0.status'));
    }

    public function test_operator_resolve_is_review_only_once_and_needs_confirm(): void
    {
        $this->fake('paid', true, true);
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        $id = DB::table('wallet_withdrawals')->value('public_id');
        $this->artisan('wallet:resolve', ['id' => $id, 'outcome' => 'failed', '--confirm' => true])->assertFailed();
        $this->assertSame(400, (int) $u->fresh()->coin_balance, 'not in review: nothing changed');
        DB::table('wallet_withdrawals')->update(['status' => 'review']);
        $this->artisan('wallet:resolve', ['id' => $id, 'outcome' => 'failed'])->assertFailed();
        $this->assertSame('review', DB::table('wallet_withdrawals')->value('status'), 'no --confirm, no change');
        $this->artisan('wallet:resolve', ['id' => $id, 'outcome' => 'failed', '--confirm' => true])->assertSuccessful();
        $this->artisan('wallet:resolve', ['id' => $id, 'outcome' => 'failed', '--confirm' => true])->assertFailed();
        $this->assertSame(1000, (int) $u->fresh()->coin_balance, 'released exactly once');
        $this->assertSame(1, DB::table('wallet_entries')->where('kind', 'withdraw_release')->count());
        $this->assertSame('failed', DB::table('wallet_withdrawals')->value('status'));
    }

    public function test_paid_cannot_be_resolved_or_reversed(): void
    {
        $this->fake('paid');
        [$u, $h] = $this->funded('asha', 1000);
        $this->ask($h, 600)->assertCreated();
        Withdrawals::run();
        $id = DB::table('wallet_withdrawals')->value('public_id');
        $this->artisan('wallet:resolve', ['id' => $id, 'outcome' => 'failed', '--confirm' => true])->assertFailed();
        $this->assertSame('paid', DB::table('wallet_withdrawals')->value('status'));
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
    }

    public function test_signed_out_and_other_users_cannot_see_or_touch(): void
    {
        $this->fake();
        [, $h] = $this->funded('asha', 1000);
        [, $ho] = $this->member('bina');
        $this->ask($h, 600)->assertCreated();
        $this->getJson('/api/v1/wallet/withdrawals')->assertUnauthorized();
        $this->assertCount(0, $this->getJson('/api/v1/wallet/withdrawals', $ho)->json('data'));
    }
}
