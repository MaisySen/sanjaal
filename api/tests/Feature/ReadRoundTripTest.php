<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReadRoundTripTest extends TestCase
{
    use RefreshDatabase;

    public function test_public_media_reads_authorization_and_metadata_together_without_weakening_denials(): void
    {
        [$u, $h] = $this->member('roundtrip');
        $post = $this->post('/api/v1/posts', ['media' => [UploadedFile::fake()->image('p.jpg', 10, 10)]], $h)->assertCreated()->json('post');
        $id = basename($post['media'][0]['url']);
        DB::enableQueryLog();
        DB::flushQueryLog();
        $this->get('/api/v1/media/'.$id)->assertOk();
        $queries = DB::getQueryLog();
        $this->assertCount(2, $queries);
        $this->assertStringNotContainsString('"data"', $queries[0]['query']);
        DB::flushQueryLog();
        $this->get('/api/v1/media/'.$id, ['If-None-Match' => '"'.$id.'"'])->assertStatus(304);
        $this->assertCount(1, DB::getQueryLog());
        DB::table('media_blobs')->where('public_id', $id)->update(['is_private' => true]);
        $this->get('/api/v1/media/'.$id)->assertNotFound();
        DB::table('media_blobs')->where('public_id', $id)->update(['is_private' => false]);
        // A conflicting protected-story reference must win over a public post reference.
        DB::table('stories')->insert(['public_id' => (string) Str::uuid(), 'user_id' => $u->id, 'media_id' => $id, 'media_mime' => 'image/jpeg', 'protected_media' => true, 'audience' => 'only_me', 'expires_at' => now()->addDay(), 'created_at' => now(), 'updated_at' => now()]);
        $this->get('/api/v1/media/'.$id, ['If-None-Match' => '"'.$id.'"'])->assertNotFound();
        DB::disableQueryLog();
    }

    public function test_populated_feed_uses_three_reads_with_live_viewer_state(): void
    {
        [$a, $ha] = $this->member('feedowner');
        [$b, $hb] = $this->member('feedviewer');
        $post = $this->postJson('/api/v1/posts', ['body' => 'Feed fixture #roundtrip'], $ha)->assertCreated()->json('post');
        $id = \App\Models\Post::where('public_id', $post['public_id'])->value('id');
        DB::table('bookmarks')->insert(['user_id' => $b->id, 'post_id' => $id, 'created_at' => now()]);
        $b->following()->attach($a->id);
        DB::table('likes')->insert([
            ['post_id' => $id, 'user_id' => $b->id, 'reaction' => 'love', 'created_at' => now(), 'updated_at' => now()],
            ['post_id' => $id, 'user_id' => $a->id, 'reaction' => 'like', 'created_at' => now(), 'updated_at' => now()],
        ]);
        $this->getJson('/api/v1/posts', $hb)->assertOk();
        DB::enableQueryLog(); DB::flushQueryLog();
        $this->getJson('/api/v1/posts', $hb)->assertOk()
            ->assertJsonPath('data.0.saved', true)->assertJsonPath('data.0.author.following', true)
            ->assertJsonPath('data.0.can_comment', true)->assertJsonPath('data.0.can_share_to_chat', true)
            ->assertJsonPath('data.0.my_reaction', 'love')->assertJsonPath('data.0.liked', true)
            ->assertJsonPath('data.0.reactions.love', 1)->assertJsonPath('data.0.reactions.like', 1)
            ->assertJsonPath('data.0.author.username', $a->username)->assertJsonPath('data.0.author.public_id', $a->public_id);
        $reads = array_filter(DB::getQueryLog(), fn ($q) => str_starts_with(strtolower($q['query']), 'select') && !str_contains($q['query'], 'personal_access_tokens') && !str_contains($q['query'], '"auth0_sub"'));
        $this->assertCount(3, $reads, json_encode(array_values($reads)));
        DB::disableQueryLog();
        DB::table('member_controls')->insert(['user_id' => $a->id, 'comments_from' => 'following', 'share_to_chat' => false, 'created_at' => now(), 'updated_at' => now()]);
        $this->getJson('/api/v1/posts', $hb)->assertJsonPath('data.0.can_comment', false)->assertJsonPath('data.0.can_share_to_chat', false);
        $a->following()->attach($b->id);
        $this->getJson('/api/v1/posts', $hb)->assertJsonPath('data.0.can_comment', true);
        $this->getJson('/api/v1/posts', $ha)->assertJsonPath('data.0.can_comment', true)->assertJsonPath('data.0.can_share_to_chat', true);
        foreach ([[$a->id, $b->id], [$b->id, $a->id]] as [$blocker, $blocked]) {
            DB::table('blocks')->insert(['blocker_id' => $blocker, 'blocked_id' => $blocked, 'created_at' => now()]);
            $this->getJson('/api/v1/posts', $hb)->assertJsonCount(0, 'data');
            DB::table('blocks')->delete();
        }
    }

    public function test_story_list_uses_three_reads_and_honors_both_block_directions(): void
    {
        [$a, $ha] = $this->member('owner');
        [$b, $hb] = $this->member('viewer');
        $b->following()->attach($a->id);
        $this->post('/api/v1/stories', ['media' => UploadedFile::fake()->image('s.jpg', 10, 10), 'audience' => 'followers'], $ha)->assertCreated();
        // Warm authentication before measuring controller reads.
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(1, 'data');
        DB::enableQueryLog();
        DB::flushQueryLog();
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(1, 'data');
        $reads = array_filter(DB::getQueryLog(), fn ($q) => str_starts_with(strtolower($q['query']), 'select') && !str_contains($q['query'], 'personal_access_tokens'));
        // Session authentication may read the current user, separate from the three controller reads.
        $controllerReads = array_filter($reads, fn ($q) => !str_contains($q['query'], '"auth0_sub"'));
        $this->assertCount(3, $controllerReads, json_encode(array_values($controllerReads)));
        foreach ([[$a->id, $b->id], [$b->id, $a->id]] as [$blocker, $blocked]) {
            DB::table('blocks')->insert(['blocker_id' => $blocker, 'blocked_id' => $blocked, 'created_at' => now()]);
            $this->getJson('/api/v1/stories', $hb)->assertJsonCount(0, 'data');
            DB::table('blocks')->delete();
        }
        DB::disableQueryLog();
    }
}
