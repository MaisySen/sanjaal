<?php
namespace Tests\Feature;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;
use App\Services\Push;
class CallDeviceTest extends TestCase
{
    use RefreshDatabase;
    private const LEASE = '12345678-1234-4234-8234-123456789abc';
    private const NEXT = 'abcdefab-1234-4234-8234-123456789abc';
    public function test_default_off_registration_and_sender_do_not_enroll_or_send(): void
    {
        [$u,$h]=$this->member('call_member'); Http::fake();
        $this->postJson('/api/v1/call-devices',['transport'=>'fcm','token'=>str_repeat('a',32),'login_lease'=>self::LEASE],$h)->assertNotFound();
        $this->assertSame(0,app(Push::class)->incomingCall('fixture'));
        $this->assertDatabaseCount('call_devices',0); Http::assertNothingSent();
    }
    public function test_token_replacement_is_owner_and_login_lease_bound(): void
    {
        config(['services.call_wake.registration_enabled'=>true]);
        [$a,$ha]=$this->member('call_a'); [$b,$hb]=$this->member('call_b');
        $data=['transport'=>'fcm','token'=>str_repeat('a',32),'login_lease'=>self::LEASE];
        $this->postJson('/api/v1/call-devices',$data,$ha)->assertOk();
        $this->postJson('/api/v1/call-devices',[...$data,'login_lease'=>self::NEXT],$hb)->assertOk();
        $this->postJson('/api/v1/call-devices/remove',$data,$ha)->assertOk();
        $this->assertDatabaseHas('call_devices',['user_id'=>$b->id,'login_lease'=>self::NEXT]);
        $this->postJson('/api/v1/call-devices/remove',$data,$hb)->assertOk();
        $this->assertDatabaseCount('call_devices',1);
        $this->postJson('/api/v1/call-devices/remove',[...$data,'login_lease'=>self::NEXT],$hb)->assertOk();
        $this->assertDatabaseCount('call_devices',0);
        $this->assertDatabaseCount('device_tokens',0);
    }
    public function test_voip_token_is_separate_normalized_and_validated(): void
    {
        config(['services.call_wake.registration_enabled'=>true]); [$u,$h]=$this->member('call_ios');
        $data=['transport'=>'apns_voip','token'=>str_repeat('AB',32),'login_lease'=>self::LEASE,'environment'=>'sandbox'];
        $this->postJson('/api/v1/call-devices',$data,$h)->assertOk();
        $this->assertDatabaseHas('call_devices',['transport'=>'apns_voip','token'=>str_repeat('ab',32)]);
        $this->postJson('/api/v1/call-devices',[...$data,'token'=>'not-a-voip-token'],$h)->assertStatus(422);
        $this->assertDatabaseCount('call_devices',1);
    }
    public function test_native_fcm_is_data_only_current_and_separate_from_chat_devices(): void
    {
        config(['services.call_wake.send_enabled'=>true,
            'services.fcm.credentials'=>json_encode(['client_email'=>'synthetic@example.test','private_key'=>'not-used-with-cached-token','project_id'=>'synthetic-project'])]);
        \Illuminate\Support\Facades\Cache::put('fcm_access_token','synthetic-cached',100);
        [$a,$ha]=$this->member('native_caller'); [$b]=$this->member('native_recipient');
        $cid=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>$b->username],$ha)->assertCreated()->json('conversation.public_id');
        $conversation=\App\Models\Conversation::where('public_id',$cid)->firstOrFail();
        $call=\App\Http\Controllers\ExtrasController::ring($conversation,$a,'video');
        foreach (['fcm','apns_voip'] as $transport) DB::table('call_devices')->insert([
            'user_id'=>$b->id,'transport'=>$transport,'token'=>$transport.'-synthetic',
            'token_hash'=>hash('sha256',$transport),'login_lease'=>self::LEASE,'created_at'=>now(),'updated_at'=>now()]);
        DB::table('device_tokens')->insert(['user_id'=>$b->id,'token'=>'chat-only','platform'=>'android','created_at'=>now(),'updated_at'=>now()]);
        Http::fake(['fcm.googleapis.com/*'=>Http::response(['name'=>'synthetic'],200)]);
        $this->assertSame(1,app(Push::class)->incomingCall($call));
        Http::assertSent(function ($r) use ($b,$call) {
            $m=$r['message'];
            return $m['token']==='fcm-synthetic' && !isset($m['notification']) && !isset($m['apns']) &&
                $m['data']['recipient']===$b->public_id && $m['data']['call']===$call &&
                $m['android']['priority']==='high' && (int)$m['android']['ttl']<=40 &&
                !isset($m['data']['token']) && !isset($m['data']['caller']);
        });
        Http::assertSentCount(1);
        DB::table('calls')->where('public_id',$call)->update(['status'=>'ended']);
        $this->assertSame(0,app(Push::class)->incomingCall($call));
        Http::assertSentCount(1);
    }
}
