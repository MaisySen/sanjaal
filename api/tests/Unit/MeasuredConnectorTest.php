<?php

namespace Tests\Unit;

use App\Support\MeasuredConnector;
use Illuminate\Database\Connectors\ConnectorInterface;
use PDO;
use PDOException;
use PHPUnit\Framework\TestCase;

class MeasuredConnectorTest extends TestCase
{
    public function test_no_eager_calls_and_same_config_pdo_and_one_call_per_demand(): void
    {
        $pdo = new PDO('sqlite::memory:');
        $inner = new class($pdo) implements ConnectorInterface {
            public array $received = [];
            public function __construct(private PDO $pdo) {}
            public function connect(array $config) { $this->received[] = $config; return $this->pdo; }
        };
        $meter = new MeasuredConnector($inner);
        $this->assertSame([], $inner->received);
        $this->assertSame(0, $meter->calls);
        $config = ['driver' => 'pgsql', 'host' => ['a', 'b'], 'options' => [PDO::ATTR_PERSISTENT => true]];
        $this->assertSame($pdo, $meter->connect($config));
        $this->assertSame([$config], $inner->received);
        $this->assertSame(1, $meter->calls);
        $this->assertGreaterThanOrEqual(0, $meter->milliseconds);
        $this->assertSame($pdo, $meter->connect($config));
        $this->assertCount(2, $inner->received);
        $this->assertSame(2, $meter->calls);
    }

    public function test_original_exception_object_escapes_without_retry(): void
    {
        $failure = new PDOException('synthetic initialization failure');
        $inner = new class($failure) implements ConnectorInterface {
            public int $attempts = 0;
            public function __construct(private PDOException $failure) {}
            public function connect(array $config) { $this->attempts++; throw $this->failure; }
        };
        $meter = new MeasuredConnector($inner);
        try {
            $meter->connect([]);
            $this->fail('Expected failure');
        } catch (PDOException $e) {
            $this->assertSame($failure, $e);
        }
        $this->assertSame(1, $inner->attempts);
        $this->assertSame(1, $meter->calls);
    }

    public function test_lazy_reuse_and_reconnect_do_not_gain_extra_connects(): void
    {
        $inner = new class implements ConnectorInterface {
            public int $attempts = 0;
            public function connect(array $config) { $this->attempts++; return new PDO('sqlite::memory:'); }
        };
        $meter = new MeasuredConnector($inner);
        $resolver = fn () => $meter->connect([]);
        $db = new \Illuminate\Database\SQLiteConnection($resolver, ':memory:');
        $this->assertSame(0, $meter->calls);
        $db->select('select 1');
        $db->select('select 1');
        $this->assertSame(1, $meter->calls);
        $db->disconnect();
        $db->setReconnector(fn ($connection) => $connection->setPdo($resolver));
        $db->select('select 1');
        $this->assertSame(2, $meter->calls);
        $this->assertSame(2, $inner->attempts);
    }
}
