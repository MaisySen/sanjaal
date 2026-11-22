<?php
// Test-only fixed command. No HTTP route, arbitrary command, remote database or production bootstrap.
use App\Http\Controllers\ReportController;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

try {
    if (getenv('PG_RACE') !== '1' || getenv('APP_ENV') !== 'testing' || getenv('DB_CONNECTION') !== 'pgsql' || getenv('DB_URL')) {
        throw new RuntimeException('Local operator fixture is not enabled.');
    }
    [, $barrier, $owner, $target, $ready] = $argv;
    $parent = realpath(dirname($barrier));
    $temporary = realpath(sys_get_temp_dir());
    if (! $parent || ! $temporary || ! str_starts_with($parent, $temporary.'/report-replay-race-') || basename($barrier) !== 'go') {
        throw new RuntimeException('Invalid operator fixture barrier.');
    }
    require __DIR__.'/../../vendor/autoload.php';
    $app = require __DIR__.'/../../bootstrap/app.php';
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $db = DB::connection();
    $host = $db->getConfig('host');
    if ($db->getDriverName() !== 'pgsql' || $db->getDatabaseName() !== getenv('DB_DATABASE')
        || $db->getDatabaseName() !== 'sjreport_test' || (int) $db->getConfig('port') !== 54387
        || preg_match('~^/tmp/sj-report-pg\.[A-Za-z0-9]{8}/socket$~D', $host) !== 1
        || $db->selectOne("select current_setting('data_directory') as path")->path !== dirname($host).'/data') {
        throw new RuntimeException('Operator fixture requires a disposable local database.');
    }
    if (dirname($ready) !== $parent || ! preg_match('/^ready-[0-9]+$/D', basename($ready))) {
        throw new RuntimeException('Invalid operator readiness path.');
    }
    file_put_contents($ready.'.tmp', (string) $db->selectOne('select pg_backend_pid() as pid')->pid);
    rename($ready.'.tmp', $ready);
    $deadline = hrtime(true) + 15000000000;
    while (! file_exists($barrier)) {
        if (hrtime(true) > $deadline) throw new RuntimeException('Operator fixture barrier expired.');
        usleep(1000);
    }
    $memberRef = $argv[5] ?? '';
    $request = Request::create('/api/v1/reports', 'POST', [
        'type' => $memberRef === '' ? 'post' : 'user', 'target' => $target, 'reason' => 'spam',
        'submission_id' => '11111111-1111-4111-8111-111111111111',
        ...($memberRef === '' ? [] : ['target_public_id' => $memberRef]),
    ]);
    $request->setUserResolver(fn () => User::findOrFail((int) $owner));
    try {
        $response = app(ReportController::class)->store($request);
        echo json_encode(['code' => $response->status(), 'receipt' => $response->getData(true)['report']['public_id']], JSON_THROW_ON_ERROR);
    } catch (\Symfony\Component\HttpKernel\Exception\HttpException $error) {
        echo json_encode(['code' => $error->getStatusCode(), 'receipt' => null], JSON_THROW_ON_ERROR);
    }

} catch (Throwable $error) {
    fwrite(STDERR, get_class($error));
    exit(2);
}
