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
        return response()->json(['user' => $request->user()]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:80'],
            'username' => ['sometimes', 'string', 'min:3', 'max:30', 'regex:/^[A-Za-z0-9_.]+$/', Rule::unique('users', 'username')->ignore($user->id)],
            'phone' => ['sometimes', 'nullable', 'string', 'regex:/^\+[1-9][0-9]{7,14}$/', Rule::unique('users', 'phone')->ignore($user->id)],
        ]);
        $user->update($data);

        return response()->json(['user' => $user->fresh()]);
    }
}
