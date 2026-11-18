<?php
// Runs inside the exact candidate image, no credentials or production network.
require '/app/vendor/autoload.php';
$window = new App\Support\ConnectionTiming;
$inner = new class implements Illuminate\Database\Connectors\ConnectorInterface {
    public int $calls = 0;
    public function connect(array $config) { $this->calls++; throw new PDOException('synthetic initialization failure'); }
};
$meter = new App\Support\MeasuredConnector($inner, $window);
$container = new Illuminate\Container\Container;
$container->instance('db.connector.sqlite', $meter);
$db = (new Illuminate\Database\Connectors\ConnectionFactory($container))->make(['driver'=>'sqlite','database'=>':memory:','prefix'=>'']);
$window->begin();
try { $db->select('select 1'); throw new RuntimeException('failure did not escape'); }
catch (Illuminate\Database\QueryException $e) {
    if (get_class($e->getPrevious()) !== PDOException::class || $inner->calls !== 1) throw new RuntimeException('failure semantics changed');
}
if ($window->finish()['calls'] !== 1) throw new RuntimeException('failure not accounted');
$middleware = new App\Http\Middleware\ConnectionTimingWindow($window);
$failure = new RuntimeException('synthetic downstream failure');
try { $middleware->handle(Illuminate\Http\Request::create('/'), function () use ($failure) { throw $failure; }); }
catch (RuntimeException $e) { if ($e !== $failure) throw $e; }
$r = $middleware->handle(Illuminate\Http\Request::create('/'), fn () => new Symfony\Component\HttpFoundation\Response('same',207));
if ($r->getStatusCode() !== 207 || $r->getContent() !== 'same' || !str_contains($r->headers->get('Server-Timing'),'0 connector calls')) throw new RuntimeException('reset or response changed');
echo "exact-image exception wrapping, one attempt, failed-call accounting and middleware reset passed\n";
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$actualWindow = $app->make(App\Support\ConnectionTiming::class);
$db = $app->make('db')->connection();
$actualWindow->begin();
$db->select('select 1 as fixture');
$db->select('select 2 as fixture');
if ($actualWindow->finish()['calls'] !== 1) throw new RuntimeException('exact-runtime lazy/reuse accounting failed');
$db->disconnect();
$actualWindow->begin();
$db->select('select 3 as fixture');
if ($actualWindow->finish()['calls'] !== 1) throw new RuntimeException('exact-runtime reconnect accounting failed');
echo "exact-image actual PostgreSQL lazy/reuse/reconnect request accounting passed\n";
