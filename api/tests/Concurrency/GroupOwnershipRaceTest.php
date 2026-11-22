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
        config(['group_ownership.enabled' => true]);
    }

    private function group(): array
    {
        [$a, $headers] = $this->member('owner');
        [$b] = $this->member('next');
        [$c] = $this->member('third');
        $snapshot = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Synthetic race', 'usernames' => ['next', 'third']], $headers)->assertCreated()->json('conversation');

        return [Conversation::where('public_id', $snapshot['public_id'])->firstOrFail(), $a, $b, $c, $snapshot['ownership_revision']];
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
}
