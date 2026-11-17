<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class HomeBundleTest extends TestCase
{
    use RefreshDatabase;

    public function test_home_parts_equal_their_own_endpoints_and_respect_blocks(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        foreach ([[$a, $ha], [$b, $hb], [$c, $hc]] as [$u, $h]) {
            $this->postJson('/api/v1/posts', ['body' => 'Hello from '.$u->username], $h)->assertCreated();
        }
        $this->postJson('/api/v1/users/bina/block', [], $ha)->assertSuccessful();

        $home = $this->getJson('/api/v1/home', $ha)->assertOk();
        $feed = $this->getJson('/api/v1/posts?kind=post', $ha)->assertOk()->json();
        $stories = $this->getJson('/api/v1/stories', $ha)->assertOk()->json();
        $unread = $this->getJson('/api/v1/notifications/summary', $ha)->assertOk()->json('unread_messages');

        $this->assertSame($feed, $home->json('feed'));
        $this->assertSame($stories, $home->json('stories'));
        $this->assertSame($unread, $home->json('unread_messages'));
        $bodies = array_column($home->json('feed.data'), 'body');
        $this->assertNotContains('Hello from bina', $bodies);
        $this->assertContains('Hello from chandra', $bodies);
        $this->assertStringContainsString('no-store', (string) $home->headers->get('Cache-Control'));
        $this->getJson('/api/v1/home')->assertUnauthorized();
    }
}
