<?php
namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UploadIntentTest extends TestCase
{
    use RefreshDatabase;
    protected function setUp(): void { parent::setUp(); config(['services.uploads.replay_safe' => true]); }
    private const KEY = 'fixture-upload-intent-0001';
    private function postBody(array $over = []): array { return array_merge(['body' => 'Hello #community', 'upload_intent' => self::KEY], $over); }
    private function image(string $name = 'a.png', int $width = 10): UploadedFile { return UploadedFile::fake()->image($name, $width, 10); }

    public function test_post_replay_conflict_scope_and_deleted_receipt(): void
    {
        [$a,$ha] = $this->member('asha'); [$b,$hb] = $this->member('bina');
        $this->getJson('/api/v1/auth/me',$ha)->assertJsonPath('features.upload_intents',true);
        $id = $this->postJson('/api/v1/posts',$this->postBody(),$ha)->assertCreated()->json('post.public_id');
        $this->postJson('/api/v1/posts',$this->postBody(),$ha)->assertOk()->assertJsonPath('post.public_id',$id)->assertJsonPath('replayed',true);
        $this->postJson('/api/v1/posts',$this->postBody(['body'=>'Changed']),$ha)->assertStatus(409)->assertJsonPath('code','upload_intent_conflict');
        $this->postJson('/api/v1/posts',$this->postBody(),$hb)->assertCreated();
        $this->assertDatabaseCount('posts',2); $this->assertDatabaseCount('upload_receipts',2);
        $this->deleteJson('/api/v1/posts/'.$id,[],$ha)->assertOk();
        $this->postJson('/api/v1/posts',$this->postBody(),$ha)->assertStatus(410);
        $this->assertDatabaseCount('posts',2); $this->assertDatabaseCount('upload_receipts',2);
    }
    public function test_media_replay_fingerprint_order_and_atomic_db_storage(): void
    {
        [$a,$h] = $this->member('asha');
        // Without B2 the keyed bytes stay in the database (the B2 path has its own tests).
        config(['services.b2.key_id'=>null, 'services.b2.bucket'=>null]);
        $one = $this->image(); $two = $this->image('b.png',20);
        $body = $this->postBody(['media'=>[$one,$two]]);
        $id = $this->post('/api/v1/posts',$body,$h)->assertCreated()->json('post.public_id');
        $this->post('/api/v1/posts',$body,$h)->assertOk()->assertJsonPath('post.public_id',$id);
        $this->post('/api/v1/posts',$this->postBody(['media'=>[$two,$one]]),$h)->assertStatus(409);
        $this->post('/api/v1/posts',$this->postBody(['media'=>[$this->image('new.png',30),$two]]),$h)->assertStatus(409);
        $this->assertDatabaseCount('posts',1); $this->assertDatabaseCount('post_media',2); $this->assertDatabaseCount('media_blobs',2);
        $this->assertSame(['db'],DB::table('media_blobs')->distinct()->pluck('storage')->all());
    }
    public function test_story_replay_caption_conflict_expiry_and_delete(): void
    {
        [$a,$h] = $this->member('asha'); $file = $this->image();
        $body = ['upload_intent'=>self::KEY,'media'=>$file,'caption'=>'Kept caption'];
        $id = $this->post('/api/v1/stories',$body,$h)->assertCreated()->json('story.public_id');
        $this->post('/api/v1/stories',$body,$h)->assertOk()->assertJsonPath('story.public_id',$id)->assertJsonPath('story.caption','Kept caption');
        $this->post('/api/v1/stories',array_merge($body,['caption'=>'Changed']),$h)->assertStatus(409);
        $this->assertDatabaseCount('stories',1); $this->assertDatabaseCount('media_blobs',1);
        DB::table('stories')->where('public_id',$id)->update(['expires_at'=>now()->subSecond()]);
        $this->post('/api/v1/stories',$body,$h)->assertStatus(410);
        DB::table('stories')->where('public_id',$id)->delete();
        $this->post('/api/v1/stories',$body,$h)->assertStatus(410);
        $this->assertDatabaseCount('stories',0); $this->assertDatabaseCount('upload_receipts',1);
    }
    public function test_poll_replay_does_not_reset_votes_and_changed_options_conflict(): void
    {
        [$a,$h] = $this->member('asha');
        $body=$this->postBody(['poll_options'=>['Saturday','Sunday']]);
        $id=$this->postJson('/api/v1/posts',$body,$h)->assertCreated()->json('post.public_id');
        $this->postJson('/api/v1/posts/'.$id.'/poll/vote',['choice'=>0],$h)->assertOk();
        $this->postJson('/api/v1/posts',$body,$h)->assertOk()->assertJsonPath('post.poll.total_votes',1);
        $this->postJson('/api/v1/posts',$this->postBody(['poll_options'=>['Monday','Tuesday']]),$h)->assertStatus(409);
    }
    public function test_validation_leaves_no_receipt_and_legacy_remains_compatible(): void
    {
        [$a,$h] = $this->member('asha');
        foreach (['short',str_repeat('x',81),'invalid spaces 00000000'] as $bad) $this->postJson('/api/v1/posts',$this->postBody(['upload_intent'=>$bad]),$h)->assertUnprocessable();
        $this->postJson('/api/v1/posts',$this->postBody(['body'=>'']),$h)->assertUnprocessable();
        $this->assertDatabaseCount('upload_receipts',0);
        $this->postJson('/api/v1/posts',$this->postBody(),$h)->assertCreated();
        $this->postJson('/api/v1/posts',['body'=>'Legacy'],$h)->assertCreated();
        $this->postJson('/api/v1/posts',['body'=>'Legacy'],$h)->assertCreated();
        $this->assertDatabaseCount('posts',3); $this->assertDatabaseCount('upload_receipts',1);
    }
    public function test_failure_after_blob_write_rolls_back_receipt_resource_and_bytes(): void
    {
        [$a,$h] = $this->member('asha');
        \App\Models\PostMedia::creating(function () { throw new \RuntimeException('fixture failure after blob'); });
        try {
            $this->post('/api/v1/posts',$this->postBody(['media'=>[$this->image()]]),$h)->assertStatus(500);
            $this->assertDatabaseCount('posts',0); $this->assertDatabaseCount('media_blobs',0); $this->assertDatabaseCount('upload_receipts',0);
        } finally { \App\Models\PostMedia::flushEventListeners(); }
        $this->post('/api/v1/posts',$this->postBody(['media'=>[$this->image()]]),$h)->assertCreated();
    }
    public function test_receipt_schema_can_rollback_before_use_but_refuses_tombstone_loss(): void
    {
        [$a,$h] = $this->member('asha');
        $migration = require database_path('migrations/2026_11_17_030000_create_upload_receipts.php');
        $migration->down(); $migration->up();
        $this->postJson('/api/v1/posts',$this->postBody(['body'=>'0']),$h)->assertCreated()->assertJsonPath('post.body','0');
        try { $migration->down(); $this->fail('A populated receipt ledger must never be silently dropped.'); }
        catch (\LogicException $e) { $this->assertStringContainsString('Preserve', $e->getMessage()); }
        $this->assertDatabaseCount('posts',1); $this->assertDatabaseCount('upload_receipts',1);
    }
    public function test_unauthenticated_and_invalid_story_requests_create_no_receipt_or_blob(): void
    {
        [$a,$h] = $this->member('asha');
        $this->post('/api/v1/stories',['upload_intent'=>self::KEY,'media'=>$this->image()],['Accept'=>'application/json'])->assertUnauthorized();
        $this->post('/api/v1/stories',['upload_intent'=>'invalid intent 000000','media'=>$this->image()],$h)->assertUnprocessable();
        $this->post('/api/v1/stories',['upload_intent'=>self::KEY],$h)->assertUnprocessable();
        $this->assertDatabaseCount('upload_receipts',0); $this->assertDatabaseCount('media_blobs',0);
        $this->post('/api/v1/stories',['upload_intent'=>self::KEY,'media'=>$this->image(),'caption'=>'0'],$h)->assertCreated()->assertJsonPath('story.caption','0');
    }

    public function test_disabled_rollout_does_not_advertise_or_silently_accept_keyed_uploads(): void
    {
        [$a,$h] = $this->member('asha');
        config(['services.uploads.replay_safe'=>false]);
        $this->getJson('/api/v1/auth/me',$h)->assertJsonPath('features.upload_intents',false);
        $this->postJson('/api/v1/posts',$this->postBody(),$h)->assertStatus(503)->assertJsonPath('code','upload_intents_unavailable');
        $this->post('/api/v1/stories',['upload_intent'=>self::KEY,'media'=>$this->image()],$h)->assertStatus(503);
        $this->assertDatabaseCount('posts',0); $this->assertDatabaseCount('stories',0); $this->assertDatabaseCount('media_blobs',0); $this->assertDatabaseCount('upload_receipts',0);
        $this->postJson('/api/v1/posts',['body'=>'Legacy compatible'],$h)->assertCreated();
    }

}
