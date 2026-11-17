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
