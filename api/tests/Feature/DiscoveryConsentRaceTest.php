<?php
namespace Tests\Feature;

use App\Http\Controllers\DiscoveryController;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

/** Real local PostgreSQL processes. Never connected to a deployed database. */
class DiscoveryConsentRaceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        if (DB::getDriverName() !== 'pgsql' || !function_exists('pcntl_fork')) $this->markTestSkipped('Local PostgreSQL and pcntl required.');
        if (getenv('DISCOVERY_ISOLATED_RACE') !== '1' || config('database.connections.pgsql.host') !== '/tmp/sj-isolated-api/pgsocket' || config('database.connections.pgsql.database') !== 'sj_discovery_test') $this->markTestSkipped('Explicit throwaway local database required.');
        $this->artisan('migrate:fresh', ['--force' => true])->assertExitCode(0);
    }
    public function test_two_first_saves_cannot_both_commit_the_same_revision(): void
    {
        if (DB::getDriverName() !== 'pgsql' || !function_exists('pcntl_fork')) $this->markTestSkipped('Local PostgreSQL and pcntl required.');
        config(['discovery.enabled' => true]);
        [$owner] = $this->member('raceowner');
        $post = Post::create(['user_id' => $owner->id, 'body' => 'Race fixture', 'kind' => 'post']);
        $directory = sys_get_temp_dir().'/discovery-race-'.bin2hex(random_bytes(8));
        mkdir($directory, 0700); $children = [];
        DB::disconnect();
        try {
            for ($i = 0; $i < 2; $i++) {
                $pid = pcntl_fork();
                if ($pid === -1) throw new \RuntimeException('Could not fork isolated race worker.');
                if ($pid === 0) {
                    try {
                        $deadline = microtime(true) + 10;
                        while (!file_exists($directory.'/start')) { if (microtime(true) > $deadline) throw new \RuntimeException('Barrier timeout'); usleep(1000); }
                        DB::purge();
                        $user = User::findOrFail($owner->id);
                        $request = Request::create('/fixture', 'PUT', ['author_opted_in' => true, 'revision' => 0]);
                        $request->setUserResolver(fn () => $user);
                        $response = app(DiscoveryController::class)->update($request, Post::findOrFail($post->id));
                        $result = $response->getStatusCode();
                    } catch (HttpException $e) { $result = $e->getStatusCode(); }
                    catch (\Throwable $e) { $result = 'error:'.get_class($e).':'.$e->getMessage(); }
                    try { file_put_contents($directory.'/'.$i, (string) $result); }
                    finally { DB::disconnect(); exit(0); }
                }
                $children[] = $pid;
            }
            // Hold the common post lock until both processes are observed
            // waiting for it. This proves overlap rather than hoping the
            // scheduler runs the two revision-zero requests together.
            DB::purge(); DB::beginTransaction();
            Post::whereKey($post->id)->lockForUpdate()->firstOrFail();
            touch($directory.'/start');
            $deadline = microtime(true) + 10; $waiting = 0;
            while (microtime(true) < $deadline) {
                DB::select('SELECT pg_stat_clear_snapshot()');
                $waiting = (int) DB::selectOne("SELECT count(*) AS waiting FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'")->waiting;
                if ($waiting >= 2) break;
                usleep(1000);
            }
            DB::commit();
            $this->assertGreaterThanOrEqual(2, $waiting, 'Both local workers must overlap at the post lock.');
            foreach ($children as $pid) { pcntl_waitpid($pid, $status); $this->assertTrue(pcntl_wifexited($status)); $this->assertSame(0, pcntl_wexitstatus($status)); }
            $codes = [file_get_contents($directory.'/0'), file_get_contents($directory.'/1')]; sort($codes);
            $this->assertSame(['200', '409'], $codes);
            DB::purge();
            $this->assertDatabaseCount('discovery_eligibility', 1);
            $this->assertDatabaseHas('discovery_eligibility', ['post_id' => $post->id, 'author_opted_in' => true, 'revision' => 1, 'moderation' => 'pending', 'public_post' => false]);
        } finally {
            if (DB::transactionLevel() > 0) DB::rollBack();
            foreach ($children as $pid) pcntl_waitpid($pid, $status);
            foreach (glob($directory.'/*') ?: [] as $file) unlink($file);
            rmdir($directory);
        }
    }
}
