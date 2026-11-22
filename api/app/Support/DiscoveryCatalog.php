<?php

namespace App\Support;

use App\Models\Post;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/** Local candidate, not an activated recommendation or moderation service.
 * Every eligibility row must be explicitly supplied by future authorized owner
 * and review workflows. No row, pending review and absent consent all deny.
 */
class DiscoveryCatalog
{
    public const VERSION = 'eligible-recent-v1';
    public const PAGE_SIZE = 15;

    public function page(User $viewer, ?string $kind = null, ?string $cursor = null): array
    {
        abort_unless($kind === null || $kind === 'reel', 422);
        $before = $cursor === null ? null : $this->decode($cursor, $viewer->id, $kind);
        $q = Post::query()->join('discovery_eligibility as eligibility', 'eligibility.post_id', '=', 'posts.id')
            ->select('posts.*')->where('eligibility.author_opted_in', true)
            ->where('eligibility.public_post', true)->where('eligibility.moderation', 'approved')
            ->whereNotExists(fn ($unsafe) => $unsafe->selectRaw('1')->from('post_media as attachment')
                ->join('media_blobs as sensitive', fn ($j) => $j->on(DB::raw('cast(sensitive.public_id as text)'), '=', 'attachment.path')->orOn(DB::raw('cast(sensitive.public_id as text)'), '=', 'attachment.thumbnail_path'))
                ->whereColumn('attachment.post_id', 'posts.id')
                ->where(fn ($s) => $s->where('sensitive.is_private', true)
                    ->orWhereExists(fn ($story) => $story->selectRaw('1')->from('stories')->whereColumn('stories.media_id', 'sensitive.public_id')->where('stories.protected_media', true))
                    ->orWhereExists(fn ($msg) => $msg->selectRaw('1')->from('messages')->whereColumn('messages.media_id', 'sensitive.public_id'))))
            // Unknown secondary attachments must not hide behind one safe
            // preview. Every linked source/poster needs known public metadata.
            ->whereNotExists(fn ($unknown) => $unknown->selectRaw('1')->from('post_media as secondary')
                ->leftJoin('media_blobs as source', DB::raw('cast(source.public_id as text)'), '=', 'secondary.path')
                ->leftJoin('media_blobs as poster', DB::raw('cast(poster.public_id as text)'), '=', 'secondary.thumbnail_path')
                ->whereColumn('secondary.post_id', 'posts.id')
                ->where(fn ($bad) => $bad->whereNull('source.public_id')->orWhere('source.size', '<=', 0)
                    ->orWhereNotIn('secondary.type', ['image', 'video'])
                    ->orWhere(fn ($i) => $i->where('secondary.type', 'image')->where('source.mime', 'not like', 'image/%'))
                    ->orWhere(fn ($v) => $v->where('secondary.type', 'video')->where('source.mime', 'not like', 'video/%'))
                    ->orWhere(fn ($p) => $p->whereNotNull('secondary.thumbnail_path')->where(fn ($x) => $x
                        ->whereNull('poster.public_id')->orWhere('poster.size', '<=', 0)->orWhere('poster.mime', 'not like', 'image/%')))))
            ->whereIn('posts.kind', ['post', 'reel'])
            ->whereNotExists(fn ($b) => $b->selectRaw('1')->from('blocks')->where(fn ($w) => $w
                ->where(fn ($d) => $d->whereColumn('blocks.blocker_id', 'posts.user_id')->where('blocks.blocked_id', $viewer->id))
                ->orWhere(fn ($d) => $d->where('blocks.blocker_id', $viewer->id)->whereColumn('blocks.blocked_id', 'posts.user_id'))));
        // First select at most one bounded page of eligible posts. Preview
        // ranking happens only inside that page, not over the whole catalog.
        // EXISTS and the final preview read share one SQL statement/snapshot.
        $preview = $this->previewQuery(DB::table('post_media as preview'))
            ->whereColumn('preview.post_id', 'posts.id')->selectRaw('1');
        $q->whereExists($preview);
        if ($kind !== null) $q->where('posts.kind', $kind);
        if ($before !== null) $q->where('posts.id', '<', $before);
        $page = DB::query()->fromSub($q->orderByDesc('posts.id')->limit(self::PAGE_SIZE + 1), 'posts');
        $page = $this->previewQuery($page->join('post_media as preview', 'preview.post_id', '=', 'posts.id'));
        $page->select('posts.*', 'preview.type as preview_type', 'preview.path as preview_path', 'preview.thumbnail_path as preview_thumbnail')
            ->selectRaw('row_number() over (partition by posts.id order by preview.id) as preview_rank');
        $posts = DB::query()->fromSub($page, 'eligible')->where('preview_rank', 1)->orderByDesc('id')->limit(self::PAGE_SIZE + 1)->get();
        $more = $posts->count() > self::PAGE_SIZE;
        $posts = $posts->take(self::PAGE_SIZE);
        return [
            'contract' => 'discovery_v1', 'version' => self::VERSION,
            'data' => $posts->map(function ($post) {
                $image = $post->preview_type === 'image';
                return [
                    'public_id' => $post->public_id, 'kind' => $post->kind, 'body' => $post->body,
                    'media' => [[
                        'type' => $post->preview_type,
                        // Reel tiles need only a poster. Never expose source video in a grid response.
                        ...($image ? ['url' => url('/api/v1/media/'.$post->preview_path)] : ['thumbnail_url' => url('/api/v1/media/'.$post->preview_thumbnail)]),
                    ]],
                    'discovery' => ['author_opted_in' => true, 'moderation' => 'approved', 'public_post' => true,
                        'private_bytes' => false, 'blocked_either_way' => false, 'deleted' => false],
                ];
            })->filter()->values()->all(),
            'next_cursor' => $more ? $this->encode((int) $posts->last()->id, $viewer->id, $kind) : null,
        ];
    }

    /** Preview bytes must be public-classified and not used by a protected source.
     * The authoritative public media route still rechecks byte visibility.
     */
    private function previewQuery($q)
    {
        return $q->join('media_blobs as blob', function ($j) {
            $j->on(DB::raw('cast(blob.public_id as text)'), '=', DB::raw("case when preview.type = 'image' then preview.path else preview.thumbnail_path end"));
        })->join('media_blobs as original', DB::raw('cast(original.public_id as text)'), '=', 'preview.path')
            ->where('original.is_private', false)->where('original.size', '>', 0)
            ->where(fn ($m) => $m->where(fn ($i) => $i->where('preview.type', 'image')->where('original.mime', 'like', 'image/%'))
                ->orWhere(fn ($v) => $v->where('preview.type', 'video')->where('original.mime', 'like', 'video/%')))
            ->whereNotExists(fn ($s) => $s->selectRaw('1')->from('stories')
                ->whereColumn('stories.media_id', 'original.public_id')->where('stories.protected_media', true))
            ->whereNotExists(fn ($m) => $m->selectRaw('1')->from('messages')->whereColumn('messages.media_id', 'original.public_id'))
            ->whereIn('preview.type', ['image', 'video'])->where('blob.is_private', false)
            ->where('blob.mime', 'like', 'image/%')->where('blob.size', '>', 0)
            ->whereNotExists(fn ($s) => $s->selectRaw('1')->from('stories')
                ->whereColumn('stories.media_id', 'blob.public_id')->where('stories.protected_media', true))
            ->whereNotExists(fn ($m) => $m->selectRaw('1')->from('messages')->whereColumn('messages.media_id', 'blob.public_id'));
    }

    private function key(): string
    {
        $key = (string) config('app.key');
        abort_if(strlen($key) < 16, 503, 'Discovery cursor signing is unavailable.');
        return $key;
    }
    private function encode(int $id, int $viewer, ?string $kind): string
    {
        $payload = rtrim(strtr(base64_encode(json_encode(['id' => $id, 'viewer' => $viewer, 'kind' => $kind, 'version' => self::VERSION], JSON_THROW_ON_ERROR)), '+/', '-_'), '=');
        return $payload.'.'.hash_hmac('sha256', $payload, $this->key());
    }
    private function decode(string $cursor, int $viewer, ?string $kind): int
    {
        abort_if(strlen($cursor) > 2048, 422);
        $parts = explode('.', $cursor);
        abort_unless(count($parts) === 2 && hash_equals(hash_hmac('sha256', $parts[0], $this->key()), $parts[1]), 422);
        $decoded = base64_decode(strtr($parts[0], '-_', '+/'), true);
        $data = $decoded === false ? null : json_decode($decoded, true);
        abort_unless(is_array($data) && ($data['viewer'] ?? null) === $viewer &&
            array_key_exists('kind', $data) && $data['kind'] === $kind &&
            ($data['version'] ?? null) === self::VERSION && is_int($data['id'] ?? null) && $data['id'] > 0, 422);
        return $data['id'];
    }
}
