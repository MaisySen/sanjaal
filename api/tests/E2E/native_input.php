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
$prepare = ($input['prepare_notifications'] ?? false) === true;
$x = $input['x'] ?? null;
$y = $input['y'] ?? null;
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || (! $prepare && (! is_int($x) || ! is_int($y) || min($x, $y) < 0 || max($x, $y) > 4096))) {
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
$dir = __DIR__.'/../../../app/build/screenshots';
@mkdir($dir, 0755, true);
if ($prepare) {
    // The throwaway package only. Never bypass an arbitrary native dialog by tapping.
    // Capture its actual native UI first, then make the expected notification permission deterministic.
    $run(['shell', 'uiautomator', 'dump', '/sdcard/sanjaal-native-before.xml']);
    [, $ui] = $run(['exec-out', 'cat', '/sdcard/sanjaal-native-before.xml']);
    file_put_contents($dir.'/native_before.xml', $ui);
    [, $before] = $run(['shell', 'dumpsys', 'window']);
    file_put_contents($dir.'/native_window_before.txt', $before);
    [$grant, $out, $err] = $run(['shell', 'pm', 'grant', 'au.fintex.sanjaal', 'android.permission.POST_NOTIFICATIONS']);
    $focused = false;
    $after = '';
    for ($i = 0; $grant === 0 && $i < 20; $i++) {
        [, $after] = $run(['shell', 'dumpsys', 'window']);
        $focused = preg_match('/mCurrentFocus=[^\r\n]*au\.fintex\.sanjaal\//', $after) === 1;
        if ($focused) break;
        usleep(200000);
    }
    file_put_contents($dir.'/native_window_after.txt', $after);
    file_put_contents($dir.'/native_permission_setup.txt', 'grant_exit='.$grant."\n".$out.$err."\napp_focused=".($focused ? 'true' : 'false'));
    [$capture, $png] = $run(['exec-out', 'screencap', '-p']);
    if ($capture === 0) file_put_contents($dir.'/native_ready_display.png', $png);
    http_response_code($grant === 0 && $focused ? 200 : 502);
    echo json_encode(['ok' => $grant === 0 && $focused, 'app_focused' => $focused, 'notification_permission_prepared' => $grant === 0]);
    exit;
}
[$code] = $run(['shell', 'input', 'tap', (string) $x, (string) $y]);
usleep(900000);
[$capture, $png] = $run(['exec-out', 'screencap', '-p']);
if ($capture === 0) file_put_contents($dir.'/poll_native_display.png', $png);
[, $ime] = $run(['shell', 'dumpsys', 'input_method']);
file_put_contents($dir.'/poll_native_ime.txt', 'tap x='.$x.' y='.$y."\n".$ime);
http_response_code($code === 0 ? 200 : 502);
echo json_encode(['ok' => $code === 0]);
