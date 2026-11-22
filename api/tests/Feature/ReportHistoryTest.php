<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class ReportHistoryTest extends TestCase
{
    use RefreshDatabase;

    public function test_unknown_legacy_timestamps_remain_unknown(): void
    {
        [$member, $headers] = $this->member('legacy');
        $receipt = (string) Str::uuid();
        $id = DB::table('reports')->insertGetId(['public_id' => $receipt, 'reporter_id' => $member->id, 'target_type' => 'user', 'target_id' => 'original-reference', 'reason' => 'spam', 'status' => 'received', 'created_at' => null, 'updated_at' => null]);
        DB::table('report_events')->insert(['report_id' => $id, 'status' => 'received', 'created_at' => null]);
        $this->getJson('/api/v1/reports/'.$receipt, $headers)->assertOk()->assertJsonPath('report.created_at', null)->assertJsonPath('report.updated_at', null)->assertJsonPath('events.0.created_at', null);
    }

    public function test_migration_preserves_legacy_reports_without_inventing_review(): void
    {
        [$member, $headers] = $this->member('legacy');
        $migration = require database_path('migrations/2026_11_22_000000_report_receipts.php');
        $migration->down();
        DB::table('reports')->insert(['reporter_id' => $member->id, 'target_type' => 'user', 'target_id' => 'original-target', 'reason' => 'spam', 'created_at' => '2026-11-20 10:00:00', 'updated_at' => '2026-11-20 10:00:00']);
        $migration->up();
        $result = $this->getJson('/api/v1/reports', $headers)->assertOk()->assertJsonPath('data.0.status', 'received')->assertJsonPath('data.0.target', 'original-target')->json('data.0');
        $this->assertTrue(Str::isUuid($result['public_id']));
        $this->getJson('/api/v1/reports/'.$result['public_id'], $headers)->assertOk()->assertJsonCount(1, 'events')->assertJsonPath('events.0.status', 'received');
    }

    public function test_operator_queue_is_bounded_read_only_and_omits_closed_reviews(): void
    {
        [$member, $headers] = $this->member('reporter');
        $receipt = $this->postJson('/api/v1/reports', ['type' => 'user', 'target' => 'original-target', 'reason' => 'spam'], $headers)->json('report.public_id');
        $this->artisan('reports:queue', ['--limit' => 1])->expectsOutputToContain($receipt)->assertSuccessful();
        $this->assertDatabaseCount('report_events', 1);
        $this->artisan('reports:queue', ['--limit' => 51])->assertFailed();
        $this->artisan('reports:queue', ['--after' => 'invalid'])->assertFailed();
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'closed'])->assertSuccessful();
        $this->artisan('reports:queue')->expectsOutput('{"data":[],"next_cursor":null}')->assertSuccessful();
        $this->getJson('/api/v1/auth/me', $headers)->assertOk()->assertJsonPath('features.report_history', true);
    }

    public function test_submission_returns_durable_owner_receipt_and_history(): void
    {
        [$member, $headers] = $this->member('reporter');
        $body = ['type' => 'user', 'target' => 'reported-member', 'reason' => 'abuse', 'note' => 'My original note'];
        $receipt = $this->postJson('/api/v1/reports', $body, $headers)->assertCreated()->assertJsonPath('report.status', 'received')->json('report.public_id');
        $this->assertTrue(Str::isUuid($receipt));
        $this->getJson('/api/v1/reports', $headers)->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.public_id', $receipt)->assertJsonPath('next_cursor', null);
        $response = $this->getJson('/api/v1/reports/'.$receipt, $headers)->assertOk()->assertJsonPath('report.note', 'My original note')->assertJsonPath('events.0.status', 'received')->assertJsonCount(1, 'events');
        $this->assertArrayNotHasKey('reporter_id', $response->json('report'));
        $this->assertArrayNotHasKey('id', $response->json('report'));
        $this->assertDatabaseCount('report_events', 1);
    }

    public function test_other_members_and_target_cannot_read_receipts_or_use_foreign_cursor(): void
    {
        [$a, $ha] = $this->member('reporter');
        [$b, $hb] = $this->member('reported');
        $receipt = $this->postJson('/api/v1/reports', ['type' => 'user', 'target' => 'reported', 'reason' => 'spam'], $ha)->json('report.public_id');
        $this->getJson('/api/v1/reports', $hb)->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/reports/'.$receipt, $hb)->assertNotFound();
        $this->getJson('/api/v1/reports?cursor='.$receipt, $hb)->assertNotFound();
        $this->getJson('/api/v1/reports/'.Str::uuid(), $hb)->assertNotFound();
        $this->getJson('/api/v1/reports')->assertUnauthorized();
        $this->getJson('/api/v1/reports/'.$receipt)->assertUnauthorized();
    }

    public function test_bounded_paging_has_no_foreign_rows_or_duplicates(): void
    {
        [$a, $ha] = $this->member('reporter');
        [$b, $hb] = $this->member('other');
        $ids = [];
        for ($i = 0; $i < 5; $i++) {
            $ids[] = $this->postJson('/api/v1/reports', ['type' => 'post', 'target' => 'original-'.$i, 'reason' => 'spam'], $ha)->json('report.public_id');
            $this->postJson('/api/v1/reports', ['type' => 'post', 'target' => 'private-'.$i, 'reason' => 'other'], $hb)->assertCreated();
        }
        $all = []; $cursor = null;
        do {
            $page = $this->getJson('/api/v1/reports?limit=2'.($cursor ? '&cursor='.$cursor : ''), $ha)->assertOk()->json();
            $this->assertLessThanOrEqual(2, count($page['data']));
            $all = array_merge($all, array_column($page['data'], 'public_id'));
            $cursor = $page['next_cursor'];
        } while ($cursor);
        $this->assertSame(array_reverse($ids), $all);
        $this->getJson('/api/v1/reports?limit=51', $ha)->assertUnprocessable();
        $this->getJson('/api/v1/reports?cursor=not-a-receipt', $ha)->assertUnprocessable();
    }

    public function test_operator_progress_is_visible_but_members_cannot_change_it(): void
    {
        [$a, $ha] = $this->member('reporter');
        $receipt = $this->postJson('/api/v1/reports', ['type' => 'comment', 'target' => 'original-reference', 'reason' => 'violence'], $ha)->json('report.public_id');
        $this->patchJson('/api/v1/reports/'.$receipt, ['status' => 'closed'], $ha)->assertStatus(405);
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'in_review'])->assertSuccessful();
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'in_review'])->assertSuccessful();
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'closed'])->assertSuccessful();
        $this->getJson('/api/v1/reports/'.$receipt, $ha)->assertOk()->assertJsonPath('report.status', 'closed')->assertJsonCount(3, 'events')->assertJsonPath('events.1.status', 'in_review')->assertJsonPath('events.2.status', 'closed');
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'in_review'])->assertFailed();
        $this->artisan('reports:status', ['receipt' => $receipt, 'status' => 'removed'])->assertFailed();
        $this->assertDatabaseCount('reports', 1);
        $this->assertDatabaseCount('report_events', 3);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_invalid_submission_stores_no_receipt_or_event(): void
    {
        [$a, $ha] = $this->member('reporter');
        foreach ([['type' => 'secret'], ['target' => str_repeat('x', 41)], ['reason' => 'unsupported'], ['note' => str_repeat('x', 301)]] as $bad) {
            $this->postJson('/api/v1/reports', array_merge(['type' => 'post', 'target' => 'reference', 'reason' => 'spam'], $bad), $ha)->assertUnprocessable();
        }
        $this->assertDatabaseCount('reports', 0);
        $this->assertDatabaseCount('report_events', 0);
    }

    public function test_reporter_deletion_cascades_history_without_affecting_other_owner(): void
    {
        [$a, $ha] = $this->member('reporter');
        [$b, $hb] = $this->member('other');
        foreach ([$ha, $hb] as $headers) $this->postJson('/api/v1/reports', ['type' => 'post', 'target' => 'reference', 'reason' => 'spam'], $headers)->assertCreated();
        $a->delete();
        $this->assertDatabaseCount('reports', 1);
        $this->assertDatabaseCount('report_events', 1);
        $this->getJson('/api/v1/reports', $hb)->assertOk()->assertJsonCount(1, 'data');
    }
}
