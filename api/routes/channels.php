<?php

use App\Models\Conversation;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('conversation.{publicId}', function ($user, string $publicId) {
    $c = Conversation::where('public_id', $publicId)->first();

    return $c && $c->hasMember($user);
}, ['guards' => ['auth0']]);
