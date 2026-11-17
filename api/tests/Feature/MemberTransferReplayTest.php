<?php
namespace Tests\Feature;

use App\Services\Wallet;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class MemberTransferReplayTest extends TestCase
{
    use RefreshDatabase;
    protected function setUp(): void
    {
        parent::setUp();
        config(['wallet.member_transfers_enabled' => true]);
    }
    private function payload(array $changes = []): array
    {
        return $changes + ['client_id' => 'fixture-transfer-key-001', 'username' => 'bina', 'amount' => 25, 'note' => 'Fixture momo'];
    }
    public function test_replay_keeps_one_debit_and_stable_receipt_even_after_rename_or_balance_change(): void
    {
        [$a,$h] = $this->member('asha'); [$b] = $this->member('bina');
        Wallet::credit($a,100,'topup','fixture-replay');
        $first=$this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertOk()->assertJsonPath('transfer.status','completed')->json('transfer');
        $b->forceFill(['username'=>'renamed'])->save();
        Wallet::credit($a,5,'topup','later');
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertOk()->assertJsonPath('balance',80)->assertJsonPath('transfer',$first);
        $this->assertSame(25,(int)$b->fresh()->coin_balance);
        $this->assertSame(1,DB::table('wallet_entries')->where('kind','transfer_out')->count());
        $this->assertDatabaseCount('wallet_transfers',1);
    }
    public function test_key_cannot_be_reused_for_different_content_but_is_scoped_to_sender(): void
    {
        [$a,$h]=$this->member('asha');[$b,$hb]=$this->member('bina');$this->member('chandra');
        Wallet::credit($a,100,'topup','fixture-conflict');
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertOk();
        foreach ([['amount'=>26],['username'=>'chandra'],['note'=>'different']] as $delta) {
            $this->postJson('/api/v1/wallet/transfer',$this->payload($delta),$h)->assertStatus(409);
        }
        $this->postJson('/api/v1/wallet/transfer',$this->payload(['username'=>'asha','amount'=>5]),$hb)->assertOk();
        $this->assertDatabaseCount('wallet_transfers',2);
        $this->assertSame(80,(int)$a->fresh()->coin_balance);
    }
    public function test_rejection_creates_no_receipt_and_new_explicit_transfer_uses_new_key(): void
    {
        [$a,$h]=$this->member('asha');$this->member('bina');
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertStatus(422);
        $this->assertDatabaseCount('wallet_transfers',0);
        Wallet::credit($a,100,'topup','fixture-rejected');
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertOk();
        $this->postJson('/api/v1/wallet/transfer',$this->payload(['client_id'=>'fixture-transfer-key-002']),$h)->assertOk();
        $this->assertDatabaseCount('wallet_transfers',2);
        $this->assertSame(50,(int)$a->fresh()->coin_balance);
    }
    public function test_no_completed_receipt_or_ledger_half_survives_receipt_write_failure(): void
    {
        [$a,$h]=$this->member('asha');[$b]=$this->member('bina');Wallet::credit($a,100,'topup','fixture-atomic');
        $fail = true;
        DB::connection()->beforeExecuting(function ($query) use (&$fail) {
            if ($fail && str_starts_with(strtolower($query), 'insert into "wallet_transfers"')) throw new \RuntimeException('fixture failed receipt');
        });
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertStatus(500);
        $this->assertSame(100,(int)$a->fresh()->coin_balance);$this->assertSame(0,(int)$b->fresh()->coin_balance);
        $this->assertDatabaseCount('wallet_transfers',0);$this->assertSame(0,DB::table('wallet_entries')->where('kind','transfer_out')->count());
        $fail = false;
        $this->postJson('/api/v1/wallet/transfer',$this->payload(),$h)->assertOk();
    }
    public function test_malformed_key_is_rejected_before_mutation(): void
    {
        [$a,$h]=$this->member('asha');$this->member('bina');Wallet::credit($a,100,'topup','fixture-key');
        $this->postJson('/api/v1/wallet/transfer',['username'=>'bina','amount'=>25],$h)->assertStatus(422);
        foreach(['short','path/fixture-key-001',str_repeat('x',81)] as $id) $this->postJson('/api/v1/wallet/transfer',$this->payload(['client_id'=>$id]),$h)->assertStatus(422);
        $this->assertSame(100,(int)$a->fresh()->coin_balance);$this->assertDatabaseCount('wallet_transfers',0);
    }
}
