<?php
namespace Tests\Feature;
use App\Services\CallVoipPush;
use App\Models\Conversation;
use App\Http\Controllers\ExtrasController;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;
class CallVoipPushTest extends TestCase
{
    use RefreshDatabase;
    private function fixture(): array
    {
        [$a,$ha]=$this->member('voip_a'); [$b]=$this->member('voip_b');
        $cid=$this->postJson('/api/v1/conversations',['type'=>'direct','username'=>$b->username],$ha)->json('conversation.public_id');
        $conversation=Conversation::where('public_id',$cid)->firstOrFail();
        return [ExtrasController::ring($conversation,$a,'voice'),$b];
    }
    private function enable(): void
    {
        // Ephemeral test key never saved; all HTTP is intercepted.
        $key=openssl_pkey_new(['private_key_type'=>OPENSSL_KEYTYPE_EC,'curve_name'=>'prime256v1']);
        openssl_pkey_export($key,$pem);
        config(['services.call_wake.send_enabled'=>true,'services.call_wake.apns_enabled'=>true,
            'services.call_wake.apns_key_id'=>'ABCDEFGHIJ','services.call_wake.apns_team_id'=>'KLMNOPQRST',
            'services.call_wake.apns_bundle_id'=>'test.synthetic','services.call_wake.apns_private_key'=>$pem]);
    }
    public function test_default_off_and_missing_configuration_make_no_network_request(): void
    {
        Http::fake(); [$call]=$this->fixture();
        $this->assertSame(0,app(CallVoipPush::class)->incomingCall($call));
        config(['services.call_wake.send_enabled'=>true,'services.call_wake.apns_enabled'=>true]);
        $this->assertSame(0,app(CallVoipPush::class)->incomingCall($call)); Http::assertNothingSent();
    }
    public function test_voip_request_has_exact_environment_topic_type_no_alert_and_no_storage(): void
    {
        Http::fake(); $this->enable(); [$call,$b]=$this->fixture();
        foreach (['sandbox','production'] as $env) DB::table('call_devices')->insert([
            'user_id'=>$b->id,'transport'=>'apns_voip','environment'=>$env,'token'=>str_repeat($env==='sandbox'?'a':'b',64),
            'token_hash'=>hash('sha256',$env),'login_lease'=>'12345678-1234-4234-8234-123456789abc',
            'created_at'=>now(),'updated_at'=>now()]);
        $this->assertSame(2,app(CallVoipPush::class)->incomingCall($call));
        foreach (['api.sandbox.push.apple.com','api.push.apple.com'] as $host) Http::assertSent(fn ($r) =>
            str_contains($r->url(),$host) && $r->hasHeader('apns-push-type','voip') &&
            $r->hasHeader('apns-topic','test.synthetic.voip') && $r->hasHeader('apns-expiration','0') &&
            $r['recipient']===$b->public_id && $r['call']===$call && !isset($r['aps']->alert));
        Http::assertSentCount(2);
        DB::table('calls')->where('public_id',$call)->update(['status'=>'ended']);
        $this->assertSame(0,app(CallVoipPush::class)->incomingCall($call)); Http::assertSentCount(2);
    }
    public function test_old_unregistered_response_does_not_delete_a_newer_token_binding(): void
    {
        $this->enable(); [$call,$b]=$this->fixture();
        DB::table('call_devices')->insert(['user_id'=>$b->id,'transport'=>'apns_voip','environment'=>'sandbox',
            'token'=>str_repeat('a',64),'token_hash'=>hash('sha256','fixture'),
            'login_lease'=>'12345678-1234-4234-8234-123456789abc','created_at'=>now(),'updated_at'=>now()]);
        Http::fake(['*.push.apple.com/*'=>Http::response(['reason'=>'Unregistered','timestamp'=>(time()-10)*1000],410)]);
        $this->assertSame(0,app(CallVoipPush::class)->incomingCall($call));
        $this->assertDatabaseCount('call_devices',1); Http::assertSentCount(1);
    }
}
