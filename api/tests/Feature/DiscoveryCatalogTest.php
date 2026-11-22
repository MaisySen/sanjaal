<?php
namespace Tests\Feature;

use App\Models\Post;
use App\Support\DiscoveryCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

class DiscoveryCatalogTest extends TestCase
{
    use RefreshDatabase;
    protected function setUp(): void { parent::setUp(); config(['app.key' => 'local-fixture-cursor-key-not-a-secret']); }
    private function candidate($owner, array $facts = [], string $kind = 'post', bool $row = true): Post
    {
        $p = Post::create(['user_id' => $owner->id, 'body' => 'Local fixture', 'kind' => $kind]);
        $id = (string) Str::uuid();
        DB::table('media_blobs')->insert(['public_id' => $id, 'mime' => 'image/png', 'size' => 8, 'data' => base64_encode('fixture!'), 'storage' => 'db', 'is_private' => false, 'created_at' => now(), 'updated_at' => now()]);
        $p->media()->create(['type' => $kind === 'reel' ? 'video' : 'image', 'path' => $kind === 'reel' ? (string) Str::uuid() : $id, 'thumbnail_path' => $kind === 'reel' ? $id : null, 'mime' => $kind === 'reel' ? 'video/mp4' : 'image/png', 'size' => 8]);
        if ($kind === 'reel') {
            DB::table('media_blobs')->insert(['public_id' => $p->media()->first()->path, 'mime' => 'video/mp4', 'size' => 8, 'data' => base64_encode('fixture!'), 'storage' => 'db', 'is_private' => false, 'created_at' => now(), 'updated_at' => now()]);
        }
        if ($row) DB::table('discovery_eligibility')->insert(['post_id' => $p->id, 'author_opted_in' => true, 'public_post' => true, 'moderation' => 'approved', 'created_at' => now(), 'updated_at' => now(), ...$facts]);
        return $p;
    }
    public function test_no_row_or_missing_consent_or_review_never_backfills_eligibility(): void
    {
        [$u] = $this->member('owner');
        $this->candidate($u, row: false);
        foreach ([['author_opted_in' => false], ['public_post' => false], ['moderation' => 'pending'], ['moderation' => 'rejected'], ['moderation' => 'unknown']] as $facts) $this->candidate($u, $facts);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
        $this->assertDatabaseCount('discovery_eligibility', 5);
        $this->assertDatabaseCount('posts', 6);
        $this->assertDatabaseCount('post_media', 6);
    }
    public function test_exact_preview_only_output_and_real_reel_filter(): void
    {
        [$u] = $this->member('owner');
        $photo = $this->candidate($u); $reel = $this->candidate($u, kind: 'reel');
        $all = (new DiscoveryCatalog)->page($u);
        $this->assertSame('discovery_v1', $all['contract']);
        $this->assertSame([$reel->public_id, $photo->public_id], array_column($all['data'], 'public_id'));
        $this->assertArrayNotHasKey('url', $all['data'][0]['media'][0]);
        $this->assertArrayHasKey('thumbnail_url', $all['data'][0]['media'][0]);
        $this->assertSame([$reel->public_id], array_column((new DiscoveryCatalog)->page($u, 'reel')['data'], 'public_id'));
    }
    public function test_both_block_directions_and_soft_deletion_are_excluded_before_paging(): void
    {
        [$u] = $this->member('viewer'); [$a] = $this->member('author'); [$b] = $this->member('blocker');
        $this->candidate($a); $this->candidate($b); $deleted = $this->candidate($u); $deleted->delete();
        DB::table('blocks')->insert([['blocker_id' => $u->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()], ['blocker_id' => $b->id, 'blocked_id' => $u->id, 'created_at' => now(), 'updated_at' => now()]]);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_private_missing_nonimage_zero_byte_and_legacy_reel_previews_do_not_leak(): void
    {
        [$u] = $this->member('owner');
        foreach (['private', 'missing', 'mime', 'empty', 'legacy'] as $mode) {
            $p = $this->candidate($u, kind: $mode === 'legacy' ? 'reel' : 'post');
            $media = $p->media()->first();
            if ($mode === 'legacy') { $media->update(['thumbnail_path' => null]); continue; }
            $q = DB::table('media_blobs')->where('public_id', $media->path);
            if ($mode === 'missing') $q->delete();
            else $q->update(match ($mode) { 'private' => ['is_private' => true], 'mime' => ['mime' => 'video/mp4'], default => ['size' => 0] });
        }
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_conflicting_protected_story_reference_denies_even_when_blob_flag_is_wrong(): void
    {
        [$u] = $this->member('owner');
        foreach (['post', 'reel'] as $kind) {
            $p = $this->candidate($u, kind: $kind);
            DB::table('stories')->insert(['public_id' => (string) Str::uuid(), 'user_id' => $u->id, 'media_id' => $p->media()->first()->path, 'media_mime' => $kind === 'post' ? 'image/png' : 'video/mp4', 'protected_media' => true, 'audience' => 'only_me', 'expires_at' => now()->addHour(), 'created_at' => now(), 'updated_at' => now()]);
        }
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_private_original_video_is_not_discovered_through_a_public_poster(): void
    {
        [$u] = $this->member('owner'); $p = $this->candidate($u, kind: 'reel');
        DB::table('media_blobs')->where('public_id', $p->media()->first()->path)->update(['is_private' => true]);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_conflicting_chat_reference_and_a_private_second_attachment_exclude_whole_posts(): void
    {
        [$u] = $this->member('owner');
        $chatPost = $this->candidate($u); $privatePost = $this->candidate($u);
        $conversation = DB::table('conversations')->insertGetId(['public_id' => (string) Str::uuid(), 'type' => 'group', 'created_by' => $u->id, 'created_at' => now(), 'updated_at' => now()]);
        DB::table('messages')->insert(['public_id' => (string) Str::uuid(), 'conversation_id' => $conversation, 'user_id' => $u->id, 'body' => '', 'kind' => 'image', 'media_id' => $chatPost->media()->first()->path, 'created_at' => now(), 'updated_at' => now()]);
        $hidden = (string) Str::uuid();
        DB::table('media_blobs')->insert(['public_id' => $hidden, 'mime' => 'image/png', 'size' => 8, 'data' => base64_encode('private!'), 'storage' => 'db', 'is_private' => true, 'created_at' => now(), 'updated_at' => now()]);
        $privatePost->media()->create(['type' => 'image', 'path' => $hidden, 'mime' => 'image/png', 'size' => 8]);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
        foreach ([$chatPost->media()->first()->path, $hidden] as $media) {
            $path = '/api/v1/media/'.$media;
            $this->get($path)->assertNotFound();
            $this->get($path, ['Range' => 'bytes=0-3'])->assertNotFound();
            $this->get($path, ['If-None-Match' => '"'.$media.'"'])->assertNotFound();
        }
    }
    public function test_unknown_or_malformed_secondary_attachments_do_not_hide_behind_a_safe_preview(): void
    {
        [$u] = $this->member('owner');
        foreach (['missing', 'foreign', 'empty', 'mime', 'poster'] as $mode) {
            $p = $this->candidate($u); $id = (string) Str::uuid();
            if (in_array($mode, ['empty', 'mime', 'poster'], true)) DB::table('media_blobs')->insert(['public_id' => $id, 'mime' => $mode === 'mime' ? 'video/mp4' : 'image/png', 'size' => $mode === 'empty' ? 0 : 8, 'data' => base64_encode('fixture!'), 'storage' => 'db', 'is_private' => false, 'created_at' => now(), 'updated_at' => now()]);
            $p->media()->create(['type' => 'image', 'path' => $mode === 'foreign' ? 'https://fixture.invalid/private.jpg' : $id, 'thumbnail_path' => $mode === 'poster' ? (string) Str::uuid() : null, 'mime' => 'image/png', 'size' => 8]);
        }
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_opt_out_removes_recommendation_but_does_not_claim_to_revoke_public_post_bytes(): void
    {
        [$u] = $this->member('owner'); $p = $this->candidate($u); $path = '/api/v1/media/'.$p->media()->first()->path;
        $this->get($path)->assertOk();
        DB::table('discovery_eligibility')->where('post_id', $p->id)->update(['author_opted_in' => false]);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
        $this->get($path)->assertOk(); // Recommendation consent is not public-media revocation.
    }
    public function test_revoked_opt_in_and_moderation_disappear_on_next_read(): void
    {
        [$u] = $this->member('owner'); $p = $this->candidate($u); $catalog = new DiscoveryCatalog;
        $this->assertCount(1, $catalog->page($u)['data']);
        DB::table('discovery_eligibility')->where('post_id', $p->id)->update(['author_opted_in' => false]);
        $this->assertSame([], $catalog->page($u)['data']);
        DB::table('discovery_eligibility')->where('post_id', $p->id)->update(['author_opted_in' => true, 'moderation' => 'pending']);
        $this->assertSame([], $catalog->page($u)['data']);
    }
    public function test_multiple_media_never_duplicates_posts_and_cursor_is_bounded_to_viewer_filter_and_signature(): void
    {
        [$u] = $this->member('owner'); [$v] = $this->member('other');
        $ids = [];
        for ($i = 0; $i < 18; $i++) {
            $p = $this->candidate($u); $ids[] = $p->public_id;
            $m = $p->media()->first()->toArray(); unset($m['id'], $m['created_at'], $m['updated_at']); $p->media()->create($m);
        }
        $catalog = new DiscoveryCatalog; $first = $catalog->page($u);
        $this->assertCount(15, $first['data']); $this->assertNotNull($first['next_cursor']);
        $second = $catalog->page($u, null, $first['next_cursor']);
        $this->assertCount(3, $second['data']); $this->assertNull($second['next_cursor']);
        $this->assertSame(array_reverse($ids), array_column([...$first['data'], ...$second['data']], 'public_id'));
        foreach ([[$v, null, $first['next_cursor']], [$u, 'reel', $first['next_cursor']], [$u, null, $first['next_cursor'].'x']] as [$viewer, $kind, $cursor]) {
            try { $catalog->page($viewer, $kind, $cursor); $this->fail('Foreign cursor accepted'); }
            catch (HttpException $e) { $this->assertSame(422, $e->getStatusCode()); }
        }
    }
    public function test_newer_ineligible_rows_do_not_consume_the_page_or_hide_older_eligible_posts(): void
    {
        [$u] = $this->member('owner'); $expected=[];
        for($i=0;$i<18;$i++) $expected[]=$this->candidate($u)->public_id;
        for($i=0;$i<25;$i++) $this->candidate($u,['moderation'=>'pending']);
        $catalog=new DiscoveryCatalog;$first=$catalog->page($u);
        $this->assertCount(15,$first['data']);$this->assertNotNull($first['next_cursor']);
        $second=$catalog->page($u,null,$first['next_cursor']);$this->assertCount(3,$second['data']);$this->assertNull($second['next_cursor']);
        $this->assertSame(array_reverse($expected),array_column([...$first['data'],...$second['data']],'public_id'));
    }
    public function test_consent_update_preserves_existing_audience_review_and_creation_time(): void
    {
        [$u,$headers]=$this->member('owner');$post=$this->candidate($u);config(['discovery.enabled'=>true]);
        DB::table('discovery_eligibility')->where('post_id',$post->id)->update(['created_at'=>'2026-01-01 00:00:00']);
        $path='/api/v1/posts/'.$post->public_id.'/discovery';
        $this->putJson($path,['author_opted_in'=>false,'revision'=>0,'public_post'=>false],$headers)->assertUnprocessable();
        $this->putJson($path,['author_opted_in'=>false,'revision'=>0],$headers)->assertOk()->assertJsonPath('discovery.public_post',true)->assertJsonPath('discovery.moderation','approved');
        $this->assertDatabaseHas('discovery_eligibility',['post_id'=>$post->id,'created_at'=>'2026-01-01 00:00:00','revision'=>1]);
        $this->assertSame([],(new DiscoveryCatalog)->page($u)['data']);
    }
    public function test_service_capability_is_absent_in_effect_until_the_explicit_local_flag_is_enabled(): void
    {
        [$u,$headers]=$this->member('capfixture');
        $this->getJson('/api/v1/auth/me',$headers)->assertOk()->assertJsonPath('features.discovery_v1',false);
        config(['discovery.enabled'=>true]);
        $this->getJson('/api/v1/auth/me',$headers)->assertOk()->assertJsonPath('features.discovery_v1',true);
        config(['discovery.enabled'=>false]);
        $this->getJson('/api/v1/auth/me',$headers)->assertOk()->assertJsonPath('features.discovery_v1',false);
        $this->assertDatabaseCount('discovery_eligibility',0);
    }
    public function test_route_is_disabled_by_default_and_requires_real_authentication_when_locally_enabled(): void
    {
        [$u, $headers] = $this->member('owner'); $p = $this->candidate($u);
        $this->getJson('/api/v1/discovery', $headers)->assertNotFound();
        config(['discovery.enabled' => true]);
        $this->getJson('/api/v1/discovery')->assertUnauthorized();
        $this->getJson('/api/v1/discovery', $headers)->assertOk()->assertHeader('Cache-Control', 'no-store, private')
            ->assertJsonPath('contract', 'discovery_v1')->assertJsonPath('data.0.public_id', $p->public_id);
        $this->getJson('/api/v1/discovery?kind=unknown', $headers)->assertUnprocessable();
        $this->getJson('/api/v1/discovery?cursor=corrupt', $headers)->assertUnprocessable();
        config(['discovery.enabled' => false]);
        $this->getJson('/api/v1/discovery', $headers)->assertNotFound();
    }
    public function test_only_author_can_opt_in_and_consent_alone_never_approves_or_backfills_public_status(): void
    {
        [$u, $hu] = $this->member('owner'); [$v, $hv] = $this->member('other');
        $post = $this->candidate($u, row: false); $path = '/api/v1/posts/'.$post->public_id.'/discovery';
        $this->getJson($path, $hu)->assertNotFound(); config(['discovery.enabled' => true]);
        $this->getJson($path, $hv)->assertForbidden();
        $this->putJson($path, ['author_opted_in' => true, 'revision' => 0], $hv)->assertForbidden();
        $this->assertDatabaseCount('discovery_eligibility', 0);
        $this->getJson($path, $hu)->assertOk()->assertJsonPath('discovery.author_opted_in', false)->assertJsonPath('discovery.moderation', 'pending')->assertJsonPath('discovery.revision', 0);
        $this->putJson($path, ['author_opted_in' => true, 'revision' => 0, 'moderation' => 'approved'], $hu)->assertUnprocessable();
        $this->putJson($path, ['author_opted_in' => true, 'revision' => 0], $hu)->assertOk()->assertJsonPath('discovery.author_opted_in', true)->assertJsonPath('discovery.public_post', false)->assertJsonPath('discovery.moderation', 'pending')->assertJsonPath('discovery.revision', 1);
        $this->assertSame([], (new DiscoveryCatalog)->page($u)['data']);
        $this->putJson($path, ['author_opted_in' => false, 'revision' => 0], $hu)->assertConflict();
        $this->getJson($path, $hu)->assertJsonPath('discovery.author_opted_in', true)->assertJsonPath('discovery.revision', 1);
        $this->putJson($path, ['author_opted_in' => false, 'revision' => 1], $hu)->assertOk()->assertJsonPath('discovery.author_opted_in', false)->assertJsonPath('discovery.revision', 2);
        $post->delete();$this->getJson($path, $hu)->assertNotFound();
    }
    public function test_optional_local_contract_capture_comes_from_the_actual_http_response(): void
    {
        $destination = getenv('DISCOVERY_CONTRACT_CAPTURE');
        if (!$destination) { $this->markTestSkipped('Explicit isolated contract-capture path required.'); }
        [$u, $headers] = $this->member('contractowner'); $this->candidate($u); $this->candidate($u, kind: 'reel');
        config(['discovery.enabled' => true]);
        $response = $this->getJson('/api/v1/discovery', $headers)->assertOk()->assertJsonCount(2, 'data');
        file_put_contents($destination, $response->getContent());
    }
    public function test_optional_local_consent_contract_capture_uses_real_http_responses(): void
    {
        $destination=getenv('DISCOVERY_CONSENT_CAPTURE');
        if(!$destination) $this->markTestSkipped('Explicit isolated consent-capture path required.');
        [$u,$headers]=$this->member('consentfixture');$post=$this->candidate($u,row:false);config(['discovery.enabled'=>true]);
        $path='/api/v1/posts/'.$post->public_id.'/discovery';
        $initial=$this->getJson($path,$headers)->assertOk()->json();
        $save=$this->putJson($path,['author_opted_in'=>true,'revision'=>0],$headers)->assertOk()->json();
        $this->putJson($path,['author_opted_in'=>false,'revision'=>0],$headers)->assertConflict();
        $reload=$this->getJson($path,$headers)->assertOk()->json();
        $optout=$this->putJson($path,['author_opted_in'=>false,'revision'=>1],$headers)->assertOk()->json();
        file_put_contents($destination,json_encode(compact('initial','save','reload','optout'),JSON_THROW_ON_ERROR));
    }
    public function test_page_uses_one_metadata_query_without_blob_payloads_or_per_tile_reads(): void
    {
        [$u] = $this->member('owner'); for ($i = 0; $i < 16; $i++) $this->candidate($u);
        DB::enableQueryLog(); DB::flushQueryLog(); (new DiscoveryCatalog)->page($u); $queries = DB::getQueryLog(); DB::disableQueryLog();
        $this->assertCount(1, $queries);
        $this->assertStringNotContainsString('blob.data', $queries[0]['query']);
        $this->assertStringNotContainsString('media_blobs.*', $queries[0]['query']);
    }
}
