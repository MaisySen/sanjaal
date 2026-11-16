<?php

namespace App\Http\Controllers;

use App\Support\MemberControls;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class MemberControlsController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json(['controls' => MemberControls::get($request->user()->id)])->header('Cache-Control', 'private, no-store');
    }
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'revision' => ['required', 'integer', 'min:0'],
            'comments_from' => ['sometimes', 'required', Rule::in(['everyone', 'following', 'nobody'])],
            'share_to_chat' => ['sometimes', 'required', 'boolean'],
        ]);
        abort_if(count($data) < 2, 422, 'Choose a setting to change.');
        $owner = $request->user()->id;
        $controls = DB::transaction(function () use ($owner, $data) {
            // Lock an always-existing owner row, including the first settings save.
            DB::table('users')->where('id', $owner)->lockForUpdate()->first();
            $current = MemberControls::get($owner);
            abort_unless((int) $data['revision'] === $current['revision'], 409, 'Settings changed elsewhere. Reload them before saving.');
            $next = array_merge($current, $data, ['revision' => $current['revision'] + 1]);
            DB::table('member_controls')->updateOrInsert(['user_id' => $owner], $next + ['updated_at' => now(), 'created_at' => now()]);
            return $next;
        });
        return response()->json(['controls' => $controls])->header('Cache-Control', 'private, no-store');
    }
}
