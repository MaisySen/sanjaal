<?php

namespace Tests\Feature;

use App\Models\Conversation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class GroupMemberRemovalTest extends TestCase
{
    use RefreshDatabase;

    private function group(): array
    {
        config(['group_member_removal.enabled' => true, 'group_ownership.enabled' => true]);
        [$owner, $headers] = $this->member('owner');
        [$target, $targetHeaders] = $this->member('target');
        [$third, $thirdHeaders] = $this->member('third');
        $snapshot = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Synthetic removal', 'usernames' => ['target', 'third']], $headers)->assertCreated()->json('conversation');

        return [$owner, $headers, $target, $targetHeaders, $third, $thirdHeaders, $snapshot];
    }

    private function remove(array $snapshot, string $target, array $headers)
    {
        return $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/member-removals', ['member_id' => $target, 'ownership_revision' => $snapshot['ownership_revision']], $headers);
    }

    public function test_default_disabled_feature_does_not_advertise_or_remove(): void
    {
        [, $headers, $target, , , , $snapshot] = $this->group();
        config(['group_member_removal.enabled' => false]);
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_member_removal', false);
        $this->remove($snapshot, $target->public_id, $headers)->assertNotFound();
        $this->assertDatabaseCount('conversation_members', 3);
    }

    public function test_owner_removes_only_the_selected_member_without_deleting_history(): void
    {
        [$owner, $headers, $target, $targetHeaders, $third, , $snapshot] = $this->group();
        $id = $snapshot['public_id'];
        $convo = Conversation::where('public_id', $id)->firstOrFail();
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_member_removal', true);
        $convo->members()->updateExistingPivot($owner->id, ['muted' => true, 'pinned' => true]);
        $message = $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'Keep this earlier message', 'client_id' => 'before-removal'], $targetHeaders)->assertCreated()->json('message.public_id');
        $current = $this->remove($snapshot, $target->public_id, $headers)->assertOk()->assertJsonPath('conversation.my_role', 'owner')->assertJsonCount(2, 'conversation.members')->json('conversation');
        $this->assertNotSame($snapshot['ownership_revision'], $current['ownership_revision']);
        $this->assertSame(1, $convo->fresh()->ownership_version);
        $this->assertEqualsCanonicalizing([$owner->public_id, $third->public_id], collect($current['members'])->pluck('public_id')->all());
        $this->assertDatabaseHas('messages', ['public_id' => $message, 'user_id' => $target->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('conversation_members', ['user_id' => $owner->id, 'role' => 'owner', 'pinned' => true, 'muted' => true]);
        $this->assertDatabaseMissing('conversation_members', ['user_id' => $target->id]);
        $this->assertSame(1, $convo->members()->wherePivot('role', 'owner')->count());
    }

    public function test_removed_member_cannot_read_send_rename_invite_or_probe_the_group(): void
    {
        [, $headers, $target, $targetHeaders, , , $snapshot] = $this->group();
        $id = $snapshot['public_id'];
        $this->member('newcomer');
        $this->remove($snapshot, $target->public_id, $headers)->assertOk();
        $this->getJson("/api/v1/conversations/$id", $targetHeaders)->assertNotFound();
        $this->getJson("/api/v1/conversations/$id/messages?after_seq=0", $targetHeaders)->assertNotFound();
        $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'Not allowed', 'client_id' => 'removed-send'], $targetHeaders)->assertNotFound();
        $this->postJson("/api/v1/conversations/$id/read", [], $targetHeaders)->assertNotFound();
        $this->postJson("/api/v1/conversations/$id/typing", [], $targetHeaders)->assertNotFound();
        $this->patchJson("/api/v1/conversations/$id", ['title' => 'Not allowed'], $targetHeaders)->assertNotFound();
        $this->postJson("/api/v1/conversations/$id/members", ['usernames' => ['newcomer']], $targetHeaders)->assertNotFound();
        $this->getJson('/api/v1/conversations', $targetHeaders)->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_removal_cuts_off_private_media_without_deleting_other_members_copy(): void
    {
        [, $headers, $target, $targetHeaders, , , $snapshot] = $this->group();
        $id = $snapshot['public_id'];
        $image = $this->post("/api/v1/conversations/$id/messages", ['media' => UploadedFile::fake()->image('synthetic.jpg', 30, 30)], $headers)->assertCreated()->json('message');
        $url = $image['media_url'];
        $this->get($url, $targetHeaders)->assertOk();
        $this->remove($snapshot, $target->public_id, $headers)->assertOk();
        $this->get($url, $targetHeaders)->assertNotFound();
        $this->get($url, $headers)->assertOk();
        $this->assertDatabaseCount('media_blobs', 1);
        $this->assertDatabaseCount('messages', 1);
    }

    public function test_reinvitation_uses_new_history_boundary_not_old_membership(): void
    {
        [, $headers, $target, $targetHeaders, , , $snapshot] = $this->group();
        $id = $snapshot['public_id'];
        $old = $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'Earlier message', 'client_id' => 'old-target-message'], $targetHeaders)->assertCreated()->json('message.public_id');
        $this->remove($snapshot, $target->public_id, $headers)->assertOk();
        $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'During absence', 'client_id' => 'during-absence'], $headers)->assertCreated();
        $this->postJson("/api/v1/conversations/$id/members", ['usernames' => ['target']], $headers)->assertOk();
        $this->getJson("/api/v1/conversations/$id/messages", $targetHeaders)->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'Earlier message', 'client_id' => 'old-target-message'], $targetHeaders)->assertStatus(410);
        $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'After return', 'reply_to' => $old, 'client_id' => 'after-return'], $targetHeaders)->assertCreated()->assertJsonPath('message.reply_to', null);
        $this->getJson("/api/v1/conversations/$id/messages", $targetHeaders)->assertJsonCount(1, 'data')->assertJsonPath('data.0.body', 'After return');
        $this->getJson("/api/v1/conversations/$id/messages", $headers)->assertJsonCount(3, 'data');
    }

    public function test_non_owner_outsider_and_self_removal_are_rejected(): void
    {
        [$owner, $headers, $target, $targetHeaders, $third, , $snapshot] = $this->group();
        [, $outsiderHeaders] = $this->member('outsider');
        $this->remove($snapshot, $third->public_id, $targetHeaders)->assertForbidden();
        $this->remove($snapshot, $target->public_id, $outsiderHeaders)->assertNotFound();
        $this->remove($snapshot, $owner->public_id, $headers)->assertStatus(422);
        $this->assertDatabaseCount('conversation_members', 3);
    }

    public function test_stale_role_or_membership_confirmation_cannot_remove_anyone(): void
    {
        [, $headers, $target, , $third, $thirdHeaders, $snapshot] = $this->group();
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/ownership', ['member_id' => $third->public_id, 'ownership_revision' => $snapshot['ownership_revision']], $headers)->assertOk();
        $this->remove($snapshot, $target->public_id, $headers)->assertForbidden();
        $this->remove($snapshot, $target->public_id, $thirdHeaders)->assertStatus(409);
        $this->assertDatabaseCount('conversation_members', 3);
    }

    public function test_leave_and_rejoin_cannot_revive_the_old_removal_confirmation(): void
    {
        [, $headers, $target, $targetHeaders, , , $snapshot] = $this->group();
        $id = $snapshot['public_id'];
        $this->postJson("/api/v1/conversations/$id/leave", [], $targetHeaders)->assertOk();
        $this->postJson("/api/v1/conversations/$id/members", ['usernames' => ['target']], $headers)->assertOk();
        $this->remove($snapshot, $target->public_id, $headers)->assertStatus(409);
        $this->assertDatabaseCount('conversation_members', 3);
    }

    public function test_missing_migration_and_malformed_targets_fail_closed(): void
    {
        [, $headers, $target, , , , $snapshot] = $this->group();
        $this->remove($snapshot, 'bad-id', $headers)->assertStatus(422);
        $this->remove($snapshot, '00000000-0000-4000-8000-000000000099', $headers)->assertNotFound();
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/member-removals', ['member_id' => $target->public_id], $headers)->assertStatus(422);
        \Illuminate\Support\Facades\Schema::table('conversations', fn ($table) => $table->dropColumn('ownership_version'));
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_member_removal', false);
        $this->remove($snapshot, $target->public_id, $headers)->assertStatus(503);
        $this->assertDatabaseCount('conversation_members', 3);
    }

    public function test_direct_chats_cannot_remove_the_other_member(): void
    {
        [, $headers, $target, , , , $snapshot] = $this->group();
        $direct = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'target'], $headers)->assertCreated()->json('conversation');
        $direct['ownership_revision'] = $snapshot['ownership_revision'];
        $this->remove($direct, $target->public_id, $headers)->assertStatus(422);
        $this->assertDatabaseCount('conversation_members', 5);
    }
}
