<?php
// CI only router for `php -S`. Not part of the shipped image.
use Illuminate\Http\Request;

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH));
if ($uri !== '/' && file_exists(__DIR__.'/../../public'.$uri)) {
    return false;
}
require __DIR__.'/../../vendor/autoload.php';
$app = require_once __DIR__.'/../../bootstrap/app.php';
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
$app->handleRequest(Request::capture());
