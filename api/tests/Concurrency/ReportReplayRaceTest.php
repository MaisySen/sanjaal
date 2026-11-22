<?php

namespace Tests\Concurrency;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Independent operator processes against an explicitly disposable local PostgreSQL database. */
class ReportReplayRaceTest extends TestCase
{
    protected function setUp(): void
    {
        if (getenv('PG_RACE') !== '1' || getenv('DB_CONNECTION') !== 'pgsql'
            || getenv('APP_ENV') !== 'testing' || getenv('DB_URL')) {
            $this->markTestSkipped('Requires explicitly enabled disposable local PostgreSQL.');
        }
        parent::setUp();
        $db = DB::connection();
        $this->assertSame('pgsql', $db->getDriverName());
        $host = $db->getConfig('host');
        $this->assertMatchesRegularExpression('~^/tmp/sj-report-pg\.[A-Za-z0-9]{8}/socket$~D', $host);
        $this->assertSame('sjreport_test', $db->getDatabaseName());
        $this->assertSame(54387, (int) $db->getConfig('port'));
        $this->assertSame(dirname($host).'/data', $db->selectOne("select current_setting('data_directory') as path")->path);
        $this->artisan('migrate:fresh', ['--force' => true]);
    }

    private function ownerId(): int
    {
        $owner = User::factory()->create();
        return $owner->id;
    }

    private function race(int $owner, array $targets, bool $timeout = false): array
    {
        $dir = sys_get_temp_dir().'/report-replay-race-'.bin2hex(random_bytes(6));
        mkdir($dir, 0700);
        $processes = [];
        try {
            foreach ($targets as $index => $target) {
                $command = [PHP_BINARY, '-c', php_ini_loaded_file(), __DIR__.'/report-replay-worker.php', $dir.'/go', (string) $owner, $target, $dir.'/ready-'.$index];
                $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path());
                $this->assertIsResource($process);
                $processes[] = [$process, $pipes];
            }
            $deadline = hrtime(true) + 10000000000;
            $pids = [];
            while (count($pids) !== count($targets)) {
                if (hrtime(true) >= $deadline) $this->fail('Operator workers did not reach the barrier.');
                $pids = [];
                foreach (array_keys($targets) as $index) {
                    if (is_file($dir.'/ready-'.$index)) $pids[] = (int) file_get_contents($dir.'/ready-'.$index);
                }
                if (count($pids) !== count($targets)) usleep(10000);
            }
            DB::beginTransaction();
            DB::table('users')->where('id', $owner)->lockForUpdate()->first();
            touch($dir.'/go');
            $blocked = 0;
            while ($blocked !== count($targets)) {
                if (hrtime(true) >= $deadline) $this->fail('Operator workers did not contend for the report lock.');
                DB::select('select pg_stat_clear_snapshot()');
                $marks = implode(',', array_fill(0, count($pids), '?'));
                $blocked = (int) DB::selectOne("select count(*) as n from pg_stat_activity where pid in ($marks) and wait_event_type = 'Lock'", $pids)->n;
                if ($blocked !== count($targets)) usleep(10000);
            }
            $this->assertSame(count($targets), $blocked);
            if (! $timeout) DB::commit();
            $codes = [];
            foreach ($processes as [$process, $pipes]) {
                $out = stream_get_contents($pipes[1]);
                $error = stream_get_contents($pipes[2]);
                fclose($pipes[1]); fclose($pipes[2]);
                $exit = proc_close($process);
                $this->assertSame(0, $exit, 'Operator fixture worker failed: '.$error);
                $result = json_decode($out, true, flags: JSON_THROW_ON_ERROR);
                $codes[] = $result;
            }
            $processes = [];

            return $codes;
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($processes as [$process, $pipes]) {
                if (is_resource($process)) { proc_terminate($process); proc_close($process); }
            }
            foreach (array_keys($targets) as $index) @unlink($dir.'/ready-'.$index);
            @unlink($dir.'/go');
            @rmdir($dir);
        }
    }

    public function test_held_owner_lock_fails_closed_and_same_key_can_retry(): void
    {
        $owner = $this->ownerId();
        $started = hrtime(true);
        $results = $this->race($owner, ['original-post'], true);
        $this->assertSame(503, $results[0]['code']);
        $this->assertLessThan(5, (hrtime(true) - $started) / 1000000000);
        $this->assertSame(0, DB::table('reports')->count());
        $this->assertSame(0, DB::table('report_events')->count());
        $retry = $this->race($owner, ['original-post']);
        $this->assertSame(201, $retry[0]['code']);
        $this->assertSame(1, DB::table('reports')->count());
        $this->assertSame(1, DB::table('report_events')->count());
    }

    public function test_simultaneous_identical_reports_return_one_receipt(): void
    {
        $owner = $this->ownerId();
        $results = $this->race($owner, ['original-post', 'original-post']);
        $codes = array_column($results, 'code'); sort($codes);
        $this->assertSame([200, 201], $codes);
        $this->assertSame($results[0]['receipt'], $results[1]['receipt']);
        $this->assertSame(1, DB::table('reports')->count());
        $this->assertSame(1, DB::table('report_events')->count());
    }

    public function test_simultaneous_conflicting_payloads_cannot_rebind_the_key(): void
    {
        $owner = $this->ownerId();
        $results = $this->race($owner, ['original-post', 'another-post']);
        $codes = array_column($results, 'code'); sort($codes);
        $this->assertSame([201, 409], $codes);
        $winner = $results[0]['code'] === 201 ? 'original-post' : 'another-post';
        $this->assertSame($winner, DB::table('reports')->sole()->target_id);
        $this->assertSame(1, DB::table('reports')->count());
        $this->assertSame(1, DB::table('report_events')->count());
    }
}
