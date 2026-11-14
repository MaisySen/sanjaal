<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\ChatController;
use App\Http\Controllers\EngagementController;
use App\Http\Controllers\PostController;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Route;

Route::get('/v1/media/{publicId}', [\App\Http\Controllers\MediaController::class, 'show'])->whereUuid('publicId');
Route::get('/v1/ping', fn () => response()->json(['app' => 'sanjaal', 'status' => 'ok']));

Route::prefix('v1/auth')->middleware('auth:auth0')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::patch('/me', [AuthController::class, 'update']);
});

Route::prefix('v1')->middleware('auth:auth0')->group(function () {
    Route::post('/broadcasting/auth', fn (\Illuminate\Http\Request $r) => Broadcast::auth($r));

    Route::get('/posts', [PostController::class, 'index']);
    Route::post('/posts', [PostController::class, 'store'])->middleware('throttle:30,1');
    Route::get('/posts/{post}', [PostController::class, 'show']);
    Route::delete('/posts/{post}', [PostController::class, 'destroy']);
    Route::post('/posts/{post}/like', [EngagementController::class, 'like']);
    Route::delete('/posts/{post}/like', [EngagementController::class, 'unlike']);
    Route::get('/posts/{post}/comments', [EngagementController::class, 'comments']);
    Route::post('/posts/{post}/comments', [EngagementController::class, 'comment'])->middleware('throttle:30,1');
    Route::post('/users/{username}/follow', [EngagementController::class, 'follow']);
    Route::delete('/users/{username}/follow', [EngagementController::class, 'unfollow']);

    Route::get('/conversations', [ChatController::class, 'index']);
    Route::post('/conversations', [ChatController::class, 'store']);
    Route::get('/conversations/{conversation}/messages', [ChatController::class, 'messages']);
    Route::post('/conversations/{conversation}/messages', [ChatController::class, 'send'])->middleware('throttle:120,1');
    Route::post('/conversations/{conversation}/read', [ChatController::class, 'read']);

    Route::get('/wallet', [\App\Http\Controllers\WalletController::class, 'show']);
    Route::get('/wallet/entries', [\App\Http\Controllers\WalletController::class, 'entriesList']);
    Route::post('/wallet/transfer', [\App\Http\Controllers\WalletController::class, 'transfer'])->middleware('throttle:30,1');
    Route::post('/wallet/topups', [\App\Http\Controllers\WalletController::class, 'startTopup'])->middleware('throttle:10,1');
    Route::get('/wallet/topups/{id}', [\App\Http\Controllers\WalletController::class, 'topupStatus']);
});
