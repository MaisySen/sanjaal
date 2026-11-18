<?php

namespace Tests\Unit;

use App\Support\MeasuredConnector;
use Illuminate\Database\Connectors\PostgresConnector;
use PDO;
use PDOException;
use PDOStatement;
use PHPUnit\Framework\TestCase;

class PostgresConnectorParityTest extends TestCase
{
    public function test_wrapper_preserves_all_framework_session_setup_calls_and_options(): void
    {
        $results = [];
        foreach ([false, true] as $measured) {
            $pdo = new class extends PDO {
                public array $statements = [];
                public function __construct() {}
                public function prepare(string $query, array $options = []): PDOStatement|false {
                    $this->statements[] = $query;
                    return new class extends PDOStatement {
                        public function execute(?array $params = null): bool { return true; }
                    };
                }
            };
            $inner = new class($pdo) extends PostgresConnector {
                public array $received = [];
                public function __construct(private PDO $pdo) {}
                public function createConnection($dsn, array $config, array $options) {
                    $this->received[] = [$dsn, $config, $options];
                    return $this->pdo;
                }
            };
            $config = ['driver' => 'pgsql', 'host' => 'fixture', 'database' => 'fixture', 'charset' => 'utf8',
                'search_path' => 'public', 'timezone' => 'UTC', 'isolation_level' => 'read committed',
                'synchronous_commit' => 'on', 'options' => [PDO::ATTR_PERSISTENT => true]];
            $connector = $measured ? new MeasuredConnector($inner) : $inner;
            $this->assertSame($pdo, $connector->connect($config));
            $this->assertCount(1, $inner->received);
            $this->assertCount(4, $pdo->statements);
            $results[] = [$inner->received, $pdo->statements];
        }
        $this->assertSame($results[0], $results[1]);
    }

    public function test_framework_lost_connection_retry_remains_inside_one_connector_call(): void
    {
        foreach ([false, true] as $measured) {
            $inner = new class extends PostgresConnector {
                public int $attempts = 0;
                public function connect(array $config) {
                    return $this->createConnection('fixture', [], []);
                }
                protected function createPdoConnection($dsn, $username, $password, $options) {
                    $this->attempts++;
                    if ($this->attempts === 1) { throw new PDOException('server closed the connection unexpectedly'); }
                    return new PDO('sqlite::memory:');
                }
            };
            $connector = $measured ? new MeasuredConnector($inner) : $inner;
            $this->assertInstanceOf(PDO::class, $connector->connect([]));
            $this->assertSame(2, $inner->attempts);
            if ($measured) { $this->assertSame(1, $connector->calls, 'call count is not physical PDO attempt count'); }
        }
    }
}
