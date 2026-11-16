<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Message;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class MessageRetryTest extends TestCase
{
    use RefreshDatabase;

    public function test_retry_uses_original_message_reply_and_does_not_repeat_side_effects(): void
    {
        [$a,$ha] = $this->member('asha');
        [$b,$hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/conversations', ['type'=>'direct','username'=>'bina'], $ha)->json('conversation.public_id');
        $root = $this->postJson("/api/v1/conversations/$id/messages", ['body'=>'Question','client_id'=>'root'], $hb)->json('message.public_id');
        $body = ['body'=>'Original reply','client_id'=>'stable-key','reply_to'=>$root];
        $first = $this->postJson("/api/v1/conversations/$id/messages", $body, $ha)->assertCreated();
        $retry = $this->postJson("/api/v1/conversations/$id/messages", $body, $ha)->assertOk();
        $this->assertSame($first->json('message.public_id'), $retry->json('message.public_id'));
        $retry->assertJsonPath('message.reply_to.public_id', $root)->assertJsonPath('message.body','Original reply');
        $this->assertSame(2, Message::count());
        $this->assertSame(1, $this->getJson('/api/v1/conversations', $hb)->json('data.0.unread'));
        // The key always identifies the original, not an editable second send.
        $this->postJson("/api/v1/conversations/$id/messages", ['body'=>'Changed retry','client_id'=>'stable-key'], $ha)->assertOk()->assertJsonPath('message.body','Original reply');
        $this->assertSame(2, Message::count());
    }

    public function test_media_replay_or_invalid_shared_post_never_creates_an_orphan_blob(): void
    {
        [$a,$ha]=$this->member('asha');$this->member('bina');
        $id=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'bina'],$ha)->json('conversation.public_id');
        $body=['media'=>UploadedFile::fake()->image('fixture.jpg'),'client_id'=>'media-stable'];
        $first=$this->post("/api/v1/conversations/$id/messages",$body,$ha)->assertCreated();
        $this->post("/api/v1/conversations/$id/messages",$body,$ha)->assertOk()->assertJsonPath('message.public_id',$first->json('message.public_id'));
        $this->assertSame(1, DB::table('media_blobs')->count());
        $this->assertSame('db', DB::table('media_blobs')->value('storage'));
        $this->post("/api/v1/conversations/$id/messages",['media'=>UploadedFile::fake()->image('other.jpg'),'shared_post'=>(string)\Illuminate\Support\Str::uuid()],$ha)->assertUnprocessable();
        $this->assertSame(1, DB::table('media_blobs')->count());
    }

    public function test_soft_removed_or_pre_rejoin_message_is_not_recreated_or_disclosed(): void
    {
        [$a,$ha]=$this->member('asha');[$b,$hb]=$this->member('bina');
        $id=$this->postJson('/api/v1/conversations',['type'=>'group','title'=>'Group','usernames'=>['bina']],$ha)->json('conversation.public_id');
        $route="/api/v1/conversations/$id/messages";
        $this->postJson($route,['body'=>'Original','client_id'=>'gone-key'],$hb)->assertCreated();
        Message::where('client_id','gone-key')->delete();
        $this->postJson($route,['body'=>'Original','client_id'=>'gone-key'],$hb)->assertGone();
        $this->postJson($route,['body'=>'Before leaving','client_id'=>'old-key'],$hb)->assertCreated();
        $this->postJson("/api/v1/conversations/$id/leave",[],$hb)->assertOk();
        $this->postJson($route,['body'=>'Before leaving','client_id'=>'old-key'],$hb)->assertNotFound();
        $this->postJson("/api/v1/conversations/$id/members",['usernames'=>['bina']],$ha)->assertOk();
        $this->postJson($route,['body'=>'Before leaving','client_id'=>'old-key'],$hb)->assertGone();
        $this->assertSame(2, Message::withTrashed()->count());
    }

    public function test_message_and_private_bytes_rollback_together(): void
    {
        [$a,$ha]=$this->member('asha');$this->member('bina');
        $id=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'bina'],$ha)->json('conversation.public_id');
        DB::listen(function ($query) {
            if (str_starts_with(strtolower($query->sql), 'insert into "media_blobs"')) {
                throw new \RuntimeException('Fixture failure after private bytes insert');
            }
        });
        $this->post("/api/v1/conversations/$id/messages",['media'=>UploadedFile::fake()->image('fixture.jpg'),'client_id'=>'rollback-key'],$ha)->assertStatus(500);
        $this->assertSame(0, DB::table('media_blobs')->count());
        $this->assertSame(0, Message::count());
    }
    public function test_same_key_is_scoped_to_sender_and_conversation(): void
    {
        [$a,$ha]=$this->member('asha');[$b,$hb]=$this->member('bina');$this->member('chandra');
        $id=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'bina'],$ha)->json('conversation.public_id');
        $first=$this->postJson("/api/v1/conversations/$id/messages",['body'=>'A original','client_id'=>'shared-key'],$ha)->assertCreated()->json('message.public_id');
        $second=$this->postJson("/api/v1/conversations/$id/messages",['body'=>'B original','client_id'=>'shared-key'],$hb)->assertCreated()->json('message.public_id');
        $this->assertNotSame($first,$second);
        $other=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'chandra'],$ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$other/messages",['body'=>'Other chat','client_id'=>'shared-key'],$ha)->assertCreated();
        $this->assertSame(3, Message::count());
    }

    public function test_final_group_leave_removes_db_bytes_but_does_not_attempt_legacy_b2_deletion(): void
    {
        [$a,$ha]=$this->member('asha');
        $c=Conversation::create(['type'=>'group','title'=>'Only member','created_by'=>$a->id]);
        $c->members()->attach($a->id,['role'=>'owner']);
        $private=(string)\Illuminate\Support\Str::uuid();
        $legacy=(string)\Illuminate\Support\Str::uuid();
        \App\Support\MediaStore::put($private,'image/png','fixture bytes',private:true);
        DB::table('media_blobs')->insert(['public_id'=>$legacy,'mime'=>'image/png','size'=>1,'storage'=>'b2','data'=>'','created_at'=>now(),'updated_at'=>now()]);
        foreach([$private,$legacy] as $mid){$c->messages()->create(['user_id'=>$a->id,'body'=>'','kind'=>'image','media_id'=>$mid,'media_mime'=>'image/png']);}
        \Illuminate\Support\Facades\Http::preventStrayRequests();
        $this->postJson("/api/v1/conversations/{$c->public_id}/leave",[],$ha)->assertOk();
        $this->assertDatabaseMissing('media_blobs',['public_id'=>$private]);
        $this->assertDatabaseHas('media_blobs',['public_id'=>$legacy,'storage'=>'b2']);
        $this->getJson("/api/v1/media/$legacy")->assertNotFound();
        $this->getJson("/api/v1/media/$legacy",$ha)->assertNotFound();
        $this->assertSame(0, Message::count());
    }

}
