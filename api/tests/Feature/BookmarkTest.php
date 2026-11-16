<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BookmarkTest extends TestCase
{
    use RefreshDatabase;

    public function test_save_list_and_unsave_are_private_and_idempotent(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $p1 = $this->postJson('/api/v1/posts', ['body' => 'one'], $ha)->json('post.public_id');
        $p2 = $this->postJson('/api/v1/posts', ['body' => 'two'], $ha)->json('post.public_id');

        $this->postJson("/api/v1/posts/$p1/save", [], $hb)->assertOk()->assertJsonPath('saved', true);
        $this->postJson("/api/v1/posts/$p1/save", [], $hb)->assertOk();
        $this->postJson("/api/v1/posts/$p2/save", [], $hb)->assertOk();
        $this->assertSame(2, \DB::table('bookmarks')->count());

        // Newest save first, flagged saved; the author and other people see their own state only.
        $this->getJson('/api/v1/saved', $hb)->assertOk()->assertJsonCount(2, 'data')->assertJsonPath('data.0.body', 'two')->assertJsonPath('data.0.saved', true);
        $this->getJson('/api/v1/saved', $ha)->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/posts/$p1", $hb)->assertJsonPath('post.saved', true);
        $this->getJson("/api/v1/posts/$p1", $ha)->assertJsonPath('post.saved', false);
        $feed = $this->getJson('/api/v1/posts', $hb)->assertOk()->json('data');
        $this->assertSame([true, true], array_column($feed, 'saved'));

        $this->deleteJson("/api/v1/posts/$p1/save", [], $hb)->assertOk()->assertJsonPath('saved', false);
        $this->deleteJson("/api/v1/posts/$p1/save", [], $hb)->assertOk();
        $this->getJson('/api/v1/saved', $hb)->assertJsonCount(1, 'data');
        $this->postJson('/api/v1/posts/'.\Illuminate\Support\Str::uuid().'/save', [], $hb)->assertNotFound();
    }

    public function test_blocked_authors_cannot_be_saved_and_drop_out_of_the_list(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $p = $this->postJson('/api/v1/posts', ['body' => 'hello'], $ha)->json('post.public_id');
        $this->postJson("/api/v1/posts/$p/save", [], $hb)->assertOk();
        \DB::table('blocks')->insert(['blocker_id' => $b->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->getJson('/api/v1/saved', $hb)->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/posts/$p/save", [], $hb)->assertNotFound();
    }

    public function test_deleting_a_post_removes_its_bookmarks(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $p = $this->postJson('/api/v1/posts', ['body' => 'gone soon'], $ha)->json('post.public_id');
        $this->postJson("/api/v1/posts/$p/save", [], $hb)->assertOk();
        $this->deleteJson("/api/v1/posts/$p", [], $ha)->assertOk();
        $this->getJson('/api/v1/saved', $hb)->assertJsonCount(0, 'data');
    }

    public function test_requires_sign_in(): void
    {
        $this->getJson('/api/v1/saved')->assertUnauthorized();
    }
}
