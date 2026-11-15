<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * Serves post media stored in the database, with HTTP Range support for video seeking.
 *
 * Only the bytes a client asks for leave the database: the row metadata is read first
 * (no payload), a matching ETag answers 304 without touching the blob, and a Range
 * request pulls just the base64 slice that covers the range.
 */
class MediaController extends Controller
{
    public function show(Request $request, string $publicId): Response
    {
        $meta = DB::table('media_blobs')->select('public_id', 'mime', 'size', 'storage')->where('public_id', $publicId)->first();
        abort_unless($meta, 404);

        if ($meta->storage === 'b2') {
            // Bytes live in object storage: send the client straight there (Range works there too).
            return redirect()->away(\App\Support\MediaStore::url($publicId), 302, [
                'Cache-Control' => 'private, max-age=3600',
            ]);
        }

        $size = (int) $meta->size;
        $headers = [
            'Content-Type' => $meta->mime,
            'Accept-Ranges' => 'bytes',
            'Cache-Control' => 'public, max-age=31536000, immutable',
            'ETag' => '"'.$publicId.'"',
        ];

        if (($request->header('If-None-Match') ?? '') === $headers['ETag']) {
            return response('', 304, $headers);
        }

        if (preg_match('/^bytes=(\d*)-(\d*)$/', (string) $request->header('Range'), $m) && ($m[1] !== '' || $m[2] !== '')) {
            if ($m[1] === '') {
                $start = max(0, $size - (int) $m[2]);
                $end = $size - 1;
            } else {
                $start = (int) $m[1];
                $end = $m[2] === '' ? $size - 1 : min((int) $m[2], $size - 1);
            }
            if ($start > $end || $start >= $size) {
                return response('', 416, ['Content-Range' => "bytes */$size"]);
            }
            // Cap one response at 2 MB so a single request can never pull a whole video.
            $end = min($end, $start + 2 * 1024 * 1024 - 1);

            $chunkStart = intdiv($start, 3) * 4;
            $chunkLen = (intdiv($end, 3) + 1) * 4 - $chunkStart;
            $slice = DB::table('media_blobs')
                ->where('public_id', $publicId)
                ->selectRaw('substr(data, ?, ?) as part', [$chunkStart + 1, $chunkLen])
                ->value('part');
            $bytes = base64_decode((string) $slice, true);
            abort_if($bytes === false, 500);

            return response(substr($bytes, $start - intdiv($start, 3) * 3, $end - $start + 1), 206, $headers + [
                'Content-Range' => "bytes $start-$end/$size",
            ]);
        }

        $row = DB::table('media_blobs')->where('public_id', $publicId)->first();
        abort_unless($row, 404);

        return response(base64_decode($row->data, true), 200, $headers);
    }
}
