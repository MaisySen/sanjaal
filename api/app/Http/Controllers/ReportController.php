<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ReportController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type' => ['required', 'in:post,user,comment'],
            'target' => ['required', 'string', 'max:40'],
            'reason' => ['required', 'in:spam,abuse,nudity,violence,scam,other'],
            'note' => ['nullable', 'string', 'max:300'],
        ]);
        $id = DB::transaction(function () use ($request, $data) {
            $id = DB::table('reports')->insertGetId([
                'public_id' => (string) Str::uuid(),
                'reporter_id' => $request->user()->id,
                'target_type' => $data['type'], 'target_id' => $data['target'],
                'reason' => $data['reason'], 'note' => $data['note'] ?? null,
                'status' => 'received', 'created_at' => now(), 'updated_at' => now(),
            ]);
            DB::table('report_events')->insert(['report_id' => $id, 'status' => 'received', 'created_at' => now()]);

            return $id;
        });

        return response()->json(['message' => 'Report received.', 'report' => $this->present(DB::table('reports')->find($id))], 201);
    }

    public function index(Request $request): JsonResponse
    {
        $input = $request->validate(['cursor' => ['nullable', 'uuid'], 'limit' => ['sometimes', 'integer', 'min:1', 'max:50']]);
        $limit = (int) ($input['limit'] ?? 20);
        $query = DB::table('reports')->where('reporter_id', $request->user()->id);
        if (isset($input['cursor'])) {
            $boundary = DB::table('reports')->where('reporter_id', $request->user()->id)->where('public_id', $input['cursor'])->first();
            abort_unless($boundary, 404);
            $query->where('id', '<', $boundary->id);
        }
        $rows = $query->orderByDesc('id')->limit($limit + 1)->get();
        $more = $rows->count() > $limit;
        $rows = $rows->take($limit)->values();

        return response()->json([
            'data' => $rows->map(fn ($row) => $this->present($row))->all(),
            'next_cursor' => $more ? $rows->last()->public_id : null,
        ]);
    }

    public function show(Request $request, string $receipt): JsonResponse
    {
        $row = DB::table('reports')->where('reporter_id', $request->user()->id)->where('public_id', $receipt)->first();
        abort_unless($row, 404);
        $events = DB::table('report_events')->where('report_id', $row->id)->orderBy('id')->get();

        return response()->json(['report' => $this->present($row), 'events' => $events->map(fn ($event) => [
            'status' => $event->status, 'created_at' => $event->created_at === null ? null : Carbon::parse($event->created_at)->toISOString(),
        ])->all()]);
    }

    private function present(object $row): array
    {
        return [
            'public_id' => $row->public_id, 'type' => $row->target_type, 'target' => $row->target_id,
            'reason' => $row->reason, 'note' => $row->note, 'status' => $row->status,
            'created_at' => $row->created_at === null ? null : Carbon::parse($row->created_at)->toISOString(),
            'updated_at' => $row->updated_at === null ? null : Carbon::parse($row->updated_at)->toISOString(),
        ];
    }
}
