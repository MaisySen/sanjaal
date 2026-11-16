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

    public function index(Request $request): JsonResponse
    {
        $rows = DB::table('rooms')->join('users', 'users.id', '=', 'rooms.host_id')
            ->where('rooms.status', 'live')->whereNotIn('rooms.host_id', \App\Http\Resources\Present::hiddenAuthors([$request->user()->id]))->orderByDesc('rooms.id')->limit(30)
            ->get(['rooms.public_id', 'rooms.title', 'rooms.created_at', 'users.username as host_username', 'users.name as host_name']);
        $rows->transform(function ($r) {
            $r->host_name = User::safeName($r->host_name, $r->host_username);

            return $r;
        });

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
        abort_if($this->cannotContact($me, $room->host_id), 404);

        return response()->json($this->join($me, $id, $room->host_id === $me->id) + ['room_id' => $id, 'title' => $room->title, 'is_host' => $room->host_id === $me->id, 'host_name' => User::safeName(User::find($room->host_id)?->name, User::find($room->host_id)?->username), 'host_identity' => 'u'.$room->host_id]);
    }

    public function end(Request $request, string $id): JsonResponse
    {
        $n = DB::table('rooms')->where('public_id', $id)->where('host_id', $request->user()->id)->where('status', 'live')
            ->update(['status' => 'ended', 'ended_at' => now(), 'updated_at' => now()]);

        return response()->json(['ended' => $n === 1], $n === 1 ? 200 : 404);
    }

    /** Host lets a listener who raised a hand speak, or takes the mic back. */
    public function speaker(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['identity' => ['required', 'string', 'max:40', 'regex:/^u[0-9]+$/'], 'allow' => ['required', 'boolean']]);
        $room = DB::table('rooms')->where('public_id', $id)->where('host_id', $request->user()->id)->where('status', 'live')->first();
        if (! $room) {
            return response()->json(['message' => 'Only the host of a live room can do that.'], 404);
        }
        $ok = LiveKit::setCanPublish('room-'.$id, $data['identity'], (bool) $data['allow']);

        return response()->json(['ok' => $ok], $ok ? 200 : 502);
    }

    public function gift(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['gift' => ['required', 'string', 'max:16']]);
        $room = DB::table('rooms')->where('public_id', $id)->first();
        if (! $room || $room->status !== 'live') {
            return response()->json(['message' => 'This room has ended.'], 410);
        }
        $me = $request->user();
        abort_if($this->cannotContact($me, $room->host_id), 404);
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
        $name = $me->publicName();

        return [
            'url' => config('services.livekit.url'),
            'room' => 'room-'.$id,
            'identity' => 'u'.$me->id,
            'token' => LiveKit::token('u'.$me->id, $name, 'room-'.$id, 3600, $host),
        ];
    }
}
