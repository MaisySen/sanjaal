<?php
namespace Tests\Feature;
use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class MemberControlsTest extends TestCase
{
    use RefreshDatabase;
    public function test_controls_are_private_defaulted_validated_and_revision_guarded(): void
    {
        [$a,$ha]=$this->member('owner'); [$b,$hb]=$this->member('other');
        $url='/api/v1/auth/me/controls';
        $this->getJson($url)->assertUnauthorized();
        $this->getJson($url,$ha)->assertOk()->assertJsonPath('controls.comments_from','everyone')->assertJsonPath('controls.share_to_chat',true)->assertJsonPath('controls.revision',0);
        $this->patchJson($url,['revision'=>0,'comments_from'=>'nobody','share_to_chat'=>false,'user_id'=>$b->id],$ha)->assertOk()->assertJsonPath('controls.revision',1);
        $this->getJson($url,$hb)->assertJsonPath('controls.comments_from','everyone')->assertJsonPath('controls.share_to_chat',true);
        $this->patchJson($url,['revision'=>0,'comments_from'=>'everyone'],$ha)->assertConflict();
        $this->getJson($url,$ha)->assertJsonPath('controls.comments_from','nobody');
        foreach ([['revision'=>1],['revision'=>1,'comments_from'=>'private'],['comments_from'=>'everyone'],['revision'=>1,'share_to_chat'=>'yes']] as $bad) $this->patchJson($url,$bad,$ha)->assertUnprocessable();
        $this->getJson('/api/v1/users/owner',$hb)->assertJsonMissingPath('user.comments_from')->assertJsonMissingPath('user.share_to_chat');
        $this->getJson('/api/v1/auth/me',$ha)->assertJsonPath('features.interaction_controls',true);
        $this->assertDatabaseCount('member_controls',1);
    }
    public function test_comment_scope_uses_owners_following_not_unsolicited_followers(): void
    {
        [$a,$ha]=$this->member('owner'); [$b,$hb]=$this->member('other');
        $p=Post::create(['user_id'=>$a->id,'kind'=>'post','body'=>'Discussion']); $url="/api/v1/posts/{$p->public_id}/comments";
        $this->patchJson('/api/v1/auth/me/controls',['revision'=>0,'comments_from'=>'following'],$ha)->assertOk();
        $this->postJson($url,['body'=>'not followed'],$hb)->assertForbidden();
        $b->following()->attach($a->id);
        $this->postJson($url,['body'=>'following owner is insufficient'],$hb)->assertForbidden();
        $a->following()->attach($b->id);
        $root=$this->postJson($url,['body'=>'allowed'],$hb)->assertCreated()->json('comment.public_id');
        $this->patchJson('/api/v1/auth/me/controls',['revision'=>1,'comments_from'=>'nobody'],$ha)->assertOk();
        $this->postJson($url,['body'=>'no reply','parent_id'=>$root],$hb)->assertForbidden();
        $this->postJson($url,['body'=>'owner still can'],$ha)->assertCreated();
        $this->getJson($url,$hb)->assertOk()->assertJsonCount(2,'data');
        $this->assertSame(2,$p->fresh()->comments_count);
        $this->getJson("/api/v1/posts/{$p->public_id}",$hb)->assertJsonPath('post.can_comment',false);
        $this->getJson('/api/v1/posts',$hb)->assertJsonPath('data.0.can_comment',false);
        $this->getJson('/api/v1/posts',$ha)->assertJsonPath('data.0.can_comment',true);
    }
    public function test_share_setting_is_enforced_for_new_sends_without_deleting_prior_messages(): void
    {
        [$a,$ha]=$this->member('owner');[$b,$hb]=$this->member('sender');[$c,$hc]=$this->member('receiver');
        $p=Post::create(['user_id'=>$a->id,'kind'=>'post','body'=>'A public post']);
        $chat=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'receiver'],$hb)->assertCreated()->json('conversation.public_id');
        $url="/api/v1/conversations/$chat/messages";
        $key='original';
        $this->postJson($url,['shared_post'=>$p->public_id,'client_id'=>$key],$hb)->assertCreated();
        $this->patchJson('/api/v1/auth/me/controls',['revision'=>0,'share_to_chat'=>false],$ha)->assertOk();
        $this->postJson($url,['shared_post'=>$p->public_id,'client_id'=>'new'],$hb)->assertForbidden();
        $this->postJson($url,['shared_post'=>$p->public_id,'client_id'=>$key],$hb)->assertOk();
        $this->getJson($url,$hc)->assertOk()->assertJsonCount(1,'data');
        $this->assertDatabaseCount('messages',1);
        $this->getJson("/api/v1/posts/{$p->public_id}",$hb)->assertJsonPath('post.can_share_to_chat',false);
        $this->getJson('/api/v1/posts',$hb)->assertJsonPath('data.0.can_share_to_chat',false);
        // This controls Sanjaal sharing, never promises revocation of public links.
        $ownchat=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>'receiver'],$ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$ownchat/messages",['shared_post'=>$p->public_id,'client_id'=>'own'],$ha)->assertCreated();
    }
    public function test_per_page_control_queries_are_batched_and_blocks_still_win(): void
    {
        [$a,$ha]=$this->member('owner');[$b,$hb]=$this->member('viewer');
        foreach(range(1,15) as $i) Post::create(['user_id'=>$a->id,'kind'=>'post','body'=>"Post $i"]);
        DB::enableQueryLog();$this->getJson('/api/v1/posts',$hb)->assertOk()->assertJsonCount(15,'data');
        $reads=collect(DB::getQueryLog())->filter(fn($q)=>str_contains($q['query'],'member_controls'));DB::disableQueryLog();$this->assertCount(1,$reads);
        $this->postJson('/api/v1/users/viewer/block',[],$ha)->assertOk();
        $this->getJson('/api/v1/posts',$hb)->assertJsonCount(0,'data');
        $p=Post::first();$this->postJson("/api/v1/posts/{$p->public_id}/comments",['body'=>'blocked'],$hb)->assertNotFound();
    }
}
