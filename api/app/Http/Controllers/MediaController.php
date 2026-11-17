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
    /** Public post media. Files that belong to a chat message are never served here. */
    public function show(Request $request, string $publicId): Response
    {
        // Keep authorization checks live, but perform them in one database round trip.
        // Metadata only: denied or conditional requests must not load the blob.
        $meta = DB::table('media_blobs')->select('public_id', 'mime', 'size', 'storage')
            ->where('public_id', $publicId)->where('is_private', false)
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('stories')
                ->whereColumn('stories.media_id', 'media_blobs.public_id')->where('protected_media', true))
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('messages')
                ->whereColumn('messages.media_id', 'media_blobs.public_id'))
            ->where(function ($q) {
                $q->whereExists(fn ($q) => $q->selectRaw('1')->from('post_media')->join('posts', 'posts.id', '=', 'post_media.post_id')
                    ->where(fn ($q) => $q->whereColumn('post_media.path', 'media_blobs.public_id')->orWhereColumn('post_media.thumbnail_path', 'media_blobs.public_id'))
                    ->whereNull('posts.deleted_at'))
                    ->orWhereExists(fn ($q) => $q->selectRaw('1')->from('users')->whereColumn('users.avatar', 'media_blobs.public_id'))
                    ->orWhereExists(fn ($q) => $q->selectRaw('1')->from('stories')->whereColumn('stories.media_id', 'media_blobs.public_id')->where('expires_at', '>', now()));
            })->first();
        abort_unless($meta, 404);

        return $this->serve($request, $publicId, false, $meta);
    }

    /** Protected story media never redirects to a bucket or enters a public cache. */
    public function story(Request $request,string $id):Response
    {
        $story=DB::table('stories')->where('public_id',$id)->where('protected_media',true)->where('expires_at','>',now())->first();
        abort_unless($story && \App\Support\StoryAudience::visible($story,$request->user()->id),404);
        return $this->serve($request,$story->media_id,true);
    }

    /** Chat media: only current members, and only for messages from after they joined. Sign-in required. */
    public function chat(Request $request, string $conversationId, string $messageId): Response
    {
        $convo = \App\Models\Conversation::where('public_id', $conversationId)->firstOrFail();
        $me = $request->user();
        $member = $convo->members()->where('users.id', $me->id)->first();
        abort_unless($member, 404);
        $msg = $convo->messages()->where('public_id', $messageId)->where('id', '>', (int) $member->pivot->history_from_id)->firstOrFail();
        abort_unless($msg->media_id, 404);

        return $this->serve($request, $msg->media_id, true);
    }

    private function serve(Request $request, string $publicId, bool $private, ?object $meta = null): Response
    {
        $meta ??= DB::table('media_blobs')->select('public_id', 'mime', 'size', 'storage')->where('public_id', $publicId)->first();
        abort_unless($meta, 404);

        if ($meta->storage === 'b2' && $private) {
            // Never expose any object-storage bearer link for private chat media. Fetch it here instead.
            $r = \Illuminate\Support\Facades\Http::timeout(30)->get(\App\Support\MediaStore::url($publicId));
            abort_unless($r->successful(), 404);

            return response($r->body(), 200, ['Content-Type' => $meta->mime, 'Cache-Control' => 'private, no-store']);
        }

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
            'Cache-Control' => $private ? 'private, no-store' : 'public, max-age=31536000, immutable',
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
