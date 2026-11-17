<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class StoryAudienceController extends Controller
{
    public function index(Request $r)
    {
        $page = DB::table('story_relationships')->where('owner_id', $r->user()->id)->orderBy('member_id')->cursorPaginate(40);
        $users = User::whereIn('id', collect($page->items())->pluck('member_id'))->get()->keyBy('id');

        return response()->json(['data' => collect($page->items())->map(fn ($row) => ['user' => Present::user($users[$row->member_id]), 'revision' => (int) $row->revision, 'close_friend' => (bool) $row->close_friend, 'hide_story' => (bool) $row->hide_story]), 'next_cursor' => $page->nextCursor()?->encode()])->header('Cache-Control', 'private, no-store');
    }

    public function show(Request $r, string $username)
    {
        $member = User::where('username', $username)->firstOrFail();
        abort_if($member->id === $r->user()->id, 422, 'Your own stories are always visible to you.');
        $row = DB::table('story_relationships')->where(['owner_id' => $r->user()->id, 'member_id' => $member->id])->first();

        return response()->json(['member' => ['user' => Present::user($member), 'revision' => (int) ($row?->revision ?? 0), 'close_friend' => (bool) ($row?->close_friend ?? false), 'hide_story' => (bool) ($row?->hide_story ?? false)]])->header('Cache-Control', 'private, no-store');
    }

    public function update(Request $r, string $username)
    {
        $data = $r->validate(['revision' => ['required', 'integer', 'min:0'], 'close_friend' => ['required', 'boolean'], 'hide_story' => ['required', 'boolean']]);
        $member = User::where('username', $username)->firstOrFail();
        $owner = $r->user()->id;
        abort_if($member->id === $owner, 422, 'Your own stories are always visible to you.');
        $next = DB::transaction(function () use ($owner, $member, $data) {
            DB::table('users')->where('id', $owner)->lockForUpdate()->first();
            $current = DB::table('story_relationships')->where(['owner_id' => $owner, 'member_id' => $member->id])->first();
            abort_unless((int) $data['revision'] === (int) ($current?->revision ?? 0), 409, 'Story audience changed. Reload before saving.');
            $next = $data;
            $next['revision'] = (int) ($current?->revision ?? 0) + 1;
            // Keep tombstone revisions so a removed entry cannot accept an old save.
            DB::table('story_relationships')->updateOrInsert(['owner_id' => $owner, 'member_id' => $member->id], $next + ['updated_at' => now(), 'created_at' => now()]);

            return $next;
        });

        return response()->json(['member' => ['user' => Present::user($member), 'revision' => $next['revision'], 'close_friend' => (bool) $next['close_friend'], 'hide_story' => (bool) $next['hide_story']]])->header('Cache-Control','private, no-store');
    }
}
