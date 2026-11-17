<?php
// CI-only native media fixture bridge. Not registered in application routes.
// No user data, arbitrary paths, arbitrary packages, shell programs or arguments.
header('Content-Type: application/json');
$fixture = dirname((string) getenv('E2E_JWKS_FILE'));
$expected = trim((string) @file_get_contents($fixture.'/token.txt'));
$input = json_decode(file_get_contents('php://input'), true);
if (getenv('E2E_NATIVE_INPUT') !== '1' || $expected === '' || !hash_equals('Bearer '.$expected, $_SERVER['HTTP_AUTHORIZATION'] ?? '')) {
    http_response_code(403); echo json_encode(['ok'=>false]); exit;
}
$action = $input['action'] ?? '';
if ($_SERVER['REQUEST_METHOD'] !== 'POST' || !in_array($action,['prepare','camera','gallery','recording','poster','composer','story'],true)) {
    http_response_code(422); echo json_encode(['ok'=>false]); exit;
}
$adb = rtrim(getenv('ANDROID_HOME') ?: getenv('ANDROID_SDK_ROOT'),'/').'/platform-tools/adb';
$run = static function(array $args) use($adb): array {
    $p=proc_open([$adb,...$args],[1=>['pipe','w'],2=>['pipe','w']],$pipes);
    if (!is_resource($p)) return [1,''];
    $out=stream_get_contents($pipes[1]);$err=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);
    return [proc_close($p),$out.$err];
};
$dir=__DIR__.'/../../../app/build/screenshots';@mkdir($dir,0755,true);
$results=[];
if ($action==='prepare') {
    foreach (['CAMERA','RECORD_AUDIO','READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','POST_NOTIFICATIONS'] as $permission) {
        [$code,$out]=$run(['shell','pm','grant','au.fintex.sanjaal','android.permission.'.$permission]);$results[$permission]=$code;
    }
    // Fixed generated image, not the owner's library or a user-supplied file.
    $png=base64_decode('iVBORw0KGgoAAAANSUhEUgAAAKAAAADwCAIAAAAII/iNAAACfUlEQVR4nO3UQQ2AAAADsUHQgTCUIJ8PKprrYwaW7bifd9uxlWSeC62Ccde/5KBaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcV00rgXjKhjXReNaMK6CcR8h5gQMSRskWgAAAABJRU5ErkJggg==');
    file_put_contents($fixture.'/sanjaal-fixture.png',$png);
    [$push]=$run(['push',$fixture.'/sanjaal-fixture.png','/sdcard/Pictures/sanjaal-fixture.png']);$results['seed_push']=$push;
    [$scan]=$run(['shell','am','broadcast','-a','android.intent.action.MEDIA_SCANNER_SCAN_FILE','-d','file:///sdcard/Pictures/sanjaal-fixture.png']);$results['seed_scan']=$scan;
}
[, $window]=$run(['shell','dumpsys','window']);
$focused=preg_match('/mCurrentFocus=[^\r\n]*au\.fintex\.sanjaal\//',$window)===1;
file_put_contents($dir.'/native_media_'.$action.'_window.txt',$window);
[$capture,$bytes]=$run(['exec-out','screencap','-p']);
if($capture===0)file_put_contents($dir.'/native_media_'.$action.'.png',$bytes);
file_put_contents($dir.'/native_media_'.$action.'_result.txt',json_encode(['commands'=>$results,'app_focused'=>$focused,'capture_exit'=>$capture]));
$ok=$focused && $capture===0 && !array_filter($results,fn($code)=>$code!==0);
http_response_code($ok?200:502);echo json_encode(['ok'=>$ok,'app_focused'=>$focused,'commands'=>$results]);
