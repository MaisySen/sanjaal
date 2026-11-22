<?php
// CI only router for `php -S`. Not part of the shipped image.
use Illuminate\Http\Request;

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
if ($uri !== '/' && file_exists(__DIR__.'/../../public'.$uri)) {
    return false;
}
require __DIR__.'/../../vendor/autoload.php';
$app = require_once __DIR__.'/../../bootstrap/app.php';
if ($uri === '/e2e/native-media') {
    require __DIR__.'/native_media.php';
    exit;
}
if ($uri === '/e2e/native-tap') {
    require __DIR__.'/native_input.php';
    exit;
}
if ($uri === '/oauth/token') {
    // CI fixture stand-in for the identity provider's token endpoint: hands out the throwaway token.
    header('Content-Type: application/json');
    echo json_encode(['access_token' => trim((string) @file_get_contents(dirname((string) getenv('E2E_JWKS_FILE')).'/token.txt')), 'expires_in' => 3000, 'refresh_token' => 'local-e2e']);
    exit;
}
$file = getenv('E2E_JWKS_FILE');
if (! $file || ! is_file($file)) {
    http_response_code(500);
    echo 'E2E_JWKS_FILE missing';
    exit;
}
$app->booted(function () use ($app, $file) {
    $app['config']->set('services.auth0.domain', 'tenant.example.auth0.com');
    $app['config']->set('services.auth0.audience', 'https://api.test');
    $app['config']->set('services.auth0.jwks', json_decode(file_get_contents($file), true));
});
// CI-only fault injection, only on the second disposable server (E2E_FAULT_AFTER_COMMIT=1, port 8001).
// Arm it with an authenticated POST; the next post creation commits normally and then loses its response
// (503), which is the "reply lost after the server saved it" case the replay-safe upload protocol covers.
if (getenv('E2E_FAULT_AFTER_COMMIT') === '1') {
    $expected = trim((string) @file_get_contents(dirname($file).'/token.txt'));
    $authorised = $expected !== '' && hash_equals('Bearer '.$expected, $_SERVER['HTTP_AUTHORIZATION'] ?? '');
    // Separate synthetic report fault, never arms the post/upload fixture.
    $reportFlag = dirname($file).'/report-fault-armed';
    if ($uri === '/e2e/report-fault-arm' && $_SERVER['REQUEST_METHOD'] === 'POST' && $authorised) {
        file_put_contents($reportFlag, '1');
        header('Content-Type: application/json');
        echo json_encode(['armed' => true]);
        exit;
    }
    if ($uri === '/api/v1/reports' && $_SERVER['REQUEST_METHOD'] === 'POST' && $authorised && is_file($reportFlag)) {
        @unlink($reportFlag);
        $kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
        $result = $kernel->handle(Request::capture());
        if ($result->getStatusCode() !== 201) {
            $result->send();
            exit;
        }
        header_remove('Content-Length');
        header_remove('Content-Type');
        http_response_code(503);
        header('Content-Type: application/json');
        echo json_encode(['message' => 'Synthetic report response lost after commit.']);
        exit;
    }
    $flag = dirname($file).'/fault-armed';
    if ($uri === '/e2e/fault-arm' && $_SERVER['REQUEST_METHOD'] === 'POST' && $authorised) {
        file_put_contents($flag, '1');
        header('Content-Type: application/json');
        echo json_encode(['armed' => true]);
        exit;
    }
    if ($uri === '/e2e/fault-count' && $authorised) {
        header('Content-Type: application/json');
        echo json_encode(['fired' => (int) @file_get_contents(dirname($file).'/fault-fired')]);
        exit;
    }
    if ($uri === '/api/v1/posts' && $_SERVER['REQUEST_METHOD'] === 'POST' && is_file($flag)) {
        @unlink($flag);
        file_put_contents(dirname($file).'/fault-fired', (string) (1 + (int) @file_get_contents(dirname($file).'/fault-fired')));
        // Run the real handler to commit, but never send its response: handleRequest() would flush and send it
        // (the server API closes output buffers), which made earlier runs deliver the real 201 and prove nothing.
        $kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);
        $kernel->handle(Request::capture());
        header_remove('Content-Length');
        header_remove('Content-Type');
        http_response_code(503);
        header('Content-Type: application/json');
        echo json_encode(['message' => 'Service temporarily unavailable. Try again.']);
        exit;
    }
}
$app->handleRequest(Request::capture());
