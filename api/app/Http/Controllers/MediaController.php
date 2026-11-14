<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/** Serves post media stored in the database, with HTTP Range support for video seeking. */
class MediaController extends Controller
{
    public function show(Request $request, string $publicId): Response
    {
        $row = DB::table('media_blobs')->where('public_id', $publicId)->first();
        abort_unless($row, 404);

        $bytes = base64_decode($row->data, true);
        $size = strlen($bytes);
        $headers = [
            'Content-Type' => $row->mime,
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

            return response(substr($bytes, $start, $end - $start + 1), 206, $headers + [
                'Content-Range' => "bytes $start-$end/$size",
            ]);
        }

        return response($bytes, 200, $headers);
    }
}
