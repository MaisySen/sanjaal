<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/** Read-only candidate. No contact information or internal ids in responses. */
class FollowListController extends Controller
{
    public function index(Request $request, string $username, string $direction): JsonResponse
    {
        abort_unless(config('follow_lists.enabled') === true, 404);
        abort_unless(in_array($direction, ['followers', 'following'], true), 404);
        $viewer = $request->user();
        $owner = User::where('username', $username)->firstOrFail();
        $blocked = fn (int $id) => DB::table('blocks')->where('blocker_id', $id)->pluck('blocked_id')
            ->merge(DB::table('blocks')->where('blocked_id', $id)->pluck('blocker_id'))->unique()->all();
        $viewerBlocked = $blocked($viewer->id);
        abort_if(in_array($owner->id, $viewerBlocked, true), 404);
        $input = $request->validate(['cursor' => ['nullable', 'string', 'max:2048']]);
        $after = 0;
        if (!empty($input['cursor'])) {
            try {
                $cursor = json_decode(Crypt::decryptString($input['cursor']), true, 16, JSON_THROW_ON_ERROR);
                abort_unless(is_array($cursor) && ($cursor['viewer'] ?? null) === $viewer->public_id
                    && ($cursor['owner'] ?? null) === $owner->public_id && ($cursor['direction'] ?? null) === $direction
                    && is_int($cursor['after'] ?? null) && $cursor['after'] > 0, 422);
                $after = $cursor['after'];
            } catch (\Throwable $e) {
                abort(422, 'Invalid list cursor.');
            }
        }
        $ownerColumn = $direction === 'followers' ? 'followee_id' : 'follower_id';
        $memberColumn = $direction === 'followers' ? 'follower_id' : 'followee_id';
        $rows = DB::table('follows')->join('users', 'users.id', '=', "follows.$memberColumn")
            ->where("follows.$ownerColumn", $owner->id)->where('follows.id', '>', $after)
            ->whereNotIn('users.id', array_values(array_unique([...$viewerBlocked, ...$blocked($owner->id)])))
            ->orderBy('follows.id')->limit(31)->get(['follows.id as edge', 'users.*']);
        $more = $rows->count() > 30;
        $page = $rows->take(30);
        $next = $more ? Crypt::encryptString(json_encode([
            'viewer' => $viewer->public_id, 'owner' => $owner->public_id,
            'direction' => $direction, 'after' => (int) $page->last()->edge,
        ], JSON_THROW_ON_ERROR)) : null;

        return response()->json([
            'owner' => Present::user($owner), 'direction' => $direction,
            'data' => $page->map(fn ($row) => Present::user((new User)->newFromBuilder((array) $row)))->values(),
            'next_cursor' => $next,
        ]);
    }
}
