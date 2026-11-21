<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class AccountDeletionRequestTest extends TestCase
{
    use RefreshDatabase;

    private function enable(): void
    {
        config(['account_deletion.enabled' => true, 'account_deletion.completion_mechanism_verified' => true,
            'account_deletion.policy_version' => 'fixture-v1', 'account_deletion.completion_notice' => 'Synthetic completion notice, not production policy.',
            'account_deletion.retention_notice' => 'Synthetic retention notice, not production policy.']);
    }

    public function test_authentication_required(): void
    {
        $this->getJson('/api/v1/auth/me/deletion')->assertUnauthorized();
        $this->postJson('/api/v1/auth/me/deletion', [])->assertUnauthorized();
    }

    public function test_disabled_by_default_without_false_request(): void
    {
        [$a, $h] = $this->member('asha');
        $this->getJson('/api/v1/auth/me/deletion', $h)->assertOk()->assertJsonPath('available', false)->assertJsonPath('request', null);
        $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => true, 'policy_version' => 'fixture-v1'], $h)->assertStatus(503);
        $this->assertDatabaseCount('account_deletion_requests', 0);
        $this->assertDatabaseHas('users', ['id' => $a->id]);
    }

    public function test_enabled_flag_without_completion_or_notices_fails_closed(): void
    {
        [, $h] = $this->member('asha');
        config(['account_deletion.enabled' => true]);
        $this->getJson('/api/v1/auth/me/deletion', $h)->assertJsonPath('available', false);
        $this->enable(); config(['account_deletion.retention_notice' => ' ']);
        $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => true, 'policy_version' => 'fixture-v1'], $h)->assertStatus(503);
        $this->assertDatabaseCount('account_deletion_requests', 0);
    }

    public function test_explicit_confirmation_and_current_policy_required(): void
    {
        [, $h] = $this->member('asha'); $this->enable();
        $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => false, 'policy_version' => 'fixture-v1'], $h)->assertUnprocessable();
        $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => true, 'policy_version' => 'old'], $h)->assertStatus(409);
        $this->assertDatabaseCount('account_deletion_requests', 0);
    }

    public function test_request_is_idempotent_scoped_and_non_destructive(): void
    {
        [$a, $h] = $this->member('asha'); [$b, $hb] = $this->member('bina'); $this->enable();
        $payload = ['confirmed' => true, 'policy_version' => 'fixture-v1'];
        $first = $this->postJson('/api/v1/auth/me/deletion', $payload, $h)->assertCreated()->assertJsonPath('request.status', 'requested')->json('request.public_id');
        config(['account_deletion.enabled' => false]);
        $this->postJson('/api/v1/auth/me/deletion', $payload, $h)->assertOk()->assertJsonPath('request.public_id', $first);
        $this->getJson('/api/v1/auth/me/deletion', $h)->assertJsonPath('available', false)->assertJsonPath('request.public_id', $first);
        $this->getJson('/api/v1/auth/me/deletion', $hb)->assertJsonPath('request', null);
        $this->assertDatabaseCount('account_deletion_requests', 1);
        $this->assertDatabaseHas('users', ['id' => $a->id, 'username' => 'asha']);
        $this->assertDatabaseHas('users', ['id' => $b->id, 'username' => 'bina']);
    }

    public function test_cannot_select_another_member_or_set_status(): void
    {
        [, $h] = $this->member('asha'); [$b] = $this->member('bina'); $this->enable();
        foreach (['user_id' => $b->id, 'status' => 'completed', 'public_id' => 'chosen'] as $field => $value) {
            $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => true, 'policy_version' => 'fixture-v1', $field => $value], $h)->assertUnprocessable();
        }
        $this->assertDatabaseCount('account_deletion_requests', 0);
    }

    public function test_policy_notice_snapshot_does_not_change_under_existing_request(): void
    {
        [, $h] = $this->member('asha'); $this->enable();
        $this->postJson('/api/v1/auth/me/deletion', ['confirmed' => true, 'policy_version' => 'fixture-v1'], $h)->assertCreated();
        config(['account_deletion.completion_notice' => 'Different later notice']);
        $this->getJson('/api/v1/auth/me/deletion', $h)->assertJsonPath('request.completion_notice', 'Synthetic completion notice, not production policy.');
        $this->assertSame('requested', DB::table('account_deletion_requests')->value('status'));
    }
}
