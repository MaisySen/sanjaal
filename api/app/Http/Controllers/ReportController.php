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
            'submission_id' => ['sometimes', 'required', 'uuid'],
            'target_public_id' => ['sometimes', 'required', 'uuid'],
        ]);
        if (isset($data['target_public_id'])) {
            abort_unless($data['type'] === 'user', 422, 'Member reference requires a member report.');
            $data['target_public_id'] = strtolower($data['target_public_id']);
        }
        $submission = isset($data['submission_id']) ? strtolower($data['submission_id']) : null;
        // Normalize nullable note once so replay comparison does not depend on JSON key order.
        $fields = [$data['type'], $data['target'], $data['reason'], $data['note'] ?? null];
        // Keep legacy fingerprints byte-for-byte stable.
        if (isset($data['target_public_id'])) $fields[] = $data['target_public_id'];
        $fingerprint = hash('sha256', json_encode($fields, JSON_THROW_ON_ERROR));
        try {
            [$row, $replayed] = DB::transaction(function () use ($request, $data, $submission, $fingerprint) {
                if ($submission !== null || isset($data['target_public_id'])) {
                    if (DB::getDriverName() === 'pgsql') {
                        DB::statement("SET LOCAL lock_timeout = '2s'");
                        DB::statement("SET LOCAL statement_timeout = '5s'");
                    }
                }
                if ($submission !== null) {
                    // Serialize this reporter's keyed writes. The nullable unique constraint is
                    // the second guard; other reporters never contend for the same key.
                    DB::table('users')->where('id', $request->user()->id)->lockForUpdate()->firstOrFail();
                    $existing = DB::table('reports')->where('reporter_id', $request->user()->id)
                        ->where('submission_id', $submission)->first();
                    if ($existing) {
                        abort_unless(hash_equals((string) $existing->submission_fingerprint, $fingerprint), 409, 'This submission key belongs to a different report.');

                        return [$existing, true];
                    }
                }
                if (isset($data['target_public_id'])) {
                    $subject = DB::table('users')->where('public_id', $data['target_public_id'])->lockForUpdate()->first();
                    abort_unless($subject && $subject->username === $data['target'], 409, 'This profile changed. Refresh it before reporting.');
                }
                $record = [
                    'public_id' => (string) Str::uuid(),
                    'reporter_id' => $request->user()->id,
                    'target_type' => $data['type'], 'target_id' => $data['target'],
                    'reason' => $data['reason'], 'note' => $data['note'] ?? null,
                    'status' => 'received', 'created_at' => now(), 'updated_at' => now(),
                ];
                // Legacy requests remain compatible with the previous schema and writer.
                if ($submission !== null) {
                    $record += ['submission_id' => $submission, 'submission_fingerprint' => $fingerprint];
                }
                if (isset($data['target_public_id'])) $record['target_public_id'] = $data['target_public_id'];
                $id = DB::table('reports')->insertGetId($record);
                DB::table('report_events')->insert(['report_id' => $id, 'status' => 'received', 'created_at' => now()]);

                return [DB::table('reports')->find($id), false];
            });
        } catch (\Illuminate\Database\QueryException $error) {
            if (($submission !== null || isset($data['target_public_id'])) && in_array($error->getCode(), ['55P03', '57014', '40P01'], true)) {
                abort(503, 'Report result unconfirmed. Retry the same submission.');
            }
            throw $error;
        }

        return response()->json(['message' => 'Report received.', 'report' => $this->present($row), 'replayed' => $replayed], $replayed ? 200 : 201);
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
            'target_public_id' => $row->target_public_id ?? null,
            'reason' => $row->reason, 'note' => $row->note, 'status' => $row->status,
            'created_at' => $row->created_at === null ? null : Carbon::parse($row->created_at)->toISOString(),
            'updated_at' => $row->updated_at === null ? null : Carbon::parse($row->updated_at)->toISOString(),
        ];
    }
}
