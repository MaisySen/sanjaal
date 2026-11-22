<?php
// Fixed local controller operations only. No arbitrary command or remote database.
use App\Http\Controllers\ChatController;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

try {
    if (getenv('PG_RACE') !== '1' || getenv('APP_ENV') !== 'testing' || getenv('DB_CONNECTION') !== 'pgsql' || getenv('DB_URL')) {
        throw new RuntimeException('Isolated group fixture is not enabled.');
    }
    [, $barrier, $group, $actor, $operation, $target, $revision, $ready] = $argv;
    $parent = realpath(dirname($barrier));
    $temporary = realpath(sys_get_temp_dir());
    if (! $parent || ! $temporary || ! str_starts_with($parent, $temporary.'/group-ownership-race-') || basename($barrier) !== 'go'
        || dirname($ready) !== $parent || ! preg_match('/^ready-[0-9]+$/D', basename($ready))
        || ! in_array($operation, ['transfer', 'remove', 'send', 'poll', 'leave'], true)) {
        throw new RuntimeException('Invalid group fixture operation or barrier.');
    }
    require __DIR__.'/../../vendor/autoload.php';
    $app = require __DIR__.'/../../bootstrap/app.php';
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $db = DB::connection();
    $host = $db->getConfig('host');
    if ($db->getDriverName() !== 'pgsql' || $db->getDatabaseName() !== 'sjownership_test'
        || (int) $db->getConfig('port') !== 54388
        || preg_match('~^/tmp/sj-ownership-pg\.[A-Za-z0-9]{8}/socket$~D', $host) !== 1
        || $db->selectOne("select current_setting('data_directory') as path")->path !== dirname($host).'/data') {
        throw new RuntimeException('Group fixture requires its disposable local database.');
    }
    $db->statement("set statement_timeout = '5s'");
    config(['group_ownership.enabled' => true, 'group_member_removal.enabled' => true]);
    $user = User::findOrFail((int) $actor);
    $parameters = match ($operation) {
        'send' => ['body' => 'Synthetic concurrent message', 'client_id' => 'group-removal-race-message'],
        'poll' => ['after_seq' => 0, 'wait' => 4, 'typing' => ''],
        default => ['member_id' => $target, 'ownership_revision' => $revision],
    };
    $request = Request::create('/synthetic-group-membership', $operation === 'poll' ? 'GET' : 'POST', $parameters);
    $request->headers->set('Accept', 'application/json');
    $app->instance('request', $request);
    $request->setUserResolver(fn () => $user);
    if ($operation === 'poll') {
        DB::listen(function ($query) use ($ready, $barrier) {
            if (file_exists($ready.'.poll') || ! str_starts_with(strtolower($query->sql), 'select') || ! str_contains($query->sql, '"messages"')) return;
            file_put_contents($ready.'.poll', 'waiting');
            $deadline = hrtime(true) + 15000000000;
            while (! file_exists($barrier.'.read')) {
                if (hrtime(true) > $deadline) throw new RuntimeException('Group poll read barrier expired.');
                usleep(1000);
            }
        });
    }
    file_put_contents($ready.'.tmp', (string) $db->selectOne('select pg_backend_pid() as pid')->pid);
    rename($ready.'.tmp', $ready);
    $deadline = hrtime(true) + 15000000000;
    while (! file_exists($barrier)) {
        if (hrtime(true) > $deadline) throw new RuntimeException('Group fixture barrier expired.');
        usleep(1000);
    }
    $payload = [];
    try {
        $controller = $app->make(ChatController::class);
        $response = match ($operation) {
            'transfer' => $controller->transferOwnership($request, $group),
            'remove' => $controller->removeMember($request, $group),
            'send' => $controller->send($request, $group),
            'poll' => $controller->messages($request, $group),
            default => $controller->leave($request, $group),
        };
        $code = $response->getStatusCode();
        if ($operation === 'poll') $payload = $response->getData(true);
    } catch (HttpExceptionInterface $error) {
        $code = $error->getStatusCode();
    }
    echo json_encode(['code' => $code, 'payload' => $payload], JSON_THROW_ON_ERROR);
} catch (Throwable $error) {
    fwrite(STDERR, get_class($error).': '.$error->getMessage());
    exit(2);
}
