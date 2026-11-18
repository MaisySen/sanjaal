<?php
// Exact-image refusal check. Network disabled, no DB configured or accessed.
require '/app/vendor/autoload.php';
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app['config']->set('wallet.member_transfers_enabled', false);
$app['config']->set('services.esewa.product_code', '');
$app['config']->set('services.esewa.secret', '');
$app->instance(App\Contracts\PayoutProvider::class, new App\Services\DisabledPayout());
$controller = $app->make(App\Http\Controllers\WalletController::class);
$request = Illuminate\Http\Request::create('/synthetic-wallet-refusal', 'POST');
foreach (['transfer', 'startTopup', 'requestWithdrawal'] as $method) {
    $response = $controller->$method($request);
    if ($response->getStatusCode() !== 503) throw new RuntimeException('Money hold not enforced for '.$method);
    echo json_encode(['method'=>$method,'status'=>$response->getStatusCode(),'body'=>$response->getData(true)]).PHP_EOL;
}
