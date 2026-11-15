<?php

namespace Tests\Feature;

use Tests\TestCase;

class SecurityHeadersTest extends TestCase
{
    public function test_headers_present_and_no_open_cors(): void
    {
        $r = $this->getJson('/api/does-not-exist', ['Origin' => 'https://evil.example']);
        $r->assertHeader('X-Content-Type-Options', 'nosniff');
        $r->assertHeader('Referrer-Policy', 'no-referrer');
        $r->assertHeader('Strict-Transport-Security');
        $this->assertNull($r->headers->get('X-Powered-By'));
        $this->assertNotSame('*', $r->headers->get('Access-Control-Allow-Origin'));
    }
}
