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
        // Keep viewer-specific state in the same database round trip as the feed.
        // These are live correlated checks, never cached access decisions.
        $uid = $viewer->id;
        // The author and the reaction counts ride in the same database round trip as the posts (live correlated
        // reads, never cached), so a feed page costs posts + media + hashtags instead of five sequential reads.
        $q = Post::with(['media', 'hashtags'])->select('posts.*')->orderByDesc('id')
            ->whereNotExists(fn ($b) => $b->selectRaw('1')->from('blocks')->where(fn ($w) => $w
                ->where(fn ($d) => $d->whereColumn('blocks.blocker_id', 'posts.user_id')->where('blocks.blocked_id', $uid))
                ->orWhere(fn ($d) => $d->where('blocks.blocker_id', $uid)->whereColumn('blocks.blocked_id', 'posts.user_id'))))
            ->selectRaw('exists(select 1 from bookmarks where bookmarks.post_id = posts.id and bookmarks.user_id = ?) as _saved', [$uid])
            ->selectRaw('exists(select 1 from follows where follows.follower_id = ? and follows.followee_id = posts.user_id) as _following', [$uid])
            ->selectRaw("(posts.user_id = ? or coalesce((select share_to_chat from member_controls where member_controls.user_id = posts.user_id), true)) as _can_share", [$uid])
            ->selectRaw("(posts.user_id = ? or coalesce((select comments_from from member_controls where member_controls.user_id = posts.user_id), 'everyone') = 'everyone' or ((select comments_from from member_controls where member_controls.user_id = posts.user_id) = 'following' and exists(select 1 from follows where follows.follower_id = posts.user_id and follows.followee_id = ?))) as _can_comment", [$uid, $uid]);
        foreach (['public_id', 'name', 'username', 'bio', 'avatar'] as $col) {
            $q->selectRaw("(select users.$col from users where users.id = posts.user_id) as _a_$col");
        }
        foreach (\App\Http\Controllers\ExtrasController::REACTIONS as $r) {
            $q->selectRaw("(select count(*) from likes where likes.post_id = posts.id and likes.reaction = ?) as _r_$r", [$r]);
        }
        $q->selectRaw('(select likes.reaction from likes where likes.post_id = posts.id and likes.user_id = ? limit 1) as _r_mine', [$uid]);
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
                foreach ($page->items() as $p) {
                    $author = (new User)->setRawAttributes([
                        'id' => $p->user_id, 'public_id' => $p->getAttribute('_a_public_id'), 'name' => $p->getAttribute('_a_name'),
                        'username' => $p->getAttribute('_a_username'), 'bio' => $p->getAttribute('_a_bio'), 'avatar' => $p->getAttribute('_a_avatar'),
                    ], true);
                    $author->exists = true;
                    $p->setRelation('user', $author);
                    $counts = collect();
                    foreach (\App\Http\Controllers\ExtrasController::REACTIONS as $r) {
                        if ((int) $p->getAttribute("_r_$r") > 0) {
                            $counts[$r] = (int) $p->getAttribute("_r_$r");
                        }
                    }
                    $p->setAttribute('_reactions', $counts);
                    $p->setAttribute('_mine', $p->getAttribute('_r_mine') ?? false);
                }
                Present::preload($page->items(), $viewer);

                $items = collect($page->items());
                return $items->map(function ($p) use ($viewer) {
                    $a = Present::post($p, $viewer);
                    $a['author']['following'] = (bool) $p->getAttribute('_following');

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
            'posters' => ['nullable', 'array', 'max:4'],
            'posters.*' => ['required', 'file', 'image', 'mimes:jpg,jpeg,png', 'max:256', 'dimensions:max_width=640,max_height=640'],
            'poll_options' => ['nullable', 'array', 'min:2', 'max:4'],
            'poll_options.*' => ['required', 'string', 'max:80'],
        ]);
        $kind = $data['kind'] ?? 'post';
        $files = $request->file('media', []);
        $posters = $request->file('posters', []);
        ksort($posters);
        foreach ($posters as $index => $poster) {
            abort_unless(is_int($index) && isset($files[$index]) && str_starts_with($files[$index]->getMimeType(), 'video/'), 422, 'A poster must belong to the video at the same media index.');
        }
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
        // Keep legacy fingerprints unchanged. Posters are frozen draft content,
        // including their media indices, and cannot change during safe replay.
        $fields = [$kind, $body, $options];
        if ($posters) $fields['poster_indices'] = array_keys($posters);
        $fingerprint = \App\Support\UploadIntent::fingerprint($fields, array_merge($files, array_values($posters)));
        return \App\Support\UploadIntent::run($request, 'post', $fingerprint,
            function (bool $keyed) use ($request, $body, $kind, $files, $options, $posters) {
                $post = Post::create(['user_id' => $request->user()->id, 'kind' => $kind, 'body' => $body === '' ? null : $body, 'poll_options' => $options]);
                foreach ($files as $index => $file) {
                    $mime = $file->getMimeType();
                    $blob = (string) Str::uuid();
                    // Keyed bytes commit atomically with the receipt. Public migration can
                    // move positively referenced objects later; no remote orphan on rollback.
                    \App\Support\MediaStore::putFile($blob, $file, forceDatabase: $keyed);
                    $posterPath = null;
                    if (isset($posters[$index])) {
                        // Decode only a validated <=640px/256KB image, strip all
                        // metadata, and commit its bytes with the video reference.
                        $image = imagecreatefromstring(file_get_contents($posters[$index]->getRealPath()));
                        abort_unless($image, 422, 'The video poster could not be read.');
                        try {
                            ob_start();
                            $encoded = imagejpeg($image, null, 80);
                            $jpeg = ob_get_contents();
                        } finally { ob_end_clean(); imagedestroy($image); }
                        abort_unless($encoded, 422, 'The video poster could not be encoded.');
                        abort_unless(is_string($jpeg) && strlen($jpeg) <= 256 * 1024, 422, 'The video poster is too large.');
                        $posterPath = (string) Str::uuid();
                        \App\Support\MediaStore::put($posterPath, 'image/jpeg', $jpeg, forceDatabase: true);
                    }
                    $post->media()->create(['thumbnail_path' => $posterPath, 'type' => str_starts_with($mime, 'video/') ? 'video' : 'image', 'path' => $blob, 'mime' => $mime, 'size' => $file->getSize()]);
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
            $paths = $post->media->flatMap(fn ($m) => [$m->path, $m->thumbnail_path])->filter();
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
