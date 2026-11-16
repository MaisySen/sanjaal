<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Hashtag;
use App\Models\Post;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class PostController extends Controller
{
    private const WITH = ['user', 'media', 'hashtags'];

    /** Feed: ?kind=post|reel, ?scope=following, ?hashtag=tag, ?username=name, ?cursor=... */
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'kind' => ['nullable', 'in:post,reel'],
            'scope' => ['nullable', 'in:following,all'],
            'hashtag' => ['nullable', 'string', 'max:60'],
            'username' => ['nullable', 'string', 'max:30'],
        ]);
        $viewer = $request->user();
        $q = Post::with(self::WITH)->orderByDesc('id');

        $hidden = \Illuminate\Support\Facades\DB::table('blocks')
            ->where(fn ($b) => $b->where('blocker_id', $viewer->id)->orWhere('blocked_id', $viewer->id))
            ->get(['blocker_id', 'blocked_id'])
            ->flatMap(fn ($r) => [$r->blocker_id, $r->blocked_id])
            ->reject(fn ($id) => $id === $viewer->id)->unique()->values();
        if ($hidden->isNotEmpty()) {
            $q->whereNotIn('user_id', $hidden);
        }
        if ($request->filled('kind')) {
            $q->where('kind', $request->kind);
        }
        if ($request->scope === 'following') {
            $q->where(fn ($w) => $w->whereIn('user_id', $viewer->following()->select('users.id'))->orWhere('user_id', $viewer->id));
        }
        if ($request->filled('hashtag')) {
            $tag = Str::lower(ltrim($request->hashtag, '#'));
            $q->whereHas('hashtags', fn ($h) => $h->where('tag', $tag));
        }
        if ($request->filled('username')) {
            $q->whereHas('user', fn ($u) => $u->where('username', $request->username));
        }

        $page = $q->cursorPaginate(15)->withQueryString();

        return response()->json([
            'data' => (function () use ($page, $viewer) {
                Present::preload($page->items(), $viewer);

                $items = collect($page->items());
                $followed = $viewer->following()->whereIn('users.id', $items->pluck('user_id')->unique()->all())->pluck('users.id')->all();

                return $items->map(function ($p) use ($viewer, $followed) {
                    $a = Present::post($p, $viewer);
                    $a['author']['following'] = in_array($p->user_id, $followed, true);

                    return $a;
                })->values();
            })(),
            'next_cursor' => $page->nextCursor()?->encode(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'upload_intent' => \App\Support\UploadIntent::RULE,
            'kind' => ['nullable', 'in:post,reel'],
            'body' => ['nullable', 'string', 'max:2000'],
            'media' => ['nullable', 'array', 'max:4'],
            'media.*' => ['file', 'mimes:jpg,jpeg,png,webp,mp4,mov', 'max:25600'],
            'poll_options' => ['nullable', 'array', 'min:2', 'max:4'],
            'poll_options.*' => ['required', 'string', 'max:80'],
        ]);
        $kind = $data['kind'] ?? 'post';
        $files = $request->file('media', []);
        $options = isset($data['poll_options']) ? array_values(array_map('trim', $data['poll_options'])) : null;
        if ($options !== null) {
            $normalized = array_map(fn ($v) => Str::lower($v), $options);
            if ($kind !== 'post' || $files || blank($data['body'] ?? null) || in_array('', $options, true) || count(array_unique($normalized)) !== count($options)) {
                return response()->json(['message' => 'A poll needs a question and 2 to 4 different options, without media.'], 422);
            }
        }

        if (blank($data['body'] ?? null) && ! $files) {
            return response()->json(['message' => 'A post needs text or media.', 'errors' => ['body' => ['A post needs text or media.']]], 422);
        }
        if ($kind === 'reel') {
            $videos = collect($files)->filter(fn ($f) => str_starts_with($f->getMimeType(), 'video/'));
            if ($videos->count() !== 1 || count($files) !== 1) {
                return response()->json(['message' => 'A reel needs exactly one video.', 'errors' => ['media' => ['A reel needs exactly one video.']]], 422);
            }
        }

        $body = trim($data['body'] ?? '');
        $fingerprint = \App\Support\UploadIntent::fingerprint([$kind, $body, $options], $files);
        return \App\Support\UploadIntent::run($request, 'post', $fingerprint,
            function (bool $keyed) use ($request, $body, $kind, $files, $options) {
                $post = Post::create(['user_id' => $request->user()->id, 'kind' => $kind, 'body' => $body === '' ? null : $body, 'poll_options' => $options]);
                foreach ($files as $file) {
                    $mime = $file->getMimeType();
                    $blob = (string) Str::uuid();
                    // Keyed bytes commit atomically with the receipt. Public migration can
                    // move positively referenced objects later; no remote orphan on rollback.
                    \App\Support\MediaStore::putFile($blob, $file, $keyed);
                    $post->media()->create(['type' => str_starts_with($mime, 'video/') ? 'video' : 'image', 'path' => $blob, 'mime' => $mime, 'size' => $file->getSize()]);
                }
                $this->syncHashtags($post);
                return $post->public_id;
            }, function (string $id) use ($request) {
                $post = Post::with(self::WITH)->where('public_id', $id)->where('user_id', $request->user()->id)->first();
                return $post ? Present::post($post, $request->user()) : null;
            });
    }

    public function show(Request $request, string $publicId): JsonResponse
    {
        $post = Post::with(self::WITH)->where('public_id', $publicId)->firstOrFail();

        abort_if(in_array($post->user_id, Present::hiddenAuthors([$request->user()->id]), true), 404);

        return response()->json(['post' => Present::post($post, $request->user())]);
    }

    public function destroy(Request $request, string $publicId): JsonResponse
    {
        $paths = DB::transaction(function () use ($publicId, $request) {
            $post = Post::where('public_id', $publicId)->lockForUpdate()->firstOrFail();
            abort_unless($post->user_id === $request->user()->id, 403, 'You can only delete your own posts.');
            $paths = $post->media()->pluck('path');
            DB::table('poll_votes')->where('post_id', $post->id)->delete();
            $post->delete();

            return $paths;
        });
        \App\Support\MediaStore::delete($paths);

        return response()->json(['message' => 'Deleted.']);
    }

    private function syncHashtags(Post $post): void
    {
        preg_match_all('/#([\p{L}\p{N}_]{2,50})/u', (string) $post->body, $m);
        $ids = collect($m[1])->map(fn ($t) => Str::lower($t))->unique()->take(10)
            ->map(fn ($t) => Hashtag::firstOrCreate(['tag' => $t])->id);
        $post->hashtags()->sync($ids);
    }
}
