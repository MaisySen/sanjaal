<?php

namespace Tests\Feature;

use App\Support\MeasuredConnector;
use Illuminate\Database\Connectors\ConnectorInterface;
use Illuminate\Database\Connectors\ConnectionFactory;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Test-only binding. Production registration is deliberately absent. Runs on throwaway PG in CI; SQLite lazy paths have separate unit tests. */
class MeasuredConnectorIntegrationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        if (config('database.connections.'.config('database.default').'.driver') !== 'pgsql') {
            $this->markTestSkipped('Cold purge requires the throwaway PostgreSQL service.');
        }
        // This test deliberately purges connections, so transactional fixtures do not apply.
        // Use fresh only on the CI throwaway database, never historical down migrations.
        $this->assertSame('sanjaal_test', config('database.connections.pgsql.database'));
        $this->assertSame('127.0.0.1', config('database.connections.pgsql.host'));
        $this->artisan('migrate:fresh', ['--force' => true])->assertExitCode(0);
        $this->beforeApplicationDestroyed(function () {
            DB::purge();
            $this->artisan('migrate:fresh', ['--force' => true])->assertExitCode(0);
        });
    }

    public function test_auth_status_body_and_query_counts_match_cold_and_reused_connections(): void
    {
        if (config('database.connections.'.config('database.default').'.driver') !== 'pgsql') {
            $this->markTestSkipped('Cold purge requires the throwaway PostgreSQL service, not ephemeral SQLite memory.');
        }
        [$user, $headers] = $this->member('connector_fixture');
        $driver = config('database.connections.'.config('database.default').'.driver');
        $original = (new ConnectionFactory($this->app))->createConnector(['driver' => $driver]);
        $counting = new class($original) implements ConnectorInterface {
            public int $calls = 0;
            public function __construct(private ConnectorInterface $inner) {}
            public function connect(array $config) { $this->calls++; return $this->inner->connect($config); }
        };
        $window = new \App\Support\ConnectionTiming;
        $meter = new MeasuredConnector($counting, $window);
        $baseline = [];
        $queries = 0;
        DB::listen(function () use (&$queries) { $queries++; });
        foreach ([false, true] as $measured) {
            $this->app->instance('db.connector.'.$driver, $measured ? $meter : $counting);
            DB::purge();
            $before = $counting->calls;
            foreach ([['/api/v1/ping', []], ['/api/v1/auth/me', []], ['/api/v1/auth/me', $headers], ['/api/v1/auth/me', $headers], ['/api/v1/posts', $headers]] as $i => [$path, $auth]) {
                $queries = 0;
                $window->begin();
                $response = $this->getJson($path, $auth);
                $connect = $window->finish();
                $this->assertSame($measured && $i === 2 ? 1 : 0, $connect['calls'], 'connector work belongs to its actual request');
                $result = [$response->status(), $response->json(), $queries];
                if (!$measured) { $baseline[$i] = $result; }
                else { $this->assertSame($baseline[$i], $result, 'status/body/query count at request '.$i); }
                if ($i < 2) { $this->assertSame($before, $counting->calls, 'public/unauthenticated request must not open PDO'); }
            }
            $this->assertSame(1, $counting->calls - $before, 'authenticated requests share one lazy connection');
        }
        $this->assertSame(1, $meter->calls);
        $this->assertSame(2, $counting->calls);
    }
}
