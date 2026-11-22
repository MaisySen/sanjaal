<?php

namespace Tests\Feature;

use App\Models\Conversation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class GroupOwnershipTest extends TestCase
{
    use RefreshDatabase;

    private function group(): array
    {
        config(['group_ownership.enabled' => true]);
        [$owner, $headers] = $this->member('owner');
        [$next, $nextHeaders] = $this->member('next');
        [$third, $thirdHeaders] = $this->member('third');
        $snapshot = $this->postJson('/api/v1/conversations', [
            'type' => 'group', 'title' => 'Synthetic group', 'usernames' => ['next', 'third'],
        ], $headers)->assertCreated()->json('conversation');

        return [$owner, $headers, $next, $nextHeaders, $third, $thirdHeaders, $snapshot];
    }

    private function transfer(array $snapshot, string $member, array $headers)
    {
        return $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/ownership', [
            'member_id' => $member, 'ownership_revision' => $snapshot['ownership_revision'],
        ], $headers);
    }

    public function test_disabled_feature_does_not_offer_or_execute_a_handoff(): void
    {
        [, $headers, $next, , , , $snapshot] = $this->group();
        config(['group_ownership.enabled' => false]);
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_ownership', false);
        $this->transfer($snapshot, $next->public_id, $headers)->assertNotFound();
        $this->assertDatabaseHas('conversation_members', ['user_id' => $next->id, 'role' => 'member']);
    }

    public function test_snapshot_and_capability_identify_one_current_owner(): void
    {
        [$owner, $headers, $next, , , , $snapshot] = $this->group();
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_ownership', true);
        $current = $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $headers)->assertOk()->json('conversation');
        $this->assertSame($snapshot['ownership_revision'], $current['ownership_revision']);
        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $current['ownership_revision']);
        $members = collect($current['members'])->keyBy('public_id');
        $this->assertSame('owner', $members[$owner->public_id]['group_role']);
        $this->assertSame('member', $members[$next->public_id]['group_role']);
    }

    public function test_explicit_handoff_preserves_members_history_and_personal_settings(): void
    {
        [$owner, $headers, $next, $nextHeaders, , , $snapshot] = $this->group();
        $convo = Conversation::where('public_id', $snapshot['public_id'])->firstOrFail();
        $convo->members()->updateExistingPivot($owner->id, ['muted' => true, 'pinned' => true, 'history_from_id' => 7]);
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/messages', ['body' => 'Existing synthetic message', 'client_id' => 'ownership-fixture-message'], $nextHeaders)->assertCreated();
        $messageIds = DB::table('messages')->pluck('id')->all();
        $result = $this->transfer($snapshot, $next->public_id, $headers)->assertOk()->assertJsonPath('conversation.my_role', 'member')->assertJsonCount(3, 'conversation.members')->json('conversation');
        $this->assertNotSame($snapshot['ownership_revision'], $result['ownership_revision']);
        $this->assertSame(1, $convo->fresh()->ownership_version);
        $this->assertSame($messageIds, DB::table('messages')->pluck('id')->all());
        $this->assertDatabaseHas('conversation_members', ['conversation_id' => $convo->id, 'user_id' => $owner->id, 'role' => 'member', 'muted' => true, 'pinned' => true, 'history_from_id' => 7]);
        $this->assertDatabaseHas('conversation_members', ['conversation_id' => $convo->id, 'user_id' => $next->id, 'role' => 'owner']);
        $this->assertSame(1, $convo->members()->wherePivot('role', 'owner')->count());
        $this->patchJson('/api/v1/conversations/'.$snapshot['public_id'], ['title' => 'Old owner cannot rename'], $headers)->assertForbidden();
        $this->patchJson('/api/v1/conversations/'.$snapshot['public_id'], ['title' => 'New owner can rename'], $nextHeaders)->assertOk();
    }

    public function test_non_owner_and_outsider_cannot_choose_or_read_authority(): void
    {
        [, $headers, $next, $nextHeaders, $third, , $snapshot] = $this->group();
        [, $outsiderHeaders] = $this->member('outsider');
        $this->transfer($snapshot, $third->public_id, $nextHeaders)->assertForbidden();
        $this->transfer($snapshot, $next->public_id, $outsiderHeaders)->assertNotFound();
        $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $outsiderHeaders)->assertNotFound();
        $this->transfer($snapshot, $next->public_id, $headers)->assertOk();
        $this->transfer($snapshot, $third->public_id, $headers)->assertForbidden();
    }

    public function test_target_must_be_another_current_stable_member_and_revision_is_required(): void
    {
        [$owner, $headers, $next, , , , $snapshot] = $this->group();
        [$outsider] = $this->member('outsider');
        $this->transfer($snapshot, $owner->public_id, $headers)->assertStatus(422);
        $this->transfer($snapshot, $outsider->public_id, $headers)->assertNotFound();
        $this->transfer($snapshot, 'not-a-uuid', $headers)->assertStatus(422);
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/ownership', ['member_id' => $next->public_id], $headers)->assertStatus(422);
        $this->assertDatabaseHas('conversation_members', ['user_id' => $owner->id, 'role' => 'owner']);
        $this->assertSame(0, Conversation::first()->ownership_version);
    }

    public function test_membership_name_or_group_changes_require_a_new_confirmation(): void
    {
        [, $headers, $next, , , , $snapshot] = $this->group();
        $next->update(['name' => 'Changed synthetic name']);
        $this->transfer($snapshot, $next->public_id, $headers)->assertStatus(409);
        $snapshot = $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $headers)->json('conversation');
        $this->member('newcomer');
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/members', ['usernames' => ['newcomer']], $headers)->assertOk();
        $this->transfer($snapshot, $next->public_id, $headers)->assertStatus(409);
        $snapshot = $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $headers)->json('conversation');
        $this->patchJson('/api/v1/conversations/'.$snapshot['public_id'], ['title' => 'Changed group'], $headers)->assertOk();
        $this->transfer($snapshot, $next->public_id, $headers)->assertStatus(409);
    }

    public function test_ownership_round_trip_cannot_revive_an_old_confirmation(): void
    {
        [$owner, $headers, $next, $nextHeaders, $third, , $snapshot] = $this->group();
        $this->transfer($snapshot, $next->public_id, $headers)->assertOk();
        $current = $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $nextHeaders)->assertOk()->json('conversation');
        $this->transfer($current, $owner->public_id, $nextHeaders)->assertOk();
        $this->transfer($snapshot, $third->public_id, $headers)->assertStatus(409);
        $this->assertSame(2, Conversation::first()->ownership_version);
        $this->assertSame(1, DB::table('conversation_members')->where('role', 'owner')->count());
    }

    public function test_current_owner_leave_keeps_exactly_one_owner_and_invalidates_snapshot(): void
    {
        [$owner, $headers, $next, $nextHeaders, $third, , $snapshot] = $this->group();
        $this->transfer($snapshot, $next->public_id, $headers)->assertOk();
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/leave', [], $nextHeaders)->assertOk();
        $this->assertDatabaseHas('conversation_members', ['user_id' => $owner->id, 'role' => 'owner']);
        $this->assertSame(1, DB::table('conversation_members')->where('role', 'owner')->count());
        $this->transfer($snapshot, $third->public_id, $headers)->assertStatus(409);
        $this->getJson('/api/v1/conversations/'.$snapshot['public_id'], $nextHeaders)->assertNotFound();
    }

    public function test_missing_migration_fails_closed_without_breaking_legacy_group_actions(): void
    {
        [, $headers, $next, , , , $snapshot] = $this->group();
        \Illuminate\Support\Facades\Schema::table('conversations', fn ($table) => $table->dropColumn('ownership_version'));
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_ownership', false);
        $this->transfer($snapshot, $next->public_id, $headers)->assertStatus(503);
        $this->patchJson('/api/v1/conversations/'.$snapshot['public_id'], ['title' => 'Legacy title'], $headers)->assertOk();
        $this->member('newcomer');
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/members', ['usernames' => ['newcomer']], $headers)->assertOk();
        $this->postJson('/api/v1/conversations/'.$snapshot['public_id'].'/leave', [], $headers)->assertOk();
    }

    public function test_direct_chats_and_malformed_paths_do_not_change_roles(): void
    {
        [, $headers, $next, , , , $snapshot] = $this->group();
        $direct = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'next'], $headers)->assertCreated()->json('conversation');
        $this->postJson('/api/v1/conversations/'.$direct['public_id'].'/ownership', ['member_id' => $next->public_id, 'ownership_revision' => $snapshot['ownership_revision']], $headers)->assertStatus(422);
        $this->getJson('/api/v1/conversations/not-a-uuid', $headers)->assertStatus(405);
        $this->postJson('/api/v1/conversations/not-a-uuid/ownership', [], $headers)->assertNotFound();
    }
}
