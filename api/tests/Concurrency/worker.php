<?php
// Worker for the Postgres race tests. Boots the app, waits for the go file, sends one request as one user,
// prints the HTTP status. Used only by tests/Concurrency/PostgresRaceTest.php against a local throwaway database.
use Illuminate\Http\Request;

[, $go, $jwksFile, $token, $method, $uri, $json] = $argv;
require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();
config(['services.auth0.domain' => 'tenant.example.auth0.com', 'services.auth0.audience' => 'https://api.test', 'services.auth0.jwks' => json_decode(file_get_contents($jwksFile), true)]);
if (getenv('PAYOUT_FAKE') === '1') {
    require_once __DIR__.'/FakePayout.php';
    $app->instance(App\Contracts\PayoutProvider::class, new Tests\Concurrency\FakePayout());
}
$deadline = microtime(true) + 30;
while (! file_exists($go) && microtime(true) < $deadline) {
    usleep(500);
}
$req = Request::create($uri, $method, [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer '.$token], $json);
$res = $kernel->handle($req);
echo $res->getStatusCode();
