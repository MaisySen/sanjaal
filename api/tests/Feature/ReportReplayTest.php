<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReportReplayTest extends TestCase
{
    use RefreshDatabase;

    private function body(array $changes = []): array
    {
        return array_merge(['type' => 'post', 'target' => 'original-post', 'reason' => 'spam', 'note' => null, 'submission_id' => '11111111-1111-4111-8111-111111111111'], $changes);
    }

    public function test_member_reference_survives_rename_and_handle_reuse_without_retargeting(): void
    {
        [$member, $headers] = $this->member('reporter');
        [$subject] = $this->member('asha');
        $body = $this->body(['type' => 'user', 'target' => 'asha', 'target_public_id' => $subject->public_id]);
        $receipt = $this->postJson('/api/v1/reports', $body, $headers)->assertCreated()->assertJsonPath('report.target_public_id', $subject->public_id)->json('report.public_id');
        $subject->update(['username' => 'renamed', 'auth0_sub' => 'auth0|renamed']);
        [$replacement] = $this->member('asha');
        $this->postJson('/api/v1/reports', $body, $headers)->assertOk()->assertJsonPath('replayed', true)->assertJsonPath('report.public_id', $receipt)->assertJsonPath('report.target_public_id', $subject->public_id);
        $this->postJson('/api/v1/reports', array_replace($body, ['submission_id' => (string) Str::uuid()]), $headers)->assertConflict();
        $this->postJson('/api/v1/reports', array_replace($body, ['target_public_id' => $replacement->public_id]), $headers)->assertConflict();
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.report_member_refs', true);
        $this->assertDatabaseCount('reports', 1);
        $this->artisan('reports:queue')->expectsOutputToContain($subject->public_id)->assertSuccessful();
    }

    public function test_invalid_or_missing_subject_ref_never_writes_or_leaks_lookup_result(): void
    {
        [$member, $headers] = $this->member('reporter');
        foreach ([['type' => 'post', 'target_public_id' => (string) Str::uuid()], ['type' => 'user', 'target_public_id' => 'not-uuid']] as $change) {
            $this->postJson('/api/v1/reports', $this->body($change), $headers)->assertUnprocessable();
        }
        $this->postJson('/api/v1/reports', $this->body(['type' => 'user', 'target_public_id' => (string) Str::uuid()]), $headers)->assertConflict();
        $this->assertDatabaseCount('reports', 0);
        $this->assertDatabaseCount('report_events', 0);
    }

    public function test_same_submission_returns_one_original_receipt_and_event(): void
    {
        [$member, $headers] = $this->member('reporter');
        $receipt = $this->postJson('/api/v1/reports', $this->body(), $headers)->assertCreated()->assertJsonPath('replayed', false)->json('report.public_id');
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertOk()->assertJsonPath('replayed', true)->assertJsonPath('report.public_id', $receipt);
        $this->assertDatabaseCount('reports', 1);
        $this->assertDatabaseCount('report_events', 1);
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.report_replay', true);
    }

    public function test_changed_payload_conflicts_without_new_receipt_or_event(): void
    {
        [$member, $headers] = $this->member('reporter');
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertCreated();
        foreach ([['type' => 'user'], ['target' => 'another-post'], ['reason' => 'other'], ['note' => 'changed']] as $change) {
            $this->postJson('/api/v1/reports', $this->body($change), $headers)->assertConflict();
        }
        $this->assertDatabaseCount('reports', 1);
        $this->assertDatabaseCount('report_events', 1);
    }

    public function test_another_reporter_has_an_independent_key_and_cannot_read_original(): void
    {
        [$a, $ha] = $this->member('first'); [$b, $hb] = $this->member('second');
        $first = $this->postJson('/api/v1/reports', $this->body(), $ha)->assertCreated()->json('report.public_id');
        $second = $this->postJson('/api/v1/reports', $this->body(['target' => 'different']), $hb)->assertCreated()->json('report.public_id');
        $this->assertNotSame($first, $second);
        $this->getJson('/api/v1/reports/'.$first, $hb)->assertNotFound();
        $this->assertDatabaseCount('reports', 2);
    }

    public function test_replay_retains_operator_progress_instead_of_fabricating_received(): void
    {
        [$member, $headers] = $this->member('reporter');
        $receipt = $this->postJson('/api/v1/reports', $this->body(), $headers)->assertCreated()->json('report.public_id');
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'closed'])->assertSuccessful();
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertOk()->assertJsonPath('report.status', 'closed');
        $this->assertDatabaseCount('report_events', 2);
    }

    public function test_normalized_note_and_uuid_case_replay_without_exposing_private_keys(): void
    {
        [$member, $headers] = $this->member('reporter');
        $key = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        $first = $this->body(['submission_id' => strtoupper($key)]); unset($first['note']);
        $receipt = $this->postJson('/api/v1/reports', $first, $headers)->assertCreated()->json('report.public_id');
        $result = $this->postJson('/api/v1/reports', $this->body(['submission_id' => $key]), $headers)->assertOk()->assertJsonPath('report.public_id', $receipt);
        $this->assertArrayNotHasKey('submission_id', $result->json('report'));
        $this->assertArrayNotHasKey('submission_fingerprint', $result->json('report'));
    }

    public function test_invalid_keys_do_not_write_and_legacy_requests_remain_distinct(): void
    {
        [$member, $headers] = $this->member('reporter');
        foreach ([null, '', 'not-a-key', str_repeat('x', 1000)] as $key) {
            $this->postJson('/api/v1/reports', $this->body(['submission_id' => $key]), $headers)->assertUnprocessable();
        }
        $this->assertDatabaseCount('reports', 0);
        $legacy = $this->body(); unset($legacy['submission_id']);
        $this->postJson('/api/v1/reports', $legacy, $headers)->assertCreated();
        $this->postJson('/api/v1/reports', $legacy, $headers)->assertCreated();
        $this->assertDatabaseCount('reports', 2);
        $this->assertDatabaseCount('report_events', 2);
    }

    public function test_new_submission_key_is_an_explicitly_distinct_report(): void
    {
        [$member, $headers] = $this->member('reporter');
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertCreated();
        $this->postJson('/api/v1/reports', $this->body(['submission_id' => (string) Str::uuid()]), $headers)->assertCreated();
        $this->assertDatabaseCount('reports', 2);
    }

    public function test_event_failure_rolls_back_report_and_leaves_same_key_retryable(): void
    {
        [$member, $headers] = $this->member('reporter');
        if (DB::getDriverName() !== 'sqlite') $this->markTestSkipped('SQLite atomic failure fixture; PostgreSQL contention has its own fixture.');
        DB::unprepared("CREATE TRIGGER reject_report_event BEFORE INSERT ON report_events BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END");
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertServerError();
        $this->assertDatabaseCount('reports', 0);
        DB::unprepared('DROP TRIGGER reject_report_event');
        $this->postJson('/api/v1/reports', $this->body(), $headers)->assertCreated();
        $this->assertDatabaseCount('reports', 1);
        $this->assertDatabaseCount('report_events', 1);
    }
}
