<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],


    'livekit' => [
        'url' => env('LIVEKIT_URL'),
        'key' => env('LIVEKIT_API_KEY'),
        'secret' => env('LIVEKIT_API_SECRET'),
    ],

    'esewa' => [
        'env' => env('ESEWA_ENV', 'test'),
        'product_code' => env('ESEWA_PRODUCT_CODE'),
        'secret' => env('ESEWA_SECRET'),
    ],

    // Roll out only after receipt migration and DB-media capacity review.
    'uploads' => ['replay_safe' => env('UPLOAD_INTENTS_ENABLED', false)],

    'b2' => [
        'key_id' => env('B2_KEY_ID'),
        'key' => env('B2_APP_KEY'),
        'bucket' => env('B2_BUCKET'),
        'bucket_id' => env('B2_BUCKET_ID'),
    ],

    // Push sender (FCM HTTP v1). Credentials are a Google service account JSON, as a path or the JSON itself.
    // Unset means push is off and sending is a no-op.
    'fcm' => [
        'credentials' => env('FCM_CREDENTIALS'),
    ],

    'auth0' => [
        'domain' => env('AUTH0_DOMAIN'),
        'audience' => env('AUTH0_AUDIENCE'),
        'client_id' => env('AUTH0_CLIENT_ID'),
        'jwks' => null,
    ],

];
