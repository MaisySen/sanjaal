<?php

namespace Tests\Unit;

use Illuminate\Database\QueryException;
use Illuminate\Database\SQLiteConnection;
use PDO;
use PDOException;
use PHPUnit\Framework\TestCase;

/** Characterizes the rejected beforeExecuting/getPdo probe. It must not be used as passive instrumentation. */
class ConnectionProbeSemanticsTest extends TestCase
{
    private function connection(): SQLiteConnection
    {
        return new SQLiteConnection(fn () => new PDO('sqlite::memory:'), ':memory:');
    }

    private function rejectedProbe(SQLiteConnection $connection): object
    {
        $state = (object) ['resolutions' => 0];
        $connection->beforeExecuting(function ($query, $bindings, $db) use ($state) {
            if ($state->resolutions === 0) {
                $db->getPdo();
                $state->resolutions++;
            }
        });

        return $state;
    }

    public function test_probe_forces_an_unused_write_connection_on_read_split(): void
    {
        foreach ([false, true] as $probe) {
            $writes = 0;
            $reads = 0;
            $db = $this->connection();
            $db->setPdo(function () use (&$writes) { $writes++; return new PDO('sqlite::memory:'); });
            $db->setReadPdo(function () use (&$reads) { $reads++; return new PDO('sqlite::memory:'); });
            if ($probe) { $this->rejectedProbe($db); }
            $this->assertEquals(1, $db->select('select 1 as n')[0]->n);
            $this->assertSame(1, $reads);
            $this->assertSame($probe ? 1 : 0, $writes);
        }
    }

    public function test_probe_changes_connection_initialization_exception_type(): void
    {
        foreach ([false, true] as $probe) {
            $db = $this->connection();
            $db->setPdo(function () { throw new PDOException('synthetic initialization failure'); });
            if ($probe) { $this->rejectedProbe($db); }
            try {
                $db->select('select 1');
                $this->fail('Expected initialization failure');
            } catch (\Exception $e) {
                $this->assertSame($probe ? PDOException::class : QueryException::class, get_class($e));
            }
        }
    }

    public function test_probe_does_not_account_for_a_second_connection_resolution(): void
    {
        $opened = 0;
        $factory = function () use (&$opened) { $opened++; return new PDO('sqlite::memory:'); };
        $db = $this->connection();
        $db->setPdo($factory);
        $probe = $this->rejectedProbe($db);
        $db->select('select 1');
        $db->select('select 1');
        $this->assertSame(1, $opened, 'ordinary reuse opens no extra PDO');
        $db->disconnect();
        $db->setReconnector(function ($connection) use ($factory) { $connection->setPdo($factory); });
        $db->select('select 1');
        $this->assertSame(2, $opened);
        $this->assertSame(1, $probe->resolutions, 'the rejected probe missed the reconnect resolution');
    }
}
