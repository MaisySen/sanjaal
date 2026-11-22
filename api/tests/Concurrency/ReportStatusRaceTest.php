<?php

namespace Tests\Concurrency;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/** Independent operator processes against an explicitly disposable local PostgreSQL database. */
class ReportStatusRaceTest extends TestCase
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

    private function receipt(): string
    {
        $owner = User::factory()->create();
        $receipt = (string) Str::uuid();
        $id = DB::table('reports')->insertGetId([
            'public_id' => $receipt, 'reporter_id' => $owner->id,
            'target_type' => 'post', 'target_id' => 'local-fixture', 'reason' => 'spam',
            'status' => 'received', 'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('report_events')->insert(['report_id' => $id, 'status' => 'received', 'created_at' => now()]);

        return $receipt;
    }

    private function race(string $receipt, array $statuses): array
    {
        $dir = sys_get_temp_dir().'/report-status-race-'.bin2hex(random_bytes(6));
        mkdir($dir, 0700);
        $processes = [];
        try {
            foreach ($statuses as $index => $status) {
                $command = [PHP_BINARY, '-c', php_ini_loaded_file(), __DIR__.'/report-status-worker.php', $dir.'/go', $receipt, $status, $dir.'/ready-'.$index];
                $process = proc_open($command, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path());
                $this->assertIsResource($process);
                $processes[] = [$process, $pipes];
            }
            $deadline = hrtime(true) + 10000000000;
            $pids = [];
            while (count($pids) !== count($statuses)) {
                if (hrtime(true) >= $deadline) $this->fail('Operator workers did not reach the barrier.');
                $pids = [];
                foreach (array_keys($statuses) as $index) {
                    if (is_file($dir.'/ready-'.$index)) $pids[] = (int) file_get_contents($dir.'/ready-'.$index);
                }
                if (count($pids) !== count($statuses)) usleep(10000);
            }
            DB::beginTransaction();
            DB::table('reports')->where('public_id', $receipt)->lockForUpdate()->first();
            touch($dir.'/go');
            $blocked = 0;
            while ($blocked !== count($statuses)) {
                if (hrtime(true) >= $deadline) $this->fail('Operator workers did not contend for the report lock.');
                DB::select('select pg_stat_clear_snapshot()');
                $marks = implode(',', array_fill(0, count($pids), '?'));
                $blocked = (int) DB::selectOne("select count(*) as n from pg_stat_activity where pid in ($marks) and wait_event_type = 'Lock'", $pids)->n;
                if ($blocked !== count($statuses)) usleep(10000);
            }
            $this->assertSame(count($statuses), $blocked);
            DB::commit();
            $codes = [];
            foreach ($processes as [$process, $pipes]) {
                $out = stream_get_contents($pipes[1]);
                $error = stream_get_contents($pipes[2]);
                fclose($pipes[1]); fclose($pipes[2]);
                $exit = proc_close($process);
                $this->assertSame(0, $exit, 'Operator fixture worker failed: '.$error);
                $result = json_decode($out, true, flags: JSON_THROW_ON_ERROR);
                $codes[] = $result['code'];
            }
            $processes = [];

            return $codes;
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($processes as [$process, $pipes]) {
                if (is_resource($process)) { proc_terminate($process); proc_close($process); }
            }
            foreach (array_keys($statuses) as $index) @unlink($dir.'/ready-'.$index);
            @unlink($dir.'/go');
            @rmdir($dir);
        }
    }

    private function history(string $receipt): array
    {
        $id = DB::table('reports')->where('public_id', $receipt)->value('id');

        return DB::table('report_events')->where('report_id', $id)->orderBy('id')->pluck('status')->all();
    }

    public function test_simultaneous_review_starts_record_one_event(): void
    {
        $receipt = $this->receipt();
        $this->assertSame([0, 0], $this->race($receipt, ['in_review', 'in_review']));
        $this->assertSame(['received', 'in_review'], $this->history($receipt));
    }

    public function test_closing_review_wins_without_a_backwards_event(): void
    {
        $receipt = $this->receipt();
        $codes = $this->race($receipt, ['closed', 'in_review']);
        $this->assertSame(0, $codes[0]);
        $this->assertContains($codes[1], [0, 1]);
        $this->assertSame('closed', DB::table('reports')->where('public_id', $receipt)->value('status'));
        $this->assertContains($this->history($receipt), [['received', 'closed'], ['received', 'in_review', 'closed']]);
    }

    public function test_simultaneous_closures_record_one_event(): void
    {
        $receipt = $this->receipt();
        $this->assertSame([0, 0], $this->race($receipt, ['closed', 'closed']));
        $this->assertSame(['received', 'closed'], $this->history($receipt));
    }
}
