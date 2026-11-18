<?php
namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The timing header must include the work done by authentication, which runs before group middleware. */
class ServerTimingTest extends TestCase
{
    use RefreshDatabase;

    public function test_signed_in_request_counts_the_user_lookup_and_reports_boot_time(): void
    {
        [$u, $h] = $this->member('asha');
        $header = $this->getJson('/api/v1/auth/me', $h)->assertOk()->headers->get('Server-Timing');
        $this->assertMatchesRegularExpression('/app;dur=\d+, db;dur=[\d.]+;desc="(\d+) queries", boot;dur=\d+/', $header);
        preg_match('/desc="(\d+) queries"/', $header, $m);
        $this->assertGreaterThanOrEqual(1, (int) $m[1], 'the authentication user lookup is inside the measured window');
    }

    public function test_unauthenticated_ping_still_reports_zero_queries(): void
    {
        $header = $this->getJson('/api/v1/ping')->assertOk()->headers->get('Server-Timing');
        $this->assertStringContainsString('desc="0 queries"', $header);
    }
}
