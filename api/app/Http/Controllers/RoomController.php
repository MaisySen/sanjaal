<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\LiveKit;
use App\Services\Wallet;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/** Live audio rooms. The host speaks, listeners join with a subscribe-only token and can send gifts. */
class RoomController extends Controller
{
    private const MAX_LIVE_PER_HOST = 1;

    public function index(): JsonResponse
    {
        $rows = DB::table('rooms')->join('users', 'users.id', '=', 'rooms.host_id')
            ->where('rooms.status', 'live')->orderByDesc('rooms.id')->limit(30)
            ->get(['rooms.public_id', 'rooms.title', 'rooms.created_at', 'users.username as host_username', 'users.name as host_name']);

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request): JsonResponse
    {
        if (! LiveKit::configured()) {
            return response()->json(['message' => 'Live rooms are not available yet.'], 503);
        }
        $data = $request->validate(['title' => ['required', 'string', 'min:2', 'max:80']]);
        $me = $request->user();
        if (DB::table('rooms')->where('host_id', $me->id)->where('status', 'live')->count() >= self::MAX_LIVE_PER_HOST) {
            return response()->json(['message' => 'You already have a live room. End it first.'], 422);
        }
        $id = (string) Str::uuid();
        DB::table('rooms')->insert(['public_id' => $id, 'host_id' => $me->id, 'title' => trim($data['title']), 'status' => 'live', 'created_at' => now(), 'updated_at' => now()]);

        return response()->json($this->join($me, $id, true) + ['room_id' => $id], 201);
    }

    public function joinRoom(Request $request, string $id): JsonResponse
    {
        if (! LiveKit::configured()) {
            return response()->json(['message' => 'Live rooms are not available yet.'], 503);
        }
        $room = DB::table('rooms')->where('public_id', $id)->first();
        if (! $room || $room->status !== 'live') {
            return response()->json(['message' => 'This room has ended.'], 410);
        }
        $me = $request->user();

        return response()->json($this->join($me, $id, $room->host_id === $me->id) + ['room_id' => $id, 'title' => $room->title, 'is_host' => $room->host_id === $me->id]);
    }

    public function end(Request $request, string $id): JsonResponse
    {
        $n = DB::table('rooms')->where('public_id', $id)->where('host_id', $request->user()->id)->where('status', 'live')
            ->update(['status' => 'ended', 'ended_at' => now(), 'updated_at' => now()]);

        return response()->json(['ended' => $n === 1], $n === 1 ? 200 : 404);
    }

    public function gift(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['gift' => ['required', 'string', 'max:16']]);
        $room = DB::table('rooms')->where('public_id', $id)->first();
        if (! $room || $room->status !== 'live') {
            return response()->json(['message' => 'This room has ended.'], 410);
        }
        $me = $request->user();
        $host = User::findOrFail($room->host_id);
        try {
            $gift = Wallet::gift($me, $host, $data['gift'], null, $room->id);
        } catch (InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['gift' => $gift, 'balance' => (int) $me->fresh()->coin_balance, 'from' => $me->username], 201);
    }

    private function join(User $me, string $id, bool $host): array
    {
        $name = $me->name ?: $me->username;

        return [
            'url' => config('services.livekit.url'),
            'room' => 'room-'.$id,
            'token' => LiveKit::token('u'.$me->id, $name, 'room-'.$id, 3600, $host),
        ];
    }
}
