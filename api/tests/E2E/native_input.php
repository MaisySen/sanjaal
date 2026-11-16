<?php
// CI-only native tap bridge. Never registered in the application's routes.
// Fixed adb commands only; require the throwaway token and an explicit CI opt-in.
header('Content-Type: application/json');
$fixture = dirname((string) getenv('E2E_JWKS_FILE'));
$expected = trim((string) @file_get_contents($fixture.'/token.txt'));
if (getenv('E2E_NATIVE_INPUT') !== '1' || $expected === '' || ! hash_equals('Bearer '.$expected, $_SERVER['HTTP_AUTHORIZATION'] ?? '')) {
    http_response_code(403);
    echo json_encode(['message' => 'Fixture native input disabled']);
    exit;
}
$input = json_decode(file_get_contents('php://input'), true);
$x = $input['x'] ?? null;
$y = $input['y'] ?? null;
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || ! is_int($x) || ! is_int($y) || min($x, $y) < 0 || max($x, $y) > 4096) {
    http_response_code(422);
    echo json_encode(['message' => 'Invalid fixture tap']);
    exit;
}
$adb = rtrim(getenv('ANDROID_HOME') ?: getenv('ANDROID_SDK_ROOT'), '/').'/platform-tools/adb';
$run = static function (array $args) use ($adb): array {
    $p = proc_open([$adb, ...$args], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (! is_resource($p)) return [1, '', 'adb unavailable'];
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    return [proc_close($p), $stdout, $stderr];
};
[$code] = $run(['shell', 'input', 'tap', (string) $x, (string) $y]);
usleep(900000);
$dir = __DIR__.'/../../../app/build/screenshots';
@mkdir($dir, 0755, true);
[$capture, $png] = $run(['exec-out', 'screencap', '-p']);
if ($capture === 0) file_put_contents($dir.'/poll_native_display.png', $png);
[, $ime] = $run(['shell', 'dumpsys', 'input_method']);
file_put_contents($dir.'/poll_native_ime.txt', 'tap x='.$x.' y='.$y."\n".$ime);
http_response_code($code === 0 ? 200 : 502);
echo json_encode(['ok' => $code === 0]);
