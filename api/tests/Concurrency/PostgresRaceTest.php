<?php

namespace Tests\Concurrency;

use App\Models\Conversation;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Real concurrency tests: several PHP processes hit one local PostgreSQL database at the same moment.
 * Skipped unless PG_RACE=1 and the default connection is pgsql. Point it at a throwaway local database only.
 * SQLite cannot show row-lock behaviour; this is local Postgres evidence, not the live Neon service.
 */
class PostgresRaceTest extends TestCase
{
    protected function setUp(): void
    {
        if (getenv('PG_RACE') !== '1' || getenv('DB_CONNECTION') !== 'pgsql') {
            $this->markTestSkipped('Set PG_RACE=1 and DB_CONNECTION=pgsql against a throwaway local database.');
        }
        parent::setUp();
        // Fail closed before destructive setup, including a DB_URL override.
        $connection = DB::connection();
        $this->assertSame('pgsql', $connection->getDriverName());
        $this->assertContains($connection->getConfig('host'), ['127.0.0.1', 'localhost', '::1']);
        $this->assertMatchesRegularExpression('/(?:_test$|^sjrace_)/', $connection->getDatabaseName());
        // Fresh schema for each test. No rollback afterwards: other processes commit real rows here.
        $this->artisan('migrate:fresh', ['--force' => true]);
    }

    /** Run requests in parallel processes released together. Returns the status codes in order. */
    private function race(array $calls): array
    {
        $dir = sys_get_temp_dir().'/race-'.bin2hex(random_bytes(4));
        mkdir($dir);
        file_put_contents("$dir/jwks.json", json_encode($this->jwks()));
        $procs = [];
        foreach ($calls as $i => [$username, $method, $uri, $body]) {
            $cmd = [PHP_BINARY, __DIR__.'/worker.php', "$dir/go", "$dir/jwks.json", $this->token("auth0|$username"), $method, $uri, json_encode($body)];
            $procs[$i] = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path(), null);
            $procs[$i] = [$procs[$i], $pipes];
        }
        usleep(1_500_000); // let every worker boot and reach the barrier
        touch("$dir/go");
        $out = [];
        foreach ($procs as $i => [$p, $pipes]) {
            $out[$i] = (int) trim(stream_get_contents($pipes[1]));
            $err = stream_get_contents($pipes[2]);
            proc_close($p);
            if ($out[$i] === 0) {
                $this->fail("worker $i produced no status: $err");
            }
        }

        return $out;
    }

    private function user(string $u): User
    {
        return User::factory()->create(['username' => $u, 'auth0_sub' => "auth0|$u"]);
    }

    private function group(User $owner, iterable $others): Conversation
    {
        $c = Conversation::create(['type' => 'group', 'title' => 'Race', 'created_by' => $owner->id]);
        $c->members()->attach($owner->id, ['role' => 'owner', 'history_from_id' => 0, 'last_read_message_id' => 0]);
        foreach ($others as $o) {
            $c->members()->attach($o->id, ['role' => 'member', 'history_from_id' => 0, 'last_read_message_id' => 0]);
        }

        return $c;
    }

    public function test_capacity_holds_when_six_members_add_one_new_person_each_at_once(): void
    {
        $owner = $this->user('owner');
        $members = collect(range(1, 48))->map(fn ($i) => $this->user("m$i"));
        $c = $this->group($owner, $members);
        $adders = $members->take(6)->values();
        $fresh = collect(range(1, 6))->map(fn ($i) => $this->user("new$i"));
        $calls = $adders->map(fn ($a, $i) => [$a->username, 'POST', "/api/v1/conversations/{$c->public_id}/members", ['usernames' => [$fresh[$i]->username]]])->all();
        $codes = $this->race($calls);
        sort($codes);
        $this->assertSame([200, 422, 422, 422, 422, 422], $codes, 'exactly one add fits under the 50 cap');
        $this->assertSame(50, DB::table('conversation_members')->where('conversation_id', $c->id)->count());
    }

    public function test_two_last_members_leaving_together_delete_the_group_without_errors(): void
    {
        $a = $this->user('asha');
        $b = $this->user('bina');
        $c = $this->group($a, [$b]);
        Conversation::find($c->id)->messages()->create(['user_id' => $a->id, 'kind' => 'text', 'body' => 'hi']);
        $codes = $this->race([['asha', 'POST', "/api/v1/conversations/{$c->public_id}/leave", []], ['bina', 'POST', "/api/v1/conversations/{$c->public_id}/leave", []]]);
        foreach ($codes as $code) {
            $this->assertContains($code, [200, 403, 404], 'no server error from a simultaneous leave');
        }
        $this->assertSame(0, DB::table('conversation_members')->where('conversation_id', $c->id)->count());
        $this->assertSame(0, DB::table('messages')->where('conversation_id', $c->id)->count(), 'no orphaned messages');
    }

    public function test_owner_and_a_member_leaving_together_leave_exactly_one_owner(): void
    {
        $owner = $this->user('owner');
        $ms = collect(range(1, 3))->map(fn ($i) => $this->user("m$i"));
        $c = $this->group($owner, $ms);
        $codes = $this->race([['owner', 'POST', "/api/v1/conversations/{$c->public_id}/leave", []], ['m1', 'POST', "/api/v1/conversations/{$c->public_id}/leave", []]]);
        foreach ($codes as $code) {
            $this->assertSame(200, $code);
        }
        $rows = DB::table('conversation_members')->where('conversation_id', $c->id)->get();
        $this->assertCount(2, $rows);
        $this->assertSame(1, $rows->where('role', 'owner')->count(), 'exactly one owner');
    }
    private function funded(string $name, int $coins): User
    {
        $u = $this->user($name);
        \App\Services\Wallet::credit($u, $coins, 'topup', 'seed:'.$name);

        return $u;
    }

    public function test_simultaneous_cash_outs_cannot_overspend_the_balance(): void
    {
        putenv('PAYOUT_FAKE=1');
        $u = $this->funded('asha', 1000);
        $calls = array_map(fn ($i) => ['asha', 'POST', '/api/v1/wallet/withdrawals', ['coins' => 600, 'client_id' => "client-race-$i"]], range(1, 5));
        $codes = $this->race($calls);
        putenv('PAYOUT_FAKE');
        sort($codes);
        $this->assertSame([201, 422, 422, 422, 422], $codes, 'only one 600 fits in 1000');
        $this->assertSame(400, (int) $u->fresh()->coin_balance);
        $this->assertSame(400, (int) DB::table('wallet_entries')->where('user_id', $u->id)->sum('amount'), 'ledger sum equals balance');
        $this->assertSame(1, DB::table('wallet_withdrawals')->count());
    }

    public function test_the_same_client_id_sent_four_times_at_once_holds_once(): void
    {
        putenv('PAYOUT_FAKE=1');
        $u = $this->funded('asha', 2000);
        $calls = array_map(fn ($i) => ['asha', 'POST', '/api/v1/wallet/withdrawals', ['coins' => 600, 'client_id' => 'client-same-1']], range(1, 4));
        $codes = $this->race($calls);
        putenv('PAYOUT_FAKE');
        sort($codes);
        $this->assertSame([200, 200, 200, 201], $codes);
        $this->assertSame(1400, (int) $u->fresh()->coin_balance);
        $this->assertSame(1, DB::table('wallet_entries')->where('kind', 'withdraw_hold')->count());
    }

    public function test_two_simultaneous_cancels_release_the_hold_once(): void
    {
        putenv('PAYOUT_FAKE=1');
        $u = $this->funded('asha', 1000);
        [$w] = \App\Services\Withdrawals::request($u, 600, 'client-cancel-1');
        $codes = $this->race(array_map(fn () => ['asha', 'POST', "/api/v1/wallet/withdrawals/{$w->public_id}/cancel", []], range(1, 3)));
        putenv('PAYOUT_FAKE');
        sort($codes);
        $this->assertSame([200, 409, 409], $codes);
        $this->assertSame(1000, (int) $u->fresh()->coin_balance);
        $this->assertSame(1, DB::table('wallet_entries')->where('kind', 'withdraw_release')->count());
    }
    public function test_parallel_poll_choices_count_each_member_once(): void
    {
        $a = $this->user('asha');
        $this->user('bina');
        $p = \App\Models\Post::create(['user_id' => $a->id, 'kind' => 'post', 'body' => 'Day?', 'poll_options' => ['A', 'B']]);
        $codes = $this->race(array_map(fn ($i) => ['bina', 'POST', "/api/v1/posts/{$p->public_id}/poll/vote", ['choice' => $i % 2]], range(1, 6)));
        $this->assertSame(array_fill(0, 6, 200), $codes);
        $this->assertSame(1, DB::table('poll_votes')->where('post_id', $p->id)->count());
    }

    public function test_parallel_poll_vote_and_delete_leave_no_votes(): void
    {
        $a = $this->user('asha');
        $this->user('bina');
        $p = \App\Models\Post::create(['user_id' => $a->id, 'kind' => 'post', 'body' => 'Day?', 'poll_options' => ['A', 'B']]);
        $codes = $this->race([['asha', 'DELETE', "/api/v1/posts/{$p->public_id}", []], ['bina', 'POST', "/api/v1/posts/{$p->public_id}/poll/vote", ['choice' => 0]]]);
        $this->assertSame(200, $codes[0]);
        $this->assertContains($codes[1], [200, 404]);
        $this->assertSame(0, DB::table('poll_votes')->where('post_id', $p->id)->count());
    }

    public function test_keyed_post_and_story_retries_create_one_resource_and_one_blob(): void
    {
        $this->user('asha');
        $file = tempnam(sys_get_temp_dir(), 'upload-fixture');
        file_put_contents($file, \Illuminate\Http\UploadedFile::fake()->image('same.png')->get());
        try {
            foreach (['posts', 'stories'] as $route) {
                $body = ['upload_intent' => 'race-upload-intent-001', '_fixture_file' => $file, 'body' => 'Race post', 'caption' => 'Race story'];
                $codes = $this->race(array_fill(0, 4, ['asha', 'POST', '/api/v1/'.$route, $body]));
                sort($codes);
                $this->assertSame([200, 200, 200, 201], $codes);
                $this->assertSame(1, DB::table($route)->count());
            }
            $this->assertSame(2, DB::table('upload_receipts')->count());
            $this->assertSame(2, DB::table('media_blobs')->count());
            $this->assertSame(1, DB::table('post_media')->count());
        } finally { unlink($file); }
    }

    public function test_same_intent_with_different_concurrent_payload_conflicts_without_orphan_media(): void
    {
        $this->user('asha');
        $file = tempnam(sys_get_temp_dir(), 'upload-fixture');
        file_put_contents($file, \Illuminate\Http\UploadedFile::fake()->image('same.png')->get());
        try {
            $body = ['upload_intent' => 'race-upload-intent-002', '_fixture_file' => $file];
            $codes = $this->race([
                ['asha', 'POST', '/api/v1/posts', $body + ['body' => 'First payload']],
                ['asha', 'POST', '/api/v1/posts', $body + ['body' => 'Second payload']],
            ]);
            sort($codes);
            $this->assertSame([201, 409], $codes);
            $this->assertSame(1, DB::table('posts')->count());
            $this->assertSame(1, DB::table('media_blobs')->count());
            $this->assertSame(1, DB::table('upload_receipts')->count());
        } finally { unlink($file); }
    }

    public function test_parallel_comment_and_thread_delete_cannot_leave_orphan_or_stale_count(): void
    {
        $a = $this->user('asha');
        $this->user('bina');
        $p = \App\Models\Post::create(['user_id' => $a->id, 'kind' => 'post', 'body' => 'Discussion', 'comments_count' => 1]);
        $c = $p->comments()->create(['user_id' => $a->id, 'body' => 'Root']);
        $codes = $this->race([
            ['asha', 'DELETE', "/api/v1/comments/{$c->public_id}", []],
            ['bina', 'POST', "/api/v1/posts/{$p->public_id}/comments", ['body' => 'Reply', 'parent_id' => $c->public_id]],
            ['bina', 'POST', "/api/v1/posts/{$p->public_id}/comments", ['body' => 'Independent root']],
        ]);
        $this->assertSame(200, $codes[0]);
        $this->assertContains($codes[1], [201, 422]);
        $this->assertSame(201, $codes[2]);
        $this->assertSame(0, \App\Models\Comment::where('parent_id', $c->id)->count());
        $this->assertSame(1, \App\Models\Comment::where('post_id', $p->id)->count());
        $this->assertSame(1, $p->fresh()->comments_count);
    }

    public function test_parallel_comment_deletes_decrement_count_once(): void
    {
        $a = $this->user('asha');
        $p = \App\Models\Post::create(['user_id' => $a->id, 'kind' => 'post', 'body' => 'Discussion', 'comments_count' => 2]);
        $c = $p->comments()->create(['user_id' => $a->id, 'body' => 'Root']);
        $p->comments()->create(['user_id' => $a->id, 'body' => 'Reply', 'parent_id' => $c->id]);
        $codes = $this->race(array_fill(0, 4, ['asha', 'DELETE', "/api/v1/comments/{$c->public_id}", []]));
        sort($codes);
        $this->assertSame([200, 404, 404, 404], $codes);
        $this->assertSame(0, \App\Models\Comment::where('post_id', $p->id)->count());
        $this->assertSame(0, $p->fresh()->comments_count);
    }

}
