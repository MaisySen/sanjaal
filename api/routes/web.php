<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// One current Android download: the latest CI release (debug-signed for now). Change APK_URL to move it.
$apk = fn () => redirect()->away(env('APK_URL', 'https://github.com/MaisySen/sanjaal/releases/download/v0.2.0/app-arm64-v8a-release.apk'));
Route::get('/sanjaal-arm64.apk', $apk);
Route::get('/download', $apk);

// eSewa top up pages (public, tied to an unguessable top up id).
Route::get('/pay/esewa/{id}', [\App\Http\Controllers\WalletController::class, 'payPage'])->whereUuid('id');
Route::get('/pay/esewa/{id}/{result}', [\App\Http\Controllers\WalletController::class, 'payReturn'])->whereUuid('id')->whereIn('result', ['success', 'failure']);
