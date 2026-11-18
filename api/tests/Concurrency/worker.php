<?php
// Worker for the Postgres race tests. Boots the app, waits for the go file, sends one request as one user,
// prints the HTTP status. Used only by tests/Concurrency/PostgresRaceTest.php against a local throwaway database.
use Illuminate\Http\Request;

[, $go, $jwksFile, $token, $method, $uri, $json] = $argv;
require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$kernel->bootstrap();
config(['services.uploads.replay_safe' => true, 'wallet.member_transfers_enabled' => true]);
config(['services.auth0.domain' => 'tenant.example.auth0.com', 'services.auth0.audience' => 'https://api.test', 'services.auth0.jwks' => json_decode(file_get_contents($jwksFile), true)]);
if (getenv('PAYOUT_FAKE') === '1') {
    require_once __DIR__.'/FakePayout.php';
    $app->instance(App\Contracts\PayoutProvider::class, new Tests\Concurrency\FakePayout());
}
if (getenv('B2_RACE_FAKE') === '1') {
    // Fake B2 for the budget race: slow upload, nothing confirmed by name lookups, every upload logged to a shared file.
    config(['services.b2.key_id' => 'k', 'services.b2.key' => 's', 'services.b2.bucket' => 'b', 'services.b2.bucket_id' => 'bid', 'services.uploads.b2_budget_bytes' => (int) getenv('B2_RACE_BUDGET')]);
    \Illuminate\Support\Facades\Http::fake([
        '*b2_authorize_account*' => \Illuminate\Support\Facades\Http::response(['authorizationToken' => 'a', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.test', 'downloadUrl' => 'https://dl.test']]]),
        '*b2_get_upload_url*' => \Illuminate\Support\Facades\Http::response(['authorizationToken' => 'u', 'uploadUrl' => 'https://up.test/x']),
        '*b2_list_file_names*' => \Illuminate\Support\Facades\Http::response(['files' => []]),
        'https://up.test/*' => function ($r) { usleep(400000); file_put_contents(getenv('B2_RACE_LOG'), $r->header('X-Bz-File-Name')[0]."\n", FILE_APPEND | LOCK_EX); return \Illuminate\Support\Facades\Http::response([], 200); },
    ]);
}
$deadline = microtime(true) + 30;
while (! file_exists($go) && microtime(true) < $deadline) {
    usleep(500);
}
// Fixed CI-only command branch. No user routes or arbitrary command execution.
if ($method === 'PRUNE_EXPIRED_STORIES') {
    $code = \Illuminate\Support\Facades\Artisan::call('stories:prune-expired', ['--apply'=>true,'--limit'=>10]);
    echo $code === 0 ? 200 : 500;
    exit;
}
$body = json_decode($json, true);
if (isset($body['_fixture_file'])) {
    $path = $body['_fixture_file'];
    unset($body['_fixture_file']);
    $file = new \Illuminate\Http\UploadedFile($path, 'fixture.png', 'image/png', null, true);
    $files = (str_ends_with($uri, '/stories') || str_ends_with($uri, '/messages')) ? ['media' => $file] : ['media' => [$file]];
    $req = Request::create($uri, $method, $body, [], $files, ['HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer '.$token]);
} else {
    $req = Request::create($uri, $method, [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer '.$token], $json);
}
$res = $kernel->handle($req);
echo $res->getStatusCode();
