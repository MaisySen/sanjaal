<?php

namespace Tests\Feature;

use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class PruneExpiredStoriesTest extends TestCase
{
    use RefreshDatabase;

    private function story(array $headers, string $intent): array
    {
        $body = ['upload_intent' => $intent, 'media' => UploadedFile::fake()->image('fixture.png', 20, 20)];
        $id = $this->post('/api/v1/stories', $body, $headers)->assertCreated()->json('story.public_id');

        return [$id, DB::table('stories')->where('public_id', $id)->first(), $body];
    }

    public function test_default_is_dry_run_then_apply_removes_only_expired_story_bytes_and_views_not_receipts(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$owner,$h] = $this->member('owner');
        [$id,$s,$body] = $this->story($h, 'prune-story-fixture-0001');
        $this->postJson('/api/v1/stories/'.$id.'/view', [], $h)->assertOk();
        DB::table('stories')->where('id', $s->id)->update(['expires_at' => now()->subSecond()]);
        $this->artisan('stories:prune-expired')->assertSuccessful();
        $this->assertDatabaseHas('stories', ['id' => $s->id]);
        $this->assertDatabaseHas('media_blobs', ['public_id' => $s->media_id]);
        Http::fake();
        $this->artisan('stories:prune-expired --apply')->assertSuccessful();
        Http::assertNothingSent();
        $this->assertDatabaseMissing('stories', ['id' => $s->id]);
        $this->assertDatabaseMissing('media_blobs', ['public_id' => $s->media_id]);
        $this->assertDatabaseCount('story_views', 0);
        $this->assertDatabaseCount('upload_receipts', 1);
        $this->post('/api/v1/stories', $body, $h)->assertStatus(410);
        $this->assertDatabaseCount('media_blobs', 0);
        $this->artisan('stories:prune-expired --apply')->assertSuccessful();
    }

    public function test_active_legacy_shared_and_unclassified_media_are_not_deleted(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$owner,$h] = $this->member('owner');
        [, $active] = $this->story($h, 'prune-story-fixture-0002');
        [, $legacy] = $this->story($h, 'prune-story-fixture-0003');
        [, $shared] = $this->story($h, 'prune-story-fixture-0004');
        [, $unknown] = $this->story($h, 'prune-story-fixture-0005');
        DB::table('stories')->whereIn('id', [$legacy->id, $shared->id, $unknown->id])->update(['expires_at' => now()->subDay()]);
        DB::table('stories')->where('id', $legacy->id)->update(['protected_media' => false]);
        DB::table('media_blobs')->where('public_id', $unknown->media_id)->update(['is_private' => false]);
        DB::table('users')->where('id', $owner->id)->update(['avatar' => $shared->media_id]);
        $this->assertDatabaseHas('users', ['id' => $owner->id, 'avatar' => $shared->media_id]);
        $this->artisan('stories:prune-expired --apply')->assertSuccessful();
        foreach ([$active, $legacy] as $s) {
            $this->assertDatabaseHas('stories', ['id' => $s->id]);
        }
        foreach ([$active, $legacy, $shared, $unknown] as $s) {
            $this->assertTrue(DB::table('media_blobs')->where('public_id', $s->media_id)->exists(), 'Missing media for story '.$s->id);
            $this->assertDatabaseHas('media_blobs', ['public_id' => $s->media_id]);
        }
        $this->assertDatabaseMissing('stories', ['id' => $shared->id]);
        $this->assertDatabaseMissing('stories', ['id' => $unknown->id]);
    }

    public function test_bounded_batches_keep_other_expired_stories_and_invalid_limit_changes_nothing(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$owner,$h] = $this->member('owner');
        [, $first] = $this->story($h, 'prune-story-fixture-0006');
        [, $second] = $this->story($h, 'prune-story-fixture-0007');
        DB::table('stories')->update(['expires_at' => now()->subDay()]);
        foreach (['0', '1001', 'wrong'] as $limit) {
            $this->artisan('stories:prune-expired', ['--apply' => true, '--limit' => $limit])->assertFailed();
        }
        $this->assertDatabaseCount('stories', 2);
        $this->artisan('stories:prune-expired --apply --limit=1')->assertSuccessful();
        $this->assertDatabaseMissing('stories', ['id' => $first->id]);
        $this->assertDatabaseHas('stories', ['id' => $second->id]);
        $this->assertDatabaseHas('media_blobs', ['public_id' => $second->media_id]);
    }

    public function test_other_story_and_post_references_preserve_private_bytes_and_remote_rows_are_untouched(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$owner,$h] = $this->member('owner');
        [, $shared] = $this->story($h, 'prune-story-fixture-0008');
        [, $postStory] = $this->story($h, 'prune-story-fixture-0009');
        [, $remote] = $this->story($h, 'prune-story-fixture-0010');
        $copy = (array) $shared;
        unset($copy['id']);
        $copy['public_id'] = (string) Str::uuid();
        $copy['expires_at'] = now()->addDay();
        DB::table('stories')->insert($copy);
        $post = Post::create(['user_id' => $owner->id, 'kind' => 'post', 'body' => 'Reference fixture']);
        $post->media()->create(['path' => $postStory->media_id, 'type' => 'image', 'mime' => 'image/png', 'size' => 10]);
        DB::table('stories')->whereIn('id', [$shared->id, $postStory->id, $remote->id])->update(['expires_at' => now()->subDay()]);
        DB::table('media_blobs')->where('public_id', $remote->media_id)->update(['storage' => 'b2', 'data' => '']);
        Http::fake();
        $this->artisan('stories:prune-expired --apply')->assertSuccessful();
        Http::assertNothingSent();
        foreach ([$shared, $postStory, $remote] as $story) {
            $this->assertDatabaseMissing('stories', ['id' => $story->id]);
            $this->assertDatabaseHas('media_blobs', ['public_id' => $story->media_id]);
        }
        $this->assertDatabaseHas('stories', ['public_id' => $copy['public_id']]);
    }
}
