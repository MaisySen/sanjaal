<?php
namespace Tests\Feature;

use App\Models\Conversation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Disposable fixture only, against the no-schema production compatibility patch. */
class BackendDeliveryCompatTest extends TestCase
{
    use RefreshDatabase;

    public function test_only_covered_capabilities_are_added_without_activation_or_schema(): void
    {
        [, $headers] = $this->member('owner');
        $features = $this->getJson('/api/v1/auth/me', $headers)->assertOk()->json('features');
        $this->assertSame(['interaction_controls','video_posters','protected_stories','story_replies','group_member_refs','polls','upload_intents'], array_keys($features));
        $this->assertFalse(\Illuminate\Support\Facades\Schema::hasColumn('conversations', 'ownership_version'));
        foreach (['discovery_eligibilities','report_receipts'] as $table) $this->assertFalse(\Illuminate\Support\Facades\Schema::hasTable($table));
        $this->getJson('/api/v1/discovery', $headers)->assertNotFound();
        $this->getJson('/api/v1/reports', $headers)->assertStatus(405);
        $this->getJson('/api/v1/users/owner/followers', $headers)->assertNotFound();
    }

    public function test_legacy_username_group_creation_and_new_snapshot_are_compatible(): void
    {
        [, $owner] = $this->member('owner');
        [, $member] = $this->member('member');
        [, $outsider] = $this->member('outsider');
        $group = $this->postJson('/api/v1/conversations', ['type'=>'group','title'=>'Synthetic legacy','usernames'=>['member']], $owner)->assertCreated()->json('conversation');
        $this->getJson('/api/v1/conversations/'.$group['public_id'], $owner)->assertOk()->assertJsonPath('conversation', $group);
        $this->getJson('/api/v1/conversations/'.$group['public_id'], $member)->assertOk()->assertJsonPath('conversation.my_role', 'member');
        $this->getJson('/api/v1/conversations/'.$group['public_id'], $outsider)->assertNotFound();
        foreach (['ownership','member-removals'] as $action) $this->postJson('/api/v1/conversations/'.$group['public_id'].'/'.$action, [], $owner)->assertNotFound();
        $this->assertArrayNotHasKey('ownership_revision', $group);
        $this->assertArrayNotHasKey('group_role', $group['members'][0]);
    }

    public function test_pending_poll_rechecks_membership_after_wait_before_releasing_content(): void
    {
        [$a, $owner] = $this->member('owner');
        [$b, $member] = $this->member('member');
        $group = $this->postJson('/api/v1/conversations', ['type'=>'group','title'=>'Synthetic pending poll','usernames'=>['member']], $owner)->assertCreated()->json('conversation.public_id');
        $this->postJson('/api/v1/conversations/'.$group.'/messages', ['body'=>'private pending fixture','client_id'=>'private-pending-fixture'], $owner)->assertCreated();
        $conversation = Conversation::where('public_id', $group)->firstOrFail();
        $removed = false;
        DB::listen(function ($query) use (&$removed, $conversation, $b) {
            // Inject a committed membership departure at the wait-query boundary.
            if (!$removed && str_contains(strtolower($query->sql), 'exists') && str_contains(strtolower($query->sql), 'messages')) {
                $removed = true;
                $conversation->members()->detach($b->id);
            }
        });
        $this->getJson('/api/v1/conversations/'.$group.'/messages?after_seq=0&wait=0', $member)->assertNotFound();
        $this->assertTrue($removed);
        $this->assertDatabaseHas('messages', ['body'=>'private pending fixture','user_id'=>$a->id]);
    }
}
