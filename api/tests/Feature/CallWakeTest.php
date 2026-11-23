<?php
namespace Tests\Feature;

use App\Http\Controllers\ExtrasController;
use App\Models\Conversation;
use App\Services\CallWake;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** Network-isolated wake construction only, never provider sending. */
class CallWakeTest extends TestCase
{
    use RefreshDatabase;
    private function fixture(): array
    {
        [$a, $ha] = $this->member('wake_caller');
        [$b] = $this->member('wake_recipient');
        [$c] = $this->member('wake_muted');
        [$d] = $this->member('wake_blocked');
        $id = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Fixture',
            'usernames' => [$b->username, $c->username, $d->username]], $ha)->assertCreated()->json('conversation.public_id');
        $conversation = Conversation::where('public_id', $id)->firstOrFail();
        DB::table('conversation_members')->where('conversation_id', $conversation->id)->where('user_id', $c->id)->update(['muted' => true]);
        DB::table('blocks')->insert(['blocker_id' => $d->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()]);
        return [ExtrasController::ring($conversation, $a, 'voice'), $id, $a, $b, $c, $d];
    }
    public function test_only_current_unmuted_unblocked_members_receive_minimal_bound_envelope(): void
    {
        Http::fake();
        [$call, $conversation, , $recipient] = $this->fixture();
        $rows = app(CallWake::class)->recipients($call);
        $this->assertCount(1, $rows);
        $this->assertSame($recipient->id, $rows[0]['user_id']);
        $data = $rows[0]['data'];
        $this->assertSame(['type', 'call_version', 'recipient', 'call', 'conversation', 'kind', 'issued_at', 'expires_at'], array_keys($data));
        $this->assertSame($recipient->public_id, $data['recipient']);
        $this->assertSame($call, $data['call']); $this->assertSame($conversation, $data['conversation']);
        $this->assertSame(40, (int) $data['expires_at'] - (int) $data['issued_at']);
        Http::assertNothingSent();
    }
    public function test_expired_terminal_missing_and_future_rows_cannot_produce_a_ring(): void
    {
        [$call] = $this->fixture();
        $service = app(CallWake::class);
        $this->assertSame([], $service->recipients('missing'));
        foreach (['answered', 'declined', 'missed', 'ended'] as $status) {
            DB::table('calls')->where('public_id', $call)->update(['status' => $status]);
            $this->assertSame([], $service->recipients($call));
        }
        DB::table('calls')->where('public_id', $call)->update(['status' => 'ringing', 'created_at' => now()->addMinute()]);
        $this->assertSame([], $service->recipients($call));
        DB::table('calls')->where('public_id', $call)->update(['created_at' => now()->subSeconds(40)]);
        $this->assertSame([], $service->recipients($call));
    }
    public function test_removed_recipient_and_new_block_are_rechecked_at_dispatch_construction(): void
    {
        [$call, $conversation, $caller, $recipient] = $this->fixture();
        DB::table('blocks')->insert(['blocker_id' => $caller->id, 'blocked_id' => $recipient->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->assertSame([], app(CallWake::class)->recipients($call));
        DB::table('blocks')->where('blocker_id', $caller->id)->delete();
        DB::table('conversation_members')->where('user_id', $recipient->id)->delete();
        $this->assertSame([], app(CallWake::class)->recipients($call));
    }
    public function test_departed_caller_cannot_wake_remaining_members(): void
    {
        [$call, , $caller] = $this->fixture();
        DB::table('conversation_members')->where('user_id', $caller->id)->delete();
        $this->assertSame([], app(CallWake::class)->recipients($call));
    }

}
