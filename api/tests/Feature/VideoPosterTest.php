<?php
namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class VideoPosterTest extends TestCase
{
    use RefreshDatabase;
    private function video(): UploadedFile { return UploadedFile::fake()->create('clip.mp4', 2, 'video/mp4'); }
    private function poster(int $width = 320): UploadedFile { return UploadedFile::fake()->image('poster.png', $width, 160); }
    private function body(array $over = []): array { return array_merge(['kind'=>'reel', 'media'=>[$this->video()], 'posters'=>[$this->poster()]],$over); }
    public function test_poster_is_advertised_persisted_and_readable_then_deleted_with_video(): void
    {
        [, $h]=$this->member('asha');
        $this->getJson('/api/v1/auth/me',$h)->assertJsonPath('features.video_posters',true);
        $r=$this->post('/api/v1/posts',$this->body(),$h)->assertCreated();
        $url=$r->json('post.media.0.thumbnail_url');
        $this->assertNotNull($url);
        $this->get($url)->assertOk()->assertHeader('Content-Type','image/jpeg');
        $this->assertDatabaseCount('media_blobs',2);
        $this->deleteJson('/api/v1/posts/'.$r->json('post.public_id'),[],$h)->assertOk();
        $this->get($url)->assertNotFound(); $this->assertDatabaseCount('media_blobs',0);
    }
    public function test_legacy_video_needs_no_poster_and_does_not_invent_a_url(): void
    {
        [, $h]=$this->member('asha');
        $this->post('/api/v1/posts',$this->body(['posters'=>[]]),$h)->assertCreated()->assertJsonPath('post.media.0.thumbnail_url',null);
        $this->assertDatabaseCount('media_blobs',1);
    }
    public function test_image_or_missing_or_noninteger_index_and_oversize_poster_are_rejected_before_writing(): void
    {
        [, $h]=$this->member('asha');
        foreach ([$this->body(['posters'=>[3=>$this->poster()]]),$this->body(['posters'=>['wrong'=>$this->poster()]]),$this->body(['posters'=>[$this->poster(641)]]),$this->body(['kind'=>'post','media'=>[UploadedFile::fake()->image('photo.png')]]),$this->body(['posters'=>[UploadedFile::fake()->create('invalid.jpg',257,'image/jpeg')]])] as $body) {
            $this->post('/api/v1/posts',$body,$h)->assertUnprocessable();
        }
        $this->assertDatabaseCount('posts',0); $this->assertDatabaseCount('media_blobs',0);
    }
    public function test_poster_is_frozen_by_upload_intent_and_atomic_with_video(): void
    {
        config(['services.uploads.replay_safe'=>true,'services.b2.key_id'=>null,'services.b2.bucket'=>null]);
        [, $h]=$this->member('asha'); $body=$this->body(['upload_intent'=>'fixture-poster-intent-001']);
        $r=$this->post('/api/v1/posts',$body,$h)->assertCreated();
        $this->post('/api/v1/posts',$body,$h)->assertOk()->assertJsonPath('post.public_id',$r->json('post.public_id'));
        $this->post('/api/v1/posts',array_merge($body,['posters'=>[$this->poster(100)]]),$h)->assertStatus(409);
        $this->assertDatabaseCount('media_blobs',2); $this->assertDatabaseCount('posts',1);
        $this->assertSame(['db'],DB::table('media_blobs')->distinct()->pluck('storage')->all());
    }
    public function test_late_failure_rolls_back_both_video_and_poster_bytes(): void
    {
        config(['services.uploads.replay_safe'=>true]); [, $h]=$this->member('asha');
        \App\Models\PostMedia::creating(fn () => throw new \RuntimeException('fixture failure'));
        try { $this->post('/api/v1/posts',$this->body(['upload_intent'=>'fixture-poster-intent-002']),$h)->assertStatus(500); }
        finally { \App\Models\PostMedia::flushEventListeners(); }
        $this->assertDatabaseCount('posts',0); $this->assertDatabaseCount('media_blobs',0); $this->assertDatabaseCount('upload_receipts',0);
    }
    public function test_soft_deleted_post_cannot_publish_its_poster_even_if_blob_survives(): void
    {
        [, $h]=$this->member('asha');$r=$this->post('/api/v1/posts',$this->body(),$h)->assertCreated();
        DB::table('posts')->where('public_id',$r->json('post.public_id'))->update(['deleted_at'=>now()]);
        $this->get($r->json('post.media.0.thumbnail_url'))->assertNotFound();
    }
    public function test_poster_budget_failure_does_not_leave_a_video_or_receipt(): void
    {
        config(['services.uploads.replay_safe'=>true,'services.uploads.database_media_budget_bytes'=>100]);
        [, $h]=$this->member('asha');
        $this->post('/api/v1/posts',$this->body(['upload_intent'=>'fixture-poster-budget-001']),$h)->assertStatus(503);
        $this->assertDatabaseCount('posts',0); $this->assertDatabaseCount('media_blobs',0); $this->assertDatabaseCount('upload_receipts',0);
    }
    public function test_poster_migration_refuses_to_drop_populated_references(): void
    {
        [, $h]=$this->member('asha'); $this->post('/api/v1/posts',$this->body(),$h)->assertCreated();
        $migration=require database_path('migrations/2026_11_17_060000_add_post_video_posters.php');
        try { $migration->down(); $this->fail('Must not drop populated posters.'); }
        catch (\LogicException $e) { $this->assertStringContainsString('Preserve',$e->getMessage()); }
        $this->assertNotNull(DB::table('post_media')->value('thumbnail_path'));
    }

}
