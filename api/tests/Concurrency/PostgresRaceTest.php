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
}
