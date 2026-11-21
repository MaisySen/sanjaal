<?php

namespace Tests\Feature;

use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class AccountDeletionPlanTest extends TestCase
{
    use RefreshDatabase;

    private function request(int $userId): string
    {
        $id = (string) Str::uuid();
        DB::table('account_deletion_requests')->insert(['public_id' => $id, 'user_id' => $userId, 'status' => 'requested', 'policy_version' => 'fixture',
            'completion_notice' => 'Sensitive synthetic notice not for output', 'retention_notice' => 'Sensitive synthetic terms not for output', 'created_at' => now(), 'updated_at' => now()]);
        return $id;
    }

    public function test_unknown_or_malformed_request_has_no_plan(): void
    {
        $this->artisan('accounts:deletion-plan', ['request_id' => '../all'])->assertFailed();
        $this->artisan('accounts:deletion-plan', ['request_id' => (string) Str::uuid()])->assertFailed();
    }

    public function test_plan_is_scoped_counts_only_and_performs_only_selects(): void
    {
        [$a] = $this->member('asha'); [$b] = $this->member('bina');
        Post::create(['user_id' => $a->id, 'body' => 'PRIVATE_CONTENT_A']);
        Post::create(['user_id' => $b->id, 'body' => 'PRIVATE_CONTENT_B']);
        Post::create(['user_id' => $b->id, 'body' => 'PRIVATE_CONTENT_B2']);
        $id = $this->request($a->id);
        Http::fake(); DB::enableQueryLog(); DB::flushQueryLog();
        $this->assertSame(0, Artisan::call('accounts:deletion-plan', ['request_id' => $id]));
        $queries = DB::getQueryLog(); DB::disableQueryLog();
        foreach ($queries as $query) {
            $this->assertStringStartsWith('select ', strtolower(ltrim($query['query'])));
        }
        $output = Artisan::output(); $plan = json_decode($output, true, flags: JSON_THROW_ON_ERROR);
        $this->assertSame(1, $plan['counts']['posts']);
        $this->assertFalse($plan['inventory_complete']); $this->assertFalse($plan['deletion_allowed']); $this->assertFalse($plan['account_deleted']);
        foreach (['PRIVATE_CONTENT', $a->email, $b->email, 'Sensitive synthetic'] as $private) {
            $this->assertStringNotContainsString($private, $output);
        }
        $this->assertDatabaseCount('posts', 3); $this->assertDatabaseCount('users', 2); $this->assertDatabaseCount('account_deletion_requests', 1);
        Http::assertNothingSent();
    }

    public function test_balance_and_unsettled_payment_holds_are_not_erasure_or_refund(): void
    {
        [$a] = $this->member('asha'); [$b] = $this->member('bina'); $id = $this->request($a->id);
        DB::table('users')->where('id', $a->id)->update(['coin_balance' => 25]);
        DB::table('wallet_topups')->insert(['public_id' => (string) Str::uuid(), 'user_id' => $a->id, 'provider' => 'fixture', 'amount' => 10, 'status' => 'unknown', 'created_at' => now(), 'updated_at' => now()]);
        DB::table('wallet_withdrawals')->insert(['public_id' => (string) Str::uuid(), 'user_id' => $b->id, 'client_id' => 'other-fixture', 'coins' => 5, 'status' => 'processing', 'created_at' => now(), 'updated_at' => now()]);
        $this->assertSame(0, Artisan::call('accounts:deletion-plan', ['request_id' => $id]));
        $plan = json_decode(Artisan::output(), true, flags: JSON_THROW_ON_ERROR);
        $this->assertTrue($plan['operational_holds']['nonzero_coin_balance']); $this->assertTrue($plan['operational_holds']['unsettled_topups']);
        $this->assertFalse($plan['operational_holds']['unsettled_withdrawals']);
        $this->assertDatabaseHas('users', ['id' => $a->id, 'coin_balance' => 25]);
        $this->assertDatabaseHas('wallet_topups', ['user_id' => $a->id, 'status' => 'unknown']);
        $this->assertDatabaseHas('wallet_withdrawals', ['user_id' => $b->id, 'status' => 'processing']);
    }
}
