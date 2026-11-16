<?php

namespace Tests\Feature;

use App\Models\Conversation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MessageHistoryTest extends TestCase
{
    use RefreshDatabase;

    public function test_before_sequence_pages_are_exclusive_sorted_and_stop_at_membership_boundary(): void
    {
        [$a,$ha]=$this->member('asha');[$b,$hb]=$this->member('bina');[$c,$hc]=$this->member('chandra');
        $convo=Conversation::create(['type'=>'group','title'=>'History','created_by'=>$a->id]);
        $convo->members()->attach([$a->id=>['role'=>'owner','history_from_id'=>0],$b->id=>['role'=>'member','history_from_id'=>0]]);
        foreach(range(1,120) as $i){$convo->messages()->create(['user_id'=>$a->id,'body'=>"Message $i",'client_id'=>"fixture-$i"]);}
        $route="/api/v1/conversations/{$convo->public_id}/messages";
        $latest=$this->getJson($route,$ha)->assertOk()->assertJsonCount(50,'data')->json('data');
        $this->assertSame('Message 71',$latest[0]['body']);$this->assertSame('Message 120',$latest[49]['body']);
        $middle=$this->getJson($route.'?before_seq='.$latest[0]['seq'],$ha)->assertOk()->assertJsonCount(50,'data')->json('data');
        $this->assertSame('Message 21',$middle[0]['body']);$this->assertSame('Message 70',$middle[49]['body']);
        $oldest=$this->getJson($route.'?before_seq='.$middle[0]['seq'],$ha)->assertOk()->assertJsonCount(20,'data')->json('data');
        $this->assertSame('Message 1',$oldest[0]['body']);
        $this->getJson($route.'?before_seq='.$oldest[0]['seq'],$ha)->assertOk()->assertJsonCount(0,'data');
        $all=array_merge($oldest,$middle,$latest);$ids=array_column($all,'public_id');$this->assertSame(120,count(array_unique($ids)));
        $convo->members()->attach($c->id,['role'=>'member','history_from_id'=>$middle[19]['seq']]);
        $visible=$this->getJson($route.'?before_seq='.$latest[0]['seq'],$hc)->assertOk()->json('data');
        $this->assertSame('Message 41',$visible[0]['body']);$this->assertSame(30,count($visible));
        $this->getJson($route.'?before_seq='.$visible[0]['seq'],$hc)->assertOk()->assertJsonCount(0,'data');
        $this->postJson("/api/v1/conversations/{$convo->public_id}/leave",[],$hc)->assertOk();
        $this->getJson($route.'?before_seq='.$latest[0]['seq'],$hc)->assertNotFound();
    }
}
