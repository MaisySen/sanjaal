<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransferAvailabilityTest extends TestCase
{
    use RefreshDatabase;

    public function test_transfers_default_off_and_do_not_create_mutations(): void
    {
        $this->assertFalse(config('wallet.member_transfers_enabled'));
        [$user, $headers] = $this->member('transferhold');
        $this->getJson('/api/v1/wallet', $headers)->assertOk()
            ->assertJsonPath('transfer_replay', false)->assertJsonPath('transfer_replay_supported', true)->assertJsonPath('transfers_available', false);
        $this->postJson('/api/v1/wallet/transfer', ['client_id' => 'fixture-hold-no-transfer', 'username' => 'nobody', 'amount' => 1], $headers)
            ->assertStatus(503)->assertJsonPath('code', 'transfers_unavailable');
        $this->assertSame(0, (int) $user->fresh()->coin_balance);
        $this->assertDatabaseCount('wallet_entries', 0);
        $this->assertDatabaseCount('wallet_transfers', 0);
    }

    public function test_explicit_hold_overrides_an_old_client_and_pending_retry(): void
    {
        config(['wallet.member_transfers_enabled' => false]);
        [, $headers] = $this->member('oldclient');
        $this->postJson('/api/v1/wallet/transfer', [], $headers)->assertStatus(503);
        $this->assertDatabaseCount('wallet_transfers', 0);
    }
}
