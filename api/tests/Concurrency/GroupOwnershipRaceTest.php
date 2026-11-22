<?php

namespace Tests\Concurrency;

use App\Models\Conversation;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Only its named throwaway database is ever recreated. Workers invoke real controller code. */
class GroupOwnershipRaceTest extends TestCase
{
    protected function setUp(): void
    {
        if (getenv('PG_RACE') !== '1' || getenv('DB_CONNECTION') !== 'pgsql' || getenv('APP_ENV') !== 'testing' || getenv('DB_URL')) {
            $this->markTestSkipped('Requires an explicitly disposable local PostgreSQL fixture.');
        }
        parent::setUp();
        $db = DB::connection();
        $host = $db->getConfig('host');
        $this->assertSame('pgsql', $db->getDriverName());
        $this->assertMatchesRegularExpression('~^/tmp/sj-ownership-pg\.[A-Za-z0-9]{8}/socket$~D', $host);
        $this->assertSame('sjownership_test', $db->getDatabaseName());
        $this->assertSame(54388, (int) $db->getConfig('port'));
        $this->assertSame(dirname($host).'/data', $db->selectOne("select current_setting('data_directory') as path")->path);
        $this->artisan('migrate:fresh', ['--force' => true]);
        config(['group_ownership.enabled' => true, 'group_member_removal.enabled' => true]);
    }

    private function group(): array
    {
        [$a, $headers] = $this->member('owner');
        [$b] = $this->member('next');
        [$c] = $this->member('third');
        $snapshot = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Synthetic race', 'usernames' => ['next', 'third']], $headers)->assertCreated()->json('conversation');

        return [Conversation::where('public_id', $snapshot['public_id'])->firstOrFail(), $a, $b, $c, $snapshot['ownership_revision'], $headers];
    }

    private function race(Conversation $group, array $operations): array
    {
        $dir = sys_get_temp_dir().'/group-ownership-race-'.bin2hex(random_bytes(6));
        mkdir($dir, 0700);
        $processes = [];
        try {
            foreach ($operations as $index => $operation) {
                $command = [PHP_BINARY, '-c', php_ini_loaded_file(), __DIR__.'/group-ownership-worker.php', $dir.'/go', $group->public_id, ...$operation, $dir.'/ready-'.$index];
                $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path());
                $this->assertIsResource($process);
                $processes[] = [$process, $pipes];
            }
            $deadline = hrtime(true) + 10000000000;
            $pids = [];
            while (count($pids) !== count($operations)) {
                if (hrtime(true) >= $deadline) $this->fail('Group workers did not reach their barrier.');
                $pids = [];
                foreach (array_keys($operations) as $index) {
                    if (is_file($dir.'/ready-'.$index)) $pids[] = (int) file_get_contents($dir.'/ready-'.$index);
                }
                if (count($pids) !== count($operations)) usleep(10000);
            }
            DB::beginTransaction();
            Conversation::whereKey($group->id)->lockForUpdate()->firstOrFail();
            touch($dir.'/go');
            $blocked = 0;
            while ($blocked !== count($operations)) {
                if (hrtime(true) >= $deadline) {
                    $diagnostics = [];
                    foreach ($processes as [$process, $pipes]) {
                        stream_set_blocking($pipes[1], false); stream_set_blocking($pipes[2], false);
                        $diagnostics[] = [proc_get_status($process), stream_get_contents($pipes[1]), stream_get_contents($pipes[2])];
                    }
                    $this->fail('Group workers did not contend for the same conversation row: '.json_encode($diagnostics));
                }
                DB::select('select pg_stat_clear_snapshot()');
                $marks = implode(',', array_fill(0, count($pids), '?'));
                $blocked = (int) DB::selectOne("select count(*) as n from pg_stat_activity where pid in ($marks) and wait_event_type = 'Lock'", $pids)->n;
                if ($blocked !== count($operations)) usleep(10000);
            }
            $this->assertSame(count($operations), $blocked);
            DB::commit();
            $codes = [];
            foreach ($processes as [$process, $pipes]) {
                $out = stream_get_contents($pipes[1]);
                $error = stream_get_contents($pipes[2]);
                fclose($pipes[1]); fclose($pipes[2]);
                $this->assertSame(0, proc_close($process), 'Group fixture worker failed: '.$error);
                $codes[] = json_decode($out, true, flags: JSON_THROW_ON_ERROR)['code'];
            }
            $processes = [];

            return $codes;
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($processes as [$process, $pipes]) {
                if (is_resource($process)) { proc_terminate($process); proc_close($process); }
            }
            foreach (glob($dir.'/*') ?: [] as $file) @unlink($file);
            @rmdir($dir);
        }
    }

    public function test_competing_successors_cannot_create_two_owners(): void
    {
        [$group, $a, $b, $c, $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'transfer', $b->public_id, $revision], [$a->id, 'transfer', $c->public_id, $revision]]);
        sort($codes);
        $this->assertSame([200, 403], $codes);
        $this->assertSame(1, $group->members()->wherePivot('role', 'owner')->count());
        $this->assertContains($group->members()->wherePivot('role', 'owner')->first()->id, [$b->id, $c->id]);
        $this->assertSame(3, $group->members()->count());
        $this->assertSame(1, $group->fresh()->ownership_version);
    }

    public function test_departing_target_never_becomes_a_detached_owner(): void
    {
        [$group, $a, $b, , $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'transfer', $b->public_id, $revision], [$b->id, 'leave', '', '']]);
        $this->assertSame(200, $codes[1]);
        $this->assertContains($codes[0], [200, 409]);
        $this->assertFalse($group->hasMember($b));
        $this->assertSame(1, $group->members()->wherePivot('role', 'owner')->count());
        $this->assertSame($a->id, $group->members()->wherePivot('role', 'owner')->first()->id);
        $this->assertSame($codes[0] === 200 ? 2 : 1, $group->fresh()->ownership_version);
    }

    public function test_departing_original_owner_does_not_override_the_handoff(): void
    {
        [$group, $a, $b, , $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'transfer', $b->public_id, $revision], [$a->id, 'leave', '', '']]);
        $this->assertSame(200, $codes[1]);
        $this->assertContains($codes[0], [200, 404]);
        $this->assertFalse($group->hasMember($a));
        $this->assertSame(1, $group->members()->wherePivot('role', 'owner')->count());
        $this->assertSame($b->id, $group->members()->wherePivot('role', 'owner')->first()->id);
        $this->assertSame($codes[0] === 200 ? 2 : 1, $group->fresh()->ownership_version);
    }

    public function test_competing_removals_need_distinct_current_confirmations(): void
    {
        [$group, $a, $b, $c, $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'remove', $b->public_id, $revision], [$a->id, 'remove', $c->public_id, $revision]]);
        sort($codes);
        $this->assertSame([200, 409], $codes);
        $this->assertSame(2, $group->members()->count());
        $this->assertSame(1, $group->members()->wherePivot('role', 'owner')->count());
        $this->assertSame($a->id, $group->members()->wherePivot('role', 'owner')->first()->id);
        $this->assertSame(1, $group->fresh()->ownership_version);
    }

    public function test_removal_and_handoff_cannot_apply_the_same_old_authority(): void
    {
        [$group, $a, $b, , $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'remove', $b->public_id, $revision], [$a->id, 'transfer', $b->public_id, $revision]]);
        $this->assertTrue(in_array($codes, [[200, 409], [403, 200]], true));
        $this->assertSame(1, $group->members()->wherePivot('role', 'owner')->count());
        $this->assertSame(1, $group->fresh()->ownership_version);
        $this->assertSame($codes[0] === 200 ? $a->id : $b->id, $group->members()->wherePivot('role', 'owner')->first()->id);
    }

    public function test_queued_send_rechecks_membership_after_removal(): void
    {
        [$group, $a, $b, , $revision] = $this->group();
        $codes = $this->race($group, [[$a->id, 'remove', $b->public_id, $revision], [$b->id, 'send', '', '']]);
        $this->assertSame(200, $codes[0]);
        $this->assertContains($codes[1], [201, 404]);
        $this->assertFalse($group->hasMember($b));
        $this->assertSame($codes[1] === 201 ? 1 : 0, $group->messages()->count());
    }

    private function pausedPoll(Conversation $group, $member, callable $during): array
    {
        $dir = sys_get_temp_dir().'/group-ownership-race-'.bin2hex(random_bytes(6));
        mkdir($dir, 0700);
        $process = null;
        $pipes = [];
        try {
            $command = [PHP_BINARY, '-c', php_ini_loaded_file(), __DIR__.'/group-ownership-worker.php', $dir.'/go', $group->public_id, $member->id, 'poll', '', '', $dir.'/ready-0'];
            $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path());
            $this->assertIsResource($process);
            touch($dir.'/go');
            $deadline = hrtime(true) + 10000000000;
            while (! file_exists($dir.'/ready-0.poll')) {
                if (hrtime(true) >= $deadline) $this->fail('Group poll did not finish its initial empty-message probe.');
                usleep(10000);
            }
            // Its real controller has already authorized the old membership and
            // finished the initial empty-message query. No fixture hook is in production.
            $this->assertSame(0, $group->messages()->count());
            $during();
            touch($dir.'/go.read');
            $out = stream_get_contents($pipes[1]);
            $error = stream_get_contents($pipes[2]);
            fclose($pipes[1]); fclose($pipes[2]); $pipes = [];
            $this->assertSame(0, proc_close($process), 'Group poll fixture failed: '.$error);
            $process = null;

            return json_decode($out, true, flags: JSON_THROW_ON_ERROR);
        } finally {
            if (is_resource($process)) { proc_terminate($process); proc_close($process); }
            foreach ($pipes as $pipe) if (is_resource($pipe)) fclose($pipe);
            foreach (glob($dir.'/*') ?: [] as $file) @unlink($file);
            @rmdir($dir);
        }
    }

    public function test_waiting_poll_cannot_deliver_messages_created_after_removal(): void
    {
        [$group, $a, $b, , $revision, $headers] = $this->group();
        $result = $this->pausedPoll($group, $b, function () use ($group, $b, $revision, $headers) {
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/member-removals', ['member_id' => $b->public_id, 'ownership_revision' => $revision], $headers)->assertOk();
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/messages', ['body' => 'Private after removal', 'client_id' => 'after-removal'], $headers)->assertCreated();
        });
        $this->assertSame(404, $result['code']);
        $this->assertSame([], $result['payload']);
    }

    public function test_waiting_poll_uses_reinvited_members_new_history_boundary(): void
    {
        [$group, $a, $b, , $revision, $headers] = $this->group();
        $result = $this->pausedPoll($group, $b, function () use ($group, $b, $revision, $headers) {
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/member-removals', ['member_id' => $b->public_id, 'ownership_revision' => $revision], $headers)->assertOk();
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/messages', ['body' => 'Private during absence', 'client_id' => 'during-absence'], $headers)->assertCreated();
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/members', ['usernames' => ['next']], $headers)->assertOk();
            $this->postJson('/api/v1/conversations/'.$group->public_id.'/messages', ['body' => 'Visible after return', 'client_id' => 'after-return'], $headers)->assertCreated();
        });
        $this->assertSame(200, $result['code']);
        $this->assertSame(['Visible after return'], array_column($result['payload']['data'], 'body'));
    }
}
