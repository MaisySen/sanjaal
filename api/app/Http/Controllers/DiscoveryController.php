<?php

namespace App\Http\Controllers;

use App\Support\DiscoveryCatalog;
use App\Models\Post;
use Illuminate\Support\Facades\DB;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Local candidate route. Disabled by source configuration in normal execution. */
class DiscoveryController extends Controller
{
    private function owned(Request $request, Post $post): void
    {
        abort_unless(config('discovery.enabled') === true, 404);
        abort_unless($post->user_id === $request->user()->id, 403);
    }
    private function preference(Post $post): array
    {
        $row = DB::table('discovery_eligibility')->where('post_id', $post->id)->first();
        return ['author_opted_in' => (bool) ($row?->author_opted_in ?? false),
            'public_post' => (bool) ($row?->public_post ?? false),
            'moderation' => $row?->moderation ?? 'pending', 'revision' => (int) ($row?->revision ?? 0)];
    }
    public function show(Request $request, Post $post): JsonResponse
    {
        $this->owned($request, $post);
        return response()->json(['discovery' => $this->preference($post)])->header('Cache-Control', 'private, no-store');
    }
    public function update(Request $request, Post $post): JsonResponse
    {
        $this->owned($request, $post);
        abort_if(array_diff(array_keys($request->all()), ['author_opted_in', 'revision']), 422);
        $data = $request->validate(['author_opted_in' => ['required', 'boolean'], 'revision' => ['required', 'integer', 'min:0']]);
        return DB::transaction(function () use ($request, $post, $data) {
            // The always-existing post row serializes first saves as well as
            // updates. Future moderation writers must take this same lock.
            $current = Post::whereKey($post->id)->lockForUpdate()->firstOrFail();
            abort_unless($current->user_id === $request->user()->id, 403);
            $preference = $this->preference($current);
            abort_unless($preference['revision'] === (int) $data['revision'], 409, 'Discovery settings changed. Reload before saving.');
            $createdAt = DB::table('discovery_eligibility')->where('post_id', $current->id)->value('created_at');
            DB::table('discovery_eligibility')->updateOrInsert(['post_id' => $current->id], [
                'author_opted_in' => (bool) $data['author_opted_in'],
                // This consent endpoint never manufactures a public-audience
                // verification or moderation approval.
                'public_post' => $preference['public_post'], 'moderation' => $preference['moderation'],
                'revision' => $preference['revision'] + 1, 'created_at' => $createdAt ?? now(), 'updated_at' => now(),
            ]);
            return response()->json(['discovery' => $this->preference($current)])->header('Cache-Control', 'private, no-store');
        });
    }
    public function index(Request $request, DiscoveryCatalog $catalog): JsonResponse
    {
        abort_unless(config('discovery.enabled') === true, 404);
        $data = $request->validate(['kind' => ['nullable', 'in:reel'], 'cursor' => ['nullable', 'string', 'max:2048']]);
        return response()->json($catalog->page($request->user(), $data['kind'] ?? null, $data['cursor'] ?? null))
            ->header('Cache-Control', 'private, no-store');
    }
}
