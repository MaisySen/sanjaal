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

        $hidden = \Illuminate\Support\Facades\DB::table('blocks')->where('blocker_id', $viewer->id)->pluck('blocked_id')
            ->merge(\Illuminate\Support\Facades\DB::table('blocks')->where('blocked_id', $viewer->id)->pluck('blocker_id'));
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

                return collect($page->items())->map(fn ($p) => Present::post($p, $viewer))->values();
            })(),
            'next_cursor' => $page->nextCursor()?->encode(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['nullable', 'in:post,reel'],
            'body' => ['nullable', 'string', 'max:2000'],
            'media' => ['nullable', 'array', 'max:4'],
            'media.*' => ['file', 'mimes:jpg,jpeg,png,webp,mp4,mov', 'max:25600'],
        ]);
        $kind = $data['kind'] ?? 'post';
        $files = $request->file('media', []);

        if (blank($data['body'] ?? null) && ! $files) {
            return response()->json(['message' => 'A post needs text or media.', 'errors' => ['body' => ['A post needs text or media.']]], 422);
        }
        if ($kind === 'reel') {
            $videos = collect($files)->filter(fn ($f) => str_starts_with($f->getMimeType(), 'video/'));
            if ($videos->count() !== 1 || count($files) !== 1) {
                return response()->json(['message' => 'A reel needs exactly one video.', 'errors' => ['media' => ['A reel needs exactly one video.']]], 422);
            }
        }

        $post = DB::transaction(function () use ($request, $data, $kind, $files) {
            $post = Post::create(['user_id' => $request->user()->id, 'kind' => $kind, 'body' => $data['body'] ?? null]);
            foreach ($files as $file) {
                $mime = $file->getMimeType();
                $blob = (string) \Illuminate\Support\Str::uuid();
                \App\Support\MediaStore::putFile($blob, $file);
                $path = $blob;
                $post->media()->create([
                    'type' => str_starts_with($mime, 'video/') ? 'video' : 'image',
                    'path' => $path, 'mime' => $mime, 'size' => $file->getSize(),
                ]);
            }
            $this->syncHashtags($post);

            return $post;
        });

        return response()->json(['post' => Present::post($post->load(self::WITH), $request->user())], 201);
    }

    public function show(Request $request, string $publicId): JsonResponse
    {
        $post = Post::with(self::WITH)->where('public_id', $publicId)->firstOrFail();

        return response()->json(['post' => Present::post($post, $request->user())]);
    }

    public function destroy(Request $request, string $publicId): JsonResponse
    {
        $post = Post::where('public_id', $publicId)->firstOrFail();
        abort_unless($post->user_id === $request->user()->id, 403, 'You can only delete your own posts.');
        \App\Support\MediaStore::delete($post->media()->pluck('path'));
        $post->delete();

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
