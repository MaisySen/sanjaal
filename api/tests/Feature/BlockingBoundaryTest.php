<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Blocking must also hold when a client remembers a direct URL. */
class BlockingBoundaryTest extends TestCase
{
    use RefreshDatabase;

    public function test_direct_post_interactions_are_hidden_both_directions(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $pa = $this->postJson('/api/v1/posts', ['body' => 'A post'], $ha)->json('post.public_id');
        $pb = $this->postJson('/api/v1/posts', ['body' => 'B post'], $hb)->json('post.public_id');
        $this->postJson('/api/v1/users/bina/block', [], $ha)->assertOk();
        foreach ([[$pa, $hb], [$pb, $ha]] as [$id, $h]) {
            $this->getJson("/api/v1/posts/$id", $h)->assertNotFound();
            $this->getJson("/api/v1/posts/$id/comments", $h)->assertNotFound();
            $this->postJson("/api/v1/posts/$id/comments", ['body' => 'blocked'], $h)->assertNotFound();
            $this->postJson("/api/v1/posts/$id/like", [], $h)->assertNotFound();
            $this->postJson("/api/v1/posts/$id/reaction", ['type' => 'love'], $h)->assertNotFound();
            $this->postJson("/api/v1/posts/$id/save", [], $h)->assertNotFound();
            $this->postJson("/api/v1/posts/$id/gifts", ['gift' => 'rose'], $h)->assertNotFound();
        }
        $this->assertDatabaseCount('comments', 0);
        $this->assertDatabaseCount('likes', 0);
        $this->assertDatabaseCount('gifts', 0);
    }

    public function test_contact_block_applies_to_existing_and_new_direct_chats_and_calls(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');
        $this->postJson('/api/v1/users/bina/block', [], $ha)->assertOk();
        foreach ([[$ha, 'bina'], [$hb, 'asha']] as [$h, $u]) {
            $this->postJson("/api/v1/users/$u/follow", [], $h)->assertNotFound();
            $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => $u], $h)->assertNotFound();
            $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Contact bypass', 'usernames' => [$u]], $h)->assertNotFound();
            $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'bypass'], $h)->assertNotFound();
            $this->postJson("/api/v1/conversations/$id/call-token", [], $h)->assertNotFound();
        }
        $this->assertDatabaseCount('messages', 0);
        $this->assertDatabaseCount('calls', 0);
        $this->assertDatabaseCount('follows', 0);
        // Blocking does not destroy a member's own chat history or membership.
        $this->getJson("/api/v1/conversations/$id/messages", $ha)->assertOk();
        $this->deleteJson('/api/v1/users/bina/block', [], $ha)->assertOk();
        $this->postJson("/api/v1/conversations/$id/messages", ['body' => 'after unblock'], $hb)->assertCreated();
    }

    public function test_blocked_comments_replies_notifications_and_self_search_are_filtered(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chitra');
        // Search also matches display names; the factory's random names could contain 'asha' or 'bina' and make this flaky.
        foreach ([[$a, 'Aaa One'], [$b, 'Bbb Two'], [$c, 'Ccc Three']] as [$u, $n]) {
            $u->forceFill(['name' => $n])->save();
        }
        $id = $this->postJson('/api/v1/posts', ['body' => 'A post'], $ha)->json('post.public_id');
        $comment = $this->postJson("/api/v1/posts/$id/comments", ['body' => 'B comment'], $hb)->json('comment.public_id');
        $this->postJson("/api/v1/posts/$id/comments", ['body' => 'C reply', 'parent_id' => $comment], $hc)->assertCreated();
        $this->postJson("/api/v1/posts/$id/like", [], $hb)->assertOk();
        $this->postJson('/api/v1/users/asha/follow', [], $hb)->assertOk();
        $this->postJson('/api/v1/users/bina/block', [], $ha)->assertOk();
        $this->getJson("/api/v1/posts/$id/comments", $ha)->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/posts/$id/comments", ['body' => 'Hidden reply', 'parent_id' => $comment], $ha)->assertUnprocessable();
        $notifications = $this->getJson('/api/v1/notifications', $ha)->assertOk()->json('data');
        $this->assertNotContains('bina', array_column($notifications, 'actor'));
        $this->getJson('/api/v1/users/search?q=asha', $ha)->assertOk()->assertJsonCount(0, 'users');
        $this->getJson('/api/v1/users/search?q=bina', $ha)->assertOk()->assertJsonCount(0, 'users');
        $this->deleteJson("/api/v1/posts/$id", [], $ha)->assertOk();
        $this->getJson('/api/v1/notifications', $ha)->assertOk()->assertJsonCount(0, 'data');
    }
    public function test_block_hides_hosted_rooms_and_stops_join_and_gift(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        config(['services.livekit.url' => 'wss://fixture.invalid', 'services.livekit.key' => 'fixture-key', 'services.livekit.secret' => str_repeat('x', 40)]);
        $id = (string) \Illuminate\Support\Str::uuid();
        DB::table('rooms')->insert(['public_id' => $id, 'host_id' => $a->id, 'title' => 'A room', 'status' => 'live', 'created_at' => now(), 'updated_at' => now()]);
        $this->getJson('/api/v1/rooms', $hb)->assertOk()->assertJsonCount(1, 'data');
        $this->postJson('/api/v1/users/asha/block', [], $hb)->assertOk();
        $this->getJson('/api/v1/rooms', $hb)->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/rooms/$id/join", [], $hb)->assertNotFound();
        $this->postJson("/api/v1/rooms/$id/gifts", ['gift' => 'rose'], $hb)->assertNotFound();
        $this->assertDatabaseCount('gifts', 0);
    }

}
