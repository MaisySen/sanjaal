<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\ChatController;
use App\Http\Controllers\EngagementController;
use App\Http\Controllers\PostController;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Route;

Route::get('/v1/media/{publicId}', [\App\Http\Controllers\MediaController::class, 'show'])->whereUuid('publicId');
Route::get('/v1/ping', fn () => response()->json(['app' => 'sanjaal', 'status' => 'ok', 'media' => \App\Support\MediaStore::enabled() ? 'b2' : 'db']));

Route::prefix('v1/auth')->middleware('auth:auth0')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::get('/me/story-audience', [\App\Http\Controllers\StoryAudienceController::class, 'index']);
    Route::get('/me/story-audience/{username}', [\App\Http\Controllers\StoryAudienceController::class, 'show']);
    Route::put('/me/story-audience/{username}', [\App\Http\Controllers\StoryAudienceController::class, 'update'])->middleware('throttle:30,1');
    Route::get('/me/controls', [\App\Http\Controllers\MemberControlsController::class, 'show']);
    Route::patch('/me/controls', [\App\Http\Controllers\MemberControlsController::class, 'update'])->middleware('throttle:30,1');
    Route::patch('/me', [AuthController::class, 'update']);
    Route::post('/me/avatar', [\App\Http\Controllers\SocialController::class, 'avatar'])->middleware('throttle:10,1');
});

Route::prefix('v1')->middleware('auth:auth0')->group(function () {
    Route::post('/broadcasting/auth', fn (\Illuminate\Http\Request $r) => Broadcast::auth($r));

    Route::get('/home', [\App\Http\Controllers\HomeController::class, 'show']);
    Route::get('/discovery', [\App\Http\Controllers\DiscoveryController::class, 'index'])->middleware('throttle:60,1');
    Route::get('/posts', [PostController::class, 'index']);
    Route::post('/posts', [PostController::class, 'store'])->middleware('throttle:30,1');
    Route::get('/posts/{post:public_id}/discovery', [\App\Http\Controllers\DiscoveryController::class, 'show']);
    Route::put('/posts/{post:public_id}/discovery', [\App\Http\Controllers\DiscoveryController::class, 'update'])->middleware('throttle:30,1');
    Route::get('/posts/{post}', [PostController::class, 'show']);
    Route::delete('/posts/{post}', [PostController::class, 'destroy']);
    Route::post('/posts/{post}/poll/vote', [\App\Http\Controllers\PollController::class, 'vote'])->middleware('throttle:60,1');
    Route::delete('/posts/{post}/poll/vote', [\App\Http\Controllers\PollController::class, 'remove'])->middleware('throttle:60,1');
    Route::get('/saved', [\App\Http\Controllers\BookmarkController::class, 'index']);
    Route::post('/posts/{post}/save', [\App\Http\Controllers\BookmarkController::class, 'save']);
    Route::delete('/posts/{post}/save', [\App\Http\Controllers\BookmarkController::class, 'unsave']);
    Route::post('/posts/{post}/like', [EngagementController::class, 'like']);
    Route::delete('/posts/{post}/like', [EngagementController::class, 'unlike']);
    Route::get('/posts/{post}/comments', [EngagementController::class, 'comments']);
    Route::post('/posts/{post}/comments', [EngagementController::class, 'comment'])->middleware('throttle:30,1');
    Route::post('/users/{username}/follow', [EngagementController::class, 'follow']);
    Route::delete('/users/{username}/follow', [EngagementController::class, 'unfollow']);

    $s = \App\Http\Controllers\SocialController::class;
    Route::get('/users/search', [$s, 'search']);
    Route::get('/users/blocked', [$s, 'blocks']);
    Route::get('/users/{username}/{direction}', [\App\Http\Controllers\FollowListController::class, 'index'])->where('direction', 'followers|following');
    Route::get('/users/{username}', [$s, 'profile']);
    Route::post('/users/{username}/block', [$s, 'block']);
    Route::delete('/users/{username}/block', [$s, 'unblock']);
    Route::get('/notifications', [$s, 'notifications']);
    Route::post('/reports', [$s, 'report'])->middleware('throttle:20,1');
    Route::delete('/comments/{commentId}', [$s, 'deleteComment']);

    $x = \App\Http\Controllers\ExtrasController::class;
    Route::post('/posts/{post}/reaction', [$x, 'react']);
    Route::delete('/posts/{post}/reaction', [$x, 'unreact']);
    Route::get('/stories/{id}/media', [\App\Http\Controllers\MediaController::class, 'story'])->whereUuid('id');
    Route::get('/stories', [$x, 'stories']);
    Route::post('/stories', [$x, 'storeStory'])->middleware('throttle:20,1');
    Route::post('/stories/{id}/reply', [\App\Http\Controllers\StoryReplyController::class, 'reply'])->whereUuid('id')->middleware('throttle:30,1');
    Route::post('/stories/{id}/view', [$x, 'viewStory']);
    Route::get('/stories/{id}/viewers', [$x, 'storyViewers']);
    Route::delete('/stories/{id}', [$x, 'destroyStory']);
    Route::patch('/conversations/{id}/settings', [$x, 'settings']);
    Route::post('/conversations/{id}/typing', [$x, 'typing'])->middleware('throttle:120,1');
    Route::get('/calls/incoming', [$x, 'incoming']);
    Route::get('/calls', [$x, 'history']);
    Route::get('/calls/{id}', [$x, 'callState']);
    Route::post('/calls/{id}/action', [$x, 'callStatus']);

    Route::get('/conversations', [ChatController::class, 'index']);
    Route::post('/conversations', [ChatController::class, 'store']);
    Route::get('/conversations/{conversation}/messages', [ChatController::class, 'messages']);
    Route::post('/conversations/{conversation}/messages', [ChatController::class, 'send'])->middleware('throttle:120,1');
    Route::post('/conversations/{conversation}/read', [ChatController::class, 'read']);
    Route::get('/conversations/{conversation}/messages/{message}/media', [\App\Http\Controllers\MediaController::class, 'chat'])->whereUuid('message');
    Route::post('/conversations/{conversation}/members', [ChatController::class, 'addMembers'])->middleware('throttle:30,1');
    Route::post('/conversations/{conversation}/leave', [ChatController::class, 'leave']);
    Route::patch('/conversations/{conversation}', [ChatController::class, 'rename'])->middleware('throttle:30,1');

    Route::post('/conversations/{conversation}/call-token', [ChatController::class, 'callToken'])->middleware('throttle:30,1');
    Route::get('/notifications/summary', [ChatController::class, 'summary']);
    Route::get('/gifts', [\App\Http\Controllers\WalletController::class, 'gifts']);
    Route::post('/posts/{postId}/gifts', [\App\Http\Controllers\WalletController::class, 'sendGift'])->middleware('throttle:60,1');
    Route::get('/rooms', [\App\Http\Controllers\RoomController::class, 'index']);
    Route::post('/rooms', [\App\Http\Controllers\RoomController::class, 'store'])->middleware('throttle:10,1');
    Route::post('/rooms/{id}/join', [\App\Http\Controllers\RoomController::class, 'joinRoom'])->middleware('throttle:60,1');
    Route::post('/rooms/{id}/end', [\App\Http\Controllers\RoomController::class, 'end']);
    Route::post('/rooms/{id}/speaker', [\App\Http\Controllers\RoomController::class, 'speaker'])->middleware('throttle:60,1');
    Route::post('/rooms/{id}/gifts', [\App\Http\Controllers\RoomController::class, 'gift'])->middleware('throttle:60,1');
    Route::post('/devices', [\App\Http\Controllers\WalletController::class, 'registerDevice'])->middleware('throttle:30,1');
    Route::post('/devices/remove', [\App\Http\Controllers\WalletController::class, 'unregisterDevice'])->middleware('throttle:30,1');
    Route::get('/wallet', [\App\Http\Controllers\WalletController::class, 'show']);
    Route::get('/wallet/entries', [\App\Http\Controllers\WalletController::class, 'entriesList']);
    Route::post('/wallet/transfer', [\App\Http\Controllers\WalletController::class, 'transfer'])->middleware('throttle:30,1');
    Route::post('/wallet/topups', [\App\Http\Controllers\WalletController::class, 'startTopup'])->middleware('throttle:10,1');
    Route::get('/wallet/topups/{id}', [\App\Http\Controllers\WalletController::class, 'topupStatus']);
    Route::get('/wallet/withdrawals', [\App\Http\Controllers\WalletController::class, 'withdrawals']);
    Route::post('/wallet/withdrawals', [\App\Http\Controllers\WalletController::class, 'requestWithdrawal'])->middleware('throttle:10,1');
    Route::post('/wallet/withdrawals/{id}/cancel', [\App\Http\Controllers\WalletController::class, 'cancelWithdrawal'])->middleware('throttle:10,1');
});
