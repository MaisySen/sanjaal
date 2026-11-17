<?php

namespace Tests\Feature;

use App\Support\MediaStore;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class ProtectedStoryTest extends TestCase
{
    use RefreshDatabase;

    private function story($h, string $audience = 'followers', ?string $intent = null)
    {
        return $this->post('/api/v1/stories', ['media' => UploadedFile::fake()->image('s.jpg', 40, 40), 'caption' => 'Protected fixture', 'protected_media' => '1', 'audience' => $audience, ...($intent ? ['upload_intent' => $intent] : [])], $h)->assertCreated()->json('story');
    }

    private function relation($h, string $name, bool $close, bool $hide, int $rev = 0)
    {
        return $this->putJson('/api/v1/auth/me/story-audience/'.$name, ['revision' => $rev, 'close_friend' => $close, 'hide_story' => $hide], $h);
    }

    public function test_protected_story_bytes_cannot_be_read_through_public_or_unrelated_media_paths(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('follower');
        [$c,$hc] = $this->member('outsider');
        config(['services.b2.key_id' => 'fixture', 'services.b2.bucket' => 'fixture']);
        Http::fake();
        $s = $this->story($ha);
        Http::assertNothingSent();
        $blob = DB::table('stories')->where('public_id', $s['public_id'])->value('media_id');
        $this->assertDatabaseHas('media_blobs', ['public_id' => $blob, 'storage' => 'db']);
        $this->get('/api/v1/media/'.$blob)->assertNotFound();
        $url = '/api/v1/stories/'.$s['public_id'].'/media';
        $this->getJson($url)->assertUnauthorized();
        $this->get($url, $hc)->assertNotFound();
        $this->get($url, $ha)->assertOk()->assertHeader('Cache-Control', 'no-store, private');
        $b->following()->attach($a->id);
        $this->get($url, $hb)->assertOk();
        $range = $this->get($url, $hb + ['Range' => 'bytes=0-9'])->assertStatus(206);
        $this->assertSame(10, strlen($range->getContent()));
        $this->getJson('/api/v1/stories', $hb)->assertJsonPath('data.0.items.0.protected_media', true)->assertJsonPath('data.0.items.0.audience', 'followers');
        $this->postJson('/api/v1/stories/'.$s['public_id'].'/view', [], $hb)->assertOk();
        $b->following()->detach($a->id);
        $this->get($url, $hb)->assertNotFound();
        $this->postJson('/api/v1/stories/'.$s['public_id'].'/view', [], $hb)->assertNotFound();
    }

    public function test_close_friends_hide_and_removal_are_enforced_in_list_view_and_media_without_leaking_roster(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('friend');
        [$c,$hc] = $this->member('other');
        $this->relation($ha, 'friend', true, false)->assertOk()->assertJsonPath('member.revision', 1);
        $this->getJson('/api/v1/auth/me/story-audience', $hb)->assertJsonCount(0, 'data');
        $s = $this->story($ha, 'close_friends');
        $id = $s['public_id'];
        $media = "/api/v1/stories/$id/media";
        $this->getJson('/api/v1/stories', $hb)->assertJsonPath('data.0.items.0.public_id', $id);
        $this->get($media, $hb)->assertOk();
        $this->get($media, $hc)->assertNotFound();
        $this->relation($ha, 'friend', true, true, 1)->assertOk();
        $this->get($media, $hb)->assertNotFound();
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/stories/$id/view", [], $hb)->assertNotFound();
        $this->get($media, $ha)->assertOk();
        $this->relation($ha, 'friend', false, false, 2)->assertOk();
        $this->get($media, $hb)->assertNotFound();
        $this->relation($ha, 'friend', true, false, 1)->assertConflict();
        $this->relation($ha, 'friend', true, false, 3)->assertOk();
        $this->postJson('/api/v1/users/friend/block', [], $ha)->assertOk();
        $this->get($media, $hb)->assertNotFound();
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(0, 'data');
    }

    public function test_only_me_expiry_and_deletion_close_every_new_byte_route(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('follower');
        $b->following()->attach($a->id);
        $s = $this->story($ha, 'only_me');
        $id = $s['public_id'];
        $this->get("/api/v1/stories/$id/media", $hb)->assertNotFound();
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(0, 'data');
        $this->get("/api/v1/stories/$id/media", $ha)->assertOk();
        DB::table('stories')->where('public_id', $id)->update(['expires_at' => now()->subSecond()]);
        $this->get("/api/v1/stories/$id/media", $ha)->assertNotFound();
        $next = $this->story($ha);
        $this->deleteJson('/api/v1/stories/'.$next['public_id'], [], $ha)->assertOk();
        $this->get('/api/v1/stories/'.$next['public_id'].'/media', $ha)->assertNotFound();
    }

    public function test_audience_input_and_roster_updates_are_owner_scoped_and_versioned(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('friend');
        $this->putJson('/api/v1/auth/me/story-audience/friend', ['revision' => 0, 'close_friend' => true, 'hide_story' => false])->assertUnauthorized();
        $this->relation($ha, 'owner', true, false)->assertUnprocessable();
        $this->relation($ha, 'missing', true, false)->assertNotFound();
        $this->putJson('/api/v1/auth/me/story-audience/friend', ['revision' => 0, 'close_friend' => 'yes', 'hide_story' => false], $ha)->assertUnprocessable();
        $this->relation($ha, 'friend', true, false)->assertOk();
        $this->relation($ha, 'friend', false, true, 0)->assertConflict();
        $this->getJson('/api/v1/auth/me/story-audience', $ha)->assertJsonPath('data.0.user.username', 'friend')->assertJsonPath('data.0.revision', 1);
        $this->getJson('/api/v1/auth/me', $ha)->assertJsonPath('features.protected_stories', true);
        foreach ([['protected_media' => '0', 'audience' => 'close_friends'], ['protected_media' => '1', 'audience' => 'anyone']] as $fields) {
            $this->post('/api/v1/stories', ['media' => UploadedFile::fake()->image('s.jpg', 20, 20), ...$fields], $ha)->assertUnprocessable();
        }
    }

    public function test_new_story_default_is_protected_and_audience_changes_cannot_replay_an_old_intent(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$a,$ha] = $this->member('owner');
        $file = UploadedFile::fake()->image('s.jpg', 40, 40);
        $body = ['media' => $file, 'upload_intent' => 'protected-story-intent-0001', 'caption' => 'Same'];
        $first = $this->post('/api/v1/stories', $body, $ha)->assertCreated()->assertJsonPath('story.protected_media', true)->assertJsonPath('story.audience', 'followers');
        $id = $first->json('story.public_id');
        $this->post('/api/v1/stories', $body + ['protected_media' => '1', 'audience' => 'followers'], $ha)->assertOk()->assertJsonPath('story.public_id', $id);
        $this->post('/api/v1/stories', $body + ['protected_media' => '1', 'audience' => 'close_friends'], $ha)->assertConflict()->assertJsonPath('resource_id', $id);
        $this->assertDatabaseCount('stories', 1);
        $this->assertDatabaseCount('media_blobs', 1);
        $this->post('/api/v1/stories', ['media' => $file, 'protected_media' => '0'], $ha)->assertUnprocessable();
        $blob = DB::table('stories')->where('public_id', $id)->value('media_id');
        $this->get('/api/v1/media/'.$blob)->assertNotFound();
    }

    public function test_revocation_happens_before_etag_and_range_and_roster_is_owner_only(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('follower');
        $b->following()->attach($a->id);
        $this->relation($ha, 'follower', true, false)->assertOk();
        $s = $this->story($ha);
        $url = '/api/v1/stories/'.$s['public_id'].'/media';
        $etag = $this->get($url, $hb)->assertOk()->headers->get('ETag');
        $this->relation($ha, 'follower', true, true, 1)->assertOk();
        $this->get($url, $hb + ['If-None-Match' => $etag])->assertNotFound();
        $this->get($url, $hb + ['Range' => 'bytes=0-10'])->assertNotFound();
        $this->getJson('/api/v1/auth/me/story-audience/follower', $ha)->assertJsonPath('member.hide_story', true)->assertJsonPath('member.revision', 2);
        $this->getJson('/api/v1/auth/me/story-audience/owner', $hb)->assertJsonPath('member.hide_story', false)->assertJsonPath('member.revision', 0);
        $this->getJson('/api/v1/stories', $hb)->assertHeader('Cache-Control', 'no-store, private')->assertJsonCount(0, 'data');
    }

    public function test_preexisting_public_stories_remain_explicitly_legacy_not_relabelled_private(): void
    {
        [$a,$ha] = $this->member('owner');
        [$b,$hb] = $this->member('follower');
        $b->following()->attach($a->id);
        $s = $this->story($ha);
        DB::table('stories')->where('public_id', $s['public_id'])->update(['protected_media' => false]);
        DB::table('media_blobs')->whereIn('public_id', DB::table('stories')->where('public_id', $s['public_id'])->select('media_id'))->update(['is_private' => false]);
        $blob = DB::table('stories')->where('public_id', $s['public_id'])->value('media_id');
        $this->relation($ha, 'follower', false, true)->assertOk();
        $this->get('/api/v1/media/'.$blob)->assertOk()->assertHeader('Cache-Control', 'immutable, max-age=31536000, public');
        $this->getJson('/api/v1/stories', $hb)->assertJsonPath('data.0.items.0.protected_media', false)->assertJsonPath('data.0.items.0.audience', 'legacy_public');
    }

    public function test_backfill_never_copies_protected_stories_to_a_shared_bucket_even_with_other_references(): void
    {
        [$owner, $h] = $this->member('owner');
        $story = $this->story($h);
        $blob = DB::table('stories')->where('public_id', $story['public_id'])->value('media_id');
        // A conflicting public reference must never downgrade the protected blob.
        $owner->update(['avatar' => $blob]);
        config(['services.b2.key_id' => 'fixture', 'services.b2.bucket' => 'fixture']);
        Http::fake();
        $this->artisan('media:move-to-b2')->assertSuccessful();
        Http::assertNothingSent();
        $this->assertDatabaseHas('media_blobs', ['public_id' => $blob, 'storage' => 'db']);
        $this->get('/api/v1/media/'.$blob)->assertNotFound();
        $this->get('/api/v1/stories/'.$story['public_id'].'/media', $h)->assertOk();
    }

    public function test_private_classification_survives_story_deletion_and_conflicting_public_reference(): void
    {
        [$owner,$h] = $this->member('owner');
        $s = $this->story($h);
        $blob = DB::table('stories')->where('public_id', $s['public_id'])->value('media_id');
        $this->assertDatabaseHas('media_blobs', ['public_id' => $blob, 'is_private' => true]);
        $this->deleteJson('/api/v1/stories/'.$s['public_id'], [], $h)->assertOk();
        $owner->update(['avatar' => $blob]);
        $this->get('/api/v1/media/'.$blob)->assertNotFound();
        config(['services.b2.key_id' => 'fixture', 'services.b2.bucket' => 'fixture']);
        Http::fake();
        $this->artisan('media:move-to-b2')->assertSuccessful();
        Http::assertNothingSent();
        $this->assertDatabaseHas('media_blobs', ['public_id' => $blob, 'storage' => 'db', 'is_private' => true]);
    }

    public function test_replay_safe_public_post_storage_is_not_misclassified_private(): void
    {
        config(['services.uploads.replay_safe' => true]);
        [$owner,$h] = $this->member('owner');
        $post = $this->post('/api/v1/posts', ['media' => [UploadedFile::fake()->image('p.jpg', 20, 20)], 'body' => 'Public fixture', 'upload_intent' => 'public-story-classification-0001'], $h)->assertCreated();
        $blob = DB::table('post_media')->value('path');
        $this->assertDatabaseHas('media_blobs', ['public_id' => $blob, 'storage' => 'db', 'is_private' => false]);
        $this->get('/api/v1/media/'.$blob)->assertOk();
    }

    public function test_classification_migration_backfills_existing_protected_stories_without_downgrading_public_files(): void
    {
        [$owner,$h] = $this->member('owner');
        $s = $this->story($h);
        $private = DB::table('stories')->where('public_id', $s['public_id'])->value('media_id');
        $public = (string) Str::uuid();
        MediaStore::put($public, 'image/png', 'public fixture');
        $migration = require database_path('migrations/2026_11_17_120000_durable_private_media_classification.php');
        $migration->down();
        $migration->up();
        $this->assertDatabaseHas('media_blobs', ['public_id' => $private, 'is_private' => true]);
        $this->assertDatabaseHas('media_blobs', ['public_id' => $public, 'is_private' => false]);
    }
}
