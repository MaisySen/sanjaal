<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class GroupMemberRefsTest extends TestCase
{
    use RefreshDatabase;

    public function test_feature_advertises_stable_member_references(): void
    {
        [, $headers] = $this->member('owner');
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.group_member_refs', true);
    }

    public function test_group_creation_uses_exact_selected_ids_and_names(): void
    {
        [$owner, $headers] = $this->member('owner');
        [$friend] = $this->member('friend');
        $this->postJson('/api/v1/conversations', [
            'type' => 'group', 'title' => 'Saved plan', 'usernames' => ['friend'],
            'member_refs' => [['public_id' => $friend->public_id, 'username' => 'friend']],
        ], $headers)->assertCreated()->assertJsonCount(2, 'conversation.members');
        $this->assertDatabaseCount('conversations', 1);
        $this->assertDatabaseHas('conversation_members', ['user_id' => $friend->id]);
        $this->assertDatabaseHas('conversation_members', ['user_id' => $owner->id, 'role' => 'owner']);
    }

    public function test_reassigned_username_cannot_substitute_a_different_person(): void
    {
        [, $headers] = $this->member('owner');
        [$picked] = $this->member('friend');
        $picked->update(['username' => 'newname']);
        $this->member('friend');
        $this->postJson('/api/v1/conversations', [
            'type' => 'group', 'title' => 'Saved plan', 'usernames' => ['friend'],
            'member_refs' => [['public_id' => $picked->public_id, 'username' => 'friend']],
        ], $headers)->assertStatus(422);
        $this->assertDatabaseCount('conversations', 0);
        $this->assertDatabaseCount('conversation_members', 0);
    }

    public function test_mismatched_missing_duplicate_or_self_references_create_nothing(): void
    {
        [$owner, $headers] = $this->member('owner');
        [$friend] = $this->member('friend');
        [$other] = $this->member('other');
        $ref = ['public_id' => $friend->public_id, 'username' => 'friend'];
        foreach ([
            [],
            [['public_id' => $other->public_id, 'username' => 'friend']],
            [['public_id' => 'missing-id', 'username' => 'friend']],
            [['public_id' => $owner->public_id, 'username' => 'friend']],
            [$ref, $ref],
            [['public_id' => $friend->public_id]],
            [['username' => 'friend']],
            [$ref, ['public_id' => $other->public_id, 'username' => 'other']],
        ] as $refs) {
            $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Plan', 'usernames' => ['friend'], 'member_refs' => $refs], $headers)->assertStatus(422);
            $this->assertDatabaseCount('conversations', 0);
            $this->assertDatabaseCount('conversation_members', 0);
        }
    }

    public function test_member_reference_does_not_bypass_blocking(): void
    {
        [$owner, $headers] = $this->member('owner');
        [$friend] = $this->member('friend');
        \DB::table('blocks')->insert(['blocker_id' => $friend->id, 'blocked_id' => $owner->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson('/api/v1/conversations', [
            'type' => 'group', 'title' => 'Plan', 'usernames' => ['friend'],
            'member_refs' => [['public_id' => $friend->public_id, 'username' => 'friend']],
        ], $headers)->assertNotFound();
        $this->assertDatabaseCount('conversations', 0);
    }

    public function test_legacy_group_creation_remains_compatible(): void
    {
        [, $headers] = $this->member('owner');
        $this->member('friend');
        $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Plan', 'usernames' => ['friend']], $headers)->assertCreated();
    }
}
