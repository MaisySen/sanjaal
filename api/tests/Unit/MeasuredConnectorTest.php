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
    public function test_locked_factory_binding_remains_lazy_and_preserves_reconnect(): void
    {
        $container = new \Illuminate\Container\Container;
        $meter = new MeasuredConnector(new \Illuminate\Database\Connectors\SQLiteConnector);
        $container->instance('db.connector.sqlite', $meter);
        $factory = new \Illuminate\Database\Connectors\ConnectionFactory($container);
        $config = ['driver' => 'sqlite', 'database' => ':memory:', 'prefix' => ''];
        $db = $factory->make($config);
        $this->assertSame(0, $meter->calls, 'factory construction must remain lazy');
        $this->assertEquals(7, $db->select('select 7 as value')[0]->value);
        $db->select('select 8');
        $this->assertSame(1, $meter->calls);
        $db->disconnect();
        $db->setReconnector(function ($connection) use ($factory, $config) {
            $fresh = $factory->make($config);
            $connection->setPdo($fresh->getRawPdo());
        });
        $this->assertEquals(9, $db->select('select 9 as value')[0]->value);
        $this->assertSame(2, $meter->calls);
    }

    public function test_request_windows_reset_on_failure_and_do_not_count_outside_work(): void
    {
        $window = new \App\Support\ConnectionTiming;
        $inner = new class implements ConnectorInterface {
            public bool $fail = false;
            public function connect(array $config) {
                if ($this->fail) { throw new PDOException('synthetic initialization failure'); }
                return new PDO('sqlite::memory:');
            }
        };
        $meter = new MeasuredConnector($inner, $window);
        $meter->connect([]);
        $window->begin();
        $this->assertSame(0, $window->finish()['calls']);
        $window->begin();
        try {
            $inner->fail = true;
            $meter->connect([]);
        } catch (PDOException) {
        } finally {
            $first = $window->finish();
        }
        $this->assertSame(1, $first['calls']);
        $window->begin();
        $inner->fail = false;
        $meter->connect([]);
        $meter->connect([]);
        $this->assertSame(2, $window->finish()['calls']);
        $window->begin();
        $this->assertSame(['calls' => 0, 'milliseconds' => 0.0], $window->finish());
    }

    public function test_factory_preserves_initialization_exception_wrapper_with_meter(): void
    {
        foreach ([false, true] as $measured) {
            $container = new \Illuminate\Container\Container;
            $inner = new class implements ConnectorInterface {
                public int $calls = 0;
                public function connect(array $config) { $this->calls++; throw new PDOException('synthetic initialization failure'); }
            };
            $container->instance('db.connector.sqlite', $measured ? new MeasuredConnector($inner) : $inner);
            $db = (new \Illuminate\Database\Connectors\ConnectionFactory($container))->make(['driver' => 'sqlite', 'database' => ':memory:', 'prefix' => '']);
            try {
                $db->select('select 1');
                $this->fail('Expected failure');
            } catch (\Illuminate\Database\QueryException $e) {
                $this->assertSame(PDOException::class, get_class($e->getPrevious()));
                $this->assertSame('synthetic initialization failure', $e->getPrevious()->getMessage());
            }
            $this->assertSame(1, $inner->calls, 'no added retry');
        }
    }

}
