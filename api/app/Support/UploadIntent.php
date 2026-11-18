<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/** Durable replay receipts. No automatic expiry: content deletion must not reopen an intent. */
class UploadIntent
{
    public const RULE = ['nullable', 'string', 'min:16', 'max:80', 'regex:/\A[A-Za-z0-9_-]+\z/D'];

    public static function fingerprint(array $fields, array $files): string
    {
        return hash('sha256', json_encode([$fields, array_map(fn ($f) => [
            'mime' => $f->getMimeType(), 'size' => $f->getSize(),
            'sha256' => hash_file('sha256', $f->getRealPath()),
        ], $files)], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE));
    }

    /** $create returns the new public id. $present returns current resource or null if gone. */
    public static function run(Request $request, string $operation, string $fingerprint, callable $create, callable $present): JsonResponse
    {
        $id = $request->input('upload_intent');
        if ($id !== null && ! config('services.uploads.replay_safe')) {
            return response()->json(['message' => 'Safe upload retries are temporarily unavailable. Your draft is kept.', 'code' => 'upload_intents_unavailable'], 503);
        }
        MediaStore::beginAttempt();
        $closureDone = false;
        try {
            $response = DB::transaction(function () use ($request, $operation, $fingerprint, $create, $present, $id) {
            if ($id !== null) {
                // Serialize before any blob write. Unique receipt remains a final invariant.
                User::whereKey($request->user()->id)->lockForUpdate()->firstOrFail();
                $receipt = DB::table('upload_receipts')->where('user_id', $request->user()->id)->where('operation', $operation)->where('intent_id', $id)->first();
                if ($receipt) {
                    if (! hash_equals($receipt->fingerprint, $fingerprint)) {
                        return response()->json(['message' => 'This draft was already submitted with different content. Check the original before sharing again.', 'code' => 'upload_intent_conflict', 'resource_id' => $receipt->resource_id], 409);
                    }
                    $resource = $present($receipt->resource_id);
                    return $resource === null
                        ? response()->json(['message' => 'The original upload was removed or expired. It will not be shared again.', 'code' => 'upload_intent_gone'], 410)
                        : response()->json([$operation => $resource, 'replayed' => true]);
                }
            }
            $resourceId = $create($id !== null);
            if ($id !== null) {
                DB::table('upload_receipts')->insert([
                    'user_id' => $request->user()->id, 'operation' => $operation,
                    'intent_id' => $id, 'fingerprint' => $fingerprint, 'resource_id' => $resourceId,
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
            $closureDone = true;
            return response()->json([$operation => $present($resourceId)], 201);
            });
        } catch (\Throwable $e) {
            // Failure inside the closure rolls back, so nothing references the object. Failure after the closure
            // finished is the commit itself and may have succeeded: keep the object, never delete on ambiguity.
            $closureDone ? MediaStore::commitAttempt() : MediaStore::discardAttempt();
            throw $e;
        }
        MediaStore::commitAttempt();

        return $response;
    }
}
