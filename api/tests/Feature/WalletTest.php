<?php

namespace Tests\Feature;

use App\Services\Esewa;
use App\Services\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class WalletTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.esewa.product_code' => 'TESTCODE', 'services.esewa.secret' => 'test-secret', 'services.esewa.env' => 'test']);
    }

    public function test_new_wallet_is_empty_and_lists_topup_options(): void
    {
        [, $h] = $this->member('asha');
        $this->getJson('/api/v1/wallet', $h)->assertOk()->assertJsonPath('balance', 0)
            ->assertJsonPath('topup.esewa', true)->assertJsonPath('topup.esewa_mode', 'test')->assertJsonPath('topup.khalti', false);
    }

    public function test_transfer_moves_coins_and_writes_both_ledger_sides(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        Wallet::credit($a, 500, 'topup', 'seed-1');

        $this->postJson('/api/v1/wallet/transfer', ['username' => '@bina', 'amount' => 120, 'note' => 'momo'], $ha)->assertOk()->assertJsonPath('balance', 380);
        $this->getJson('/api/v1/wallet', $hb)->assertJsonPath('balance', 120)->assertJsonPath('entries.0.kind', 'transfer_in')->assertJsonPath('entries.0.counterparty', 'asha');
        $this->getJson('/api/v1/wallet/entries', $ha)->assertJsonPath('data.0.amount', -120)->assertJsonPath('data.0.balance_after', 380);
    }

    public function test_transfer_rejects_overdraft_self_and_unknown_member(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        Wallet::credit($a, 50, 'topup', 'seed-2');
        $this->postJson('/api/v1/wallet/transfer', ['username' => 'bina', 'amount' => 51], $ha)->assertStatus(422);
        $this->postJson('/api/v1/wallet/transfer', ['username' => 'asha', 'amount' => 5], $ha)->assertStatus(422);
        $this->postJson('/api/v1/wallet/transfer', ['username' => 'nobody', 'amount' => 5], $ha)->assertStatus(404);
        $this->postJson('/api/v1/wallet/transfer', ['username' => 'bina', 'amount' => 0], $ha)->assertStatus(422);
        $this->getJson('/api/v1/wallet', $ha)->assertJsonPath('balance', 50);
    }

    public function test_credit_is_idempotent_by_reference(): void
    {
        [$a] = $this->member('asha');
        $this->assertTrue(Wallet::credit($a, 100, 'topup', 'same'));
        $this->assertFalse(Wallet::credit($a, 100, 'topup', 'same'));
        $this->assertSame(100, (int) $a->fresh()->coin_balance);
    }

    private function esewaReturn(string $uuid, int $amount, string $status = 'COMPLETE', bool $tamper = false): string
    {
        $p = ['transaction_code' => 'T1', 'status' => $status, 'total_amount' => number_format($amount, 1), 'transaction_uuid' => $uuid,
            'product_code' => 'TESTCODE', 'signed_field_names' => 'transaction_code,status,total_amount,transaction_uuid,product_code,signed_field_names'];
        $p['signature'] = Esewa::sign($p, $p['signed_field_names']);
        if ($tamper) {
            $p['total_amount'] = number_format($amount + 500, 1);
        }

        return base64_encode(json_encode($p));
    }

    public function test_esewa_topup_credits_once_after_verified_return(): void
    {
        [, $h] = $this->member('asha');
        $start = $this->postJson('/api/v1/wallet/topups', ['amount' => 200], $h)->assertCreated();
        $id = $start->json('topup_id');
        $this->assertStringContainsString("/pay/esewa/$id", $start->json('pay_url'));

        $page = $this->get("/pay/esewa/$id")->assertOk()->getContent();
        $this->assertStringContainsString('rc-epay.esewa.com.np', $page);
        $this->assertStringContainsString('name="signature"', $page);

        Http::fake(['rc.esewa.com.np/*' => Http::response(['status' => 'COMPLETE'])]);
        $data = $this->esewaReturn($id, 200);
        $this->get("/pay/esewa/$id/success?data=".urlencode($data))->assertOk()->assertSee('Payment received');
        $this->get("/pay/esewa/$id/success?data=".urlencode($data))->assertOk();
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('balance', 200);
        $this->getJson("/api/v1/wallet/topups/$id", $h)->assertJsonPath('status', 'completed');
    }

    public function test_tampered_or_unconfirmed_payment_adds_no_coins(): void
    {
        [, $h] = $this->member('asha');
        $id = $this->postJson('/api/v1/wallet/topups', ['amount' => 200], $h)->json('topup_id');
        $statusFor = ['status' => 'COMPLETE'];
        Http::fake(['rc.esewa.com.np/*' => function () use (&$statusFor) { return Http::response($statusFor); }]);
        $this->get("/pay/esewa/$id/success?data=".urlencode($this->esewaReturn($id, 200, 'COMPLETE', true)))->assertSee('did not go through');
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('balance', 0);

        $id2 = $this->postJson('/api/v1/wallet/topups', ['amount' => 300], $h)->json('topup_id');
        $statusFor = ['status' => 'PENDING'];
        $this->get("/pay/esewa/$id2/success?data=".urlencode($this->esewaReturn($id2, 300)))->assertSee('did not go through');
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('balance', 0);
        $this->get("/pay/esewa/$id2/failure")->assertOk();
    }

    public function test_topup_is_off_without_merchant_config(): void
    {
        config(['services.esewa.secret' => null]);
        [, $h] = $this->member('asha');
        $this->postJson('/api/v1/wallet/topups', ['amount' => 100], $h)->assertStatus(503);
        $this->getJson('/api/v1/wallet', $h)->assertJsonPath('topup.esewa', false);
    }
}
