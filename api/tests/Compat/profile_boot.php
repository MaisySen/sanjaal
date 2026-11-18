<?php
// Isolated current-image CLI probe. Not installed as a route or included in any runtime image.
$start = hrtime(true);
define('LARAVEL_START', microtime(true));
require '/app/vendor/autoload.php';
$autoload = hrtime(true);
$app = require '/app/bootstrap/app.php';
$created = hrtime(true);
$parts = [];
$marks = [];
$instrumented = !in_array('--baseline', $argv ?? [], true);
foreach ($instrumented ? ['LoadEnvironmentVariables', 'LoadConfiguration', 'HandleExceptions', 'RegisterFacades', 'RegisterProviders', 'BootProviders'] : [] as $name) {
    $class = 'Illuminate\\Foundation\\Bootstrap\\'.$name;
    $app->beforeBootstrapping($class, function () use (&$marks, $name) { $marks[$name] = hrtime(true); });
    $app->afterBootstrapping($class, function () use (&$parts, &$marks, $name) { $parts[$name] = (hrtime(true) - $marks[$name]) / 1e6; });
}
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
$resolved = hrtime(true);
$response = $kernel->handle(Illuminate\Http\Request::create('/api/v1/ping', 'GET', [], [], [], ['HTTP_ACCEPT' => 'application/json']));
$done = hrtime(true);
if ($response->getStatusCode() !== 200) throw new RuntimeException('isolated ping failed');
$kernel->terminate(Illuminate\Http\Request::create('/api/v1/ping'), $response);
echo json_encode([
    'instrumented' => $instrumented, 'sapi' => PHP_SAPI, 'opcache_cli' => ini_get('opcache.enable_cli'),
    'config_cached' => $app->configurationIsCached(), 'routes_cached' => $app->routesAreCached(),
    'autoload_ms' => ($autoload - $start) / 1e6, 'app_creation_ms' => ($created - $autoload) / 1e6,
    'kernel_resolution_ms' => ($resolved - $created) / 1e6, 'bootstrap_stages_ms' => $parts,
    'kernel_handle_ms' => ($done - $resolved) / 1e6, 'total_ms' => ($done - $start) / 1e6,
    'status' => $response->getStatusCode(), 'server_timing' => $response->headers->all('Server-Timing'),
    'loaded_files' => count(get_included_files()), 'peak_memory_bytes' => memory_get_peak_usage(true),
], JSON_UNESCAPED_SLASHES)."\n";
