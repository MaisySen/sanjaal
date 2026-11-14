<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Public Android build download (debug-signed, arm64).
Route::get('/sanjaal-arm64.apk', function () {
    return response()->download(
        storage_path('dist/sanjaal-arm64.apk'),
        'sanjaal-arm64.apk',
        ['Content-Type' => 'application/vnd.android.package-archive']
    );
});
Route::redirect('/download', '/sanjaal-arm64.apk');
