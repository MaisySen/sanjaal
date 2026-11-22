<?php
namespace Tests\Feature;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;
class FollowListTest extends TestCase
{
 use RefreshDatabase;
 protected function setUp(): void { parent::setUp(); config(['app.key'=>'base64:'.base64_encode(str_repeat('x',32))]); }
 public function test_default_off_and_authentication_gate(): void
 {
  [$a,$ha]=$this->member('owner');
  $this->getJson('/api/v1/auth/me',$ha)->assertJsonPath('features.follow_lists',false);
  $this->getJson('/api/v1/users/owner/followers',$ha)->assertNotFound();
  config(['follow_lists.enabled'=>true]);
  $this->getJson('/api/v1/users/owner/followers')->assertUnauthorized();
  $this->getJson('/api/v1/auth/me',$ha)->assertJsonPath('features.follow_lists',true);
 }
 public function test_directions_project_only_public_member_fields(): void
 {
  config(['follow_lists.enabled'=>true]);
  [$a,$ha]=$this->member('owner');[$b,$hb]=$this->member('follower');[$c,$hc]=$this->member('followed');
  $b->following()->attach($a->id);$a->following()->attach($c->id);
  $j=$this->getJson('/api/v1/users/owner/followers',$ha)->assertOk()->assertJsonPath('direction','followers')->assertJsonCount(1,'data')->assertJsonPath('data.0.username','follower')->json();
  $this->assertEqualsCanonicalizing(['public_id','name','username','bio','avatar_url'],array_keys($j['data'][0]));
  $this->assertEqualsCanonicalizing(['public_id','name','username','bio','avatar_url'],array_keys($j['owner']));
  $this->getJson('/api/v1/users/owner/following',$hb)->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.username','followed')->assertJsonPath('next_cursor',null);
  $this->getJson('/api/v1/users/missing/followers',$ha)->assertNotFound();
  $this->getJson('/api/v1/users/follower/followers',$ha)->assertOk()->assertJsonCount(0,'data');
  $b->delete();$this->getJson('/api/v1/users/owner/followers',$ha)->assertOk()->assertJsonCount(0,'data');
 }
 public function test_both_block_directions_hide_rows_and_blocked_owner(): void
 {
  config(['follow_lists.enabled'=>true]);
  [$a,$ha]=$this->member('owner');[$v,$hv]=$this->member('viewer');[$b,$hb]=$this->member('hidden');[$c,$hc]=$this->member('visible');
  $b->following()->attach($a->id);$c->following()->attach($a->id);
  foreach([[$v->id,$b->id],[$b->id,$v->id]] as [$from,$to]){
   DB::table('blocks')->delete();DB::table('blocks')->insert(['blocker_id'=>$from,'blocked_id'=>$to,'created_at'=>now(),'updated_at'=>now()]);
   $this->getJson('/api/v1/users/owner/followers',$hv)->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.username','visible');
  }
  DB::table('blocks')->delete();DB::table('blocks')->insert(['blocker_id'=>$a->id,'blocked_id'=>$v->id,'created_at'=>now(),'updated_at'=>now()]);
  $this->getJson('/api/v1/users/owner/followers',$hv)->assertNotFound();
 }
 public function test_cursor_is_bounded_tamper_resistant_and_bound_to_viewer_owner_direction(): void
 {
  config(['follow_lists.enabled'=>true]);
  [$a,$ha]=$this->member('owner');[$b,$hb]=$this->member('other');
  foreach(range(1,35) as $n){$u=User::factory()->create(['username'=>'member'.$n]);$u->following()->attach($a->id);}
  $first=$this->getJson('/api/v1/users/owner/followers',$ha)->assertOk()->assertJsonCount(30,'data')->json();
  $cursor=$first['next_cursor'];$this->assertIsString($cursor);
  $tail=$this->getJson('/api/v1/users/owner/followers?cursor='.urlencode($cursor),$ha)->assertOk()->assertJsonCount(5,'data')->assertJsonPath('next_cursor',null)->json();
  $this->assertEmpty(array_intersect(array_column($first['data'],'public_id'),array_column($tail['data'],'public_id')));
  foreach([['owner','following',$ha,$cursor],['other','followers',$ha,$cursor],['owner','followers',$hb,$cursor],['owner','followers',$ha,'broken']] as [$owner,$direction,$h,$c]){
   $this->getJson("/api/v1/users/$owner/$direction?cursor=".urlencode($c),$h)->assertUnprocessable();
  }
 }
 public function test_filters_precede_page_limit_and_reads_do_not_grow_per_member(): void
 {
  config(['follow_lists.enabled'=>true]);[$owner,$headers]=$this->member('owner');[$viewer,$vh]=$this->member('viewer');
  foreach(range(1,40) as $n){
   $u=User::factory()->create(['username'=>'member'.$n]);$u->following()->attach($owner->id);
   if($n<=10)DB::table('blocks')->insert(['blocker_id'=>$u->id,'blocked_id'=>$viewer->id,'created_at'=>now(),'updated_at'=>now()]);
  }
  DB::enableQueryLog();
  $this->getJson('/api/v1/users/owner/followers',$vh)->assertOk()->assertJsonCount(30,'data')->assertJsonPath('next_cursor',null);
  $queries=DB::getQueryLog();DB::disableQueryLog();
  $this->assertLessThanOrEqual(10,count($queries),'Member projection must not issue per-row relationship queries');
  $this->getJson('/api/v1/users/owner/followers?cursor[]=bad',$vh)->assertUnprocessable();
  $this->getJson('/api/v1/users/owner/followers?cursor='.str_repeat('x',2049),$vh)->assertUnprocessable();
 }

}
