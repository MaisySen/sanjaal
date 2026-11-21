<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Sign-in itself happens at Auth0. This API only verifies the access token
 * (see App\Auth\Auth0Guard) and lets the member finish their local profile.
 */
class AuthController extends Controller
{
    public function me(Request $request): JsonResponse
    {
        return response()->json(['features' => ['discovery_v1' => config('discovery.enabled') === true, 'interaction_controls' => true, 'video_posters' => true, 'protected_stories' => true, 'story_replies' => true, 'group_member_refs' => true, 'polls' => true, 'upload_intents' => (bool) config('services.uploads.replay_safe')], 'user' => \App\Http\Resources\Present::user($request->user()) + ['phone' => $request->user()->phone, 'email' => $request->user()->email]]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:80'],
            'username' => ['sometimes', 'string', 'min:3', 'max:30', 'regex:/^[A-Za-z0-9_.]+$/', Rule::unique('users', 'username')->ignore($user->id)],
            'bio' => ['sometimes', 'nullable', 'string', 'max:160'],
            'phone' => ['sometimes', 'nullable', 'string', 'regex:/^\+[1-9][0-9]{7,14}$/', Rule::unique('users', 'phone')->ignore($user->id)],
        ]);
        $user->update($data);

        return response()->json(['user' => \App\Http\Resources\Present::user($user->fresh())]);
    }
}
