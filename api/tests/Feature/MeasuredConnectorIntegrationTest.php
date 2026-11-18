<?php

namespace Tests\Feature;

use App\Support\MeasuredConnector;
use Illuminate\Database\Connectors\ConnectorInterface;
use Illuminate\Database\Connectors\ConnectionFactory;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Test-only binding. Production registration is deliberately absent. Runs on throwaway PG in CI; SQLite lazy paths have separate unit tests. */
class MeasuredConnectorIntegrationTest extends TestCase
{
    use DatabaseMigrations { runDatabaseMigrations as private migrateFixture; }

    public function runDatabaseMigrations(): void
    {
        if (config('database.connections.'.config('database.default').'.driver') !== 'pgsql') {
            $this->markTestSkipped('Cold purge requires the throwaway PostgreSQL service.');
        }
        $this->migrateFixture();
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
        $meter = new MeasuredConnector($counting);
        $baseline = [];
        $queries = 0;
        DB::listen(function () use (&$queries) { $queries++; });
        foreach ([false, true] as $measured) {
            $this->app->instance('db.connector.'.$driver, $measured ? $meter : $counting);
            DB::purge();
            $before = $counting->calls;
            foreach ([['/api/v1/ping', []], ['/api/v1/auth/me', []], ['/api/v1/auth/me', $headers], ['/api/v1/auth/me', $headers], ['/api/v1/posts', $headers]] as $i => [$path, $auth]) {
                $queries = 0;
                $response = $this->getJson($path, $auth);
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
