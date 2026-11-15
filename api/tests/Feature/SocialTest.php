<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class SocialTest extends TestCase
{
    use RefreshDatabase;

    public function test_profile_search_follow_notifications(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $this->getJson('/api/v1/users/asha', $hb)->assertOk()->assertJsonPath('user.followers_count', 0)->assertJsonPath('user.following', false);
        $this->postJson('/api/v1/users/asha/follow', [], $hb)->assertOk();
        $this->getJson('/api/v1/users/asha', $hb)->assertJsonPath('user.followers_count', 1)->assertJsonPath('user.following', true);
        $this->getJson('/api/v1/users/search?q=as', $hb)->assertOk()->assertJsonPath('users.0.username', 'asha');
        $id = $this->postJson('/api/v1/posts', ['body' => 'hello #tihar'], $ha)->json('post.public_id');
        $this->postJson("/api/v1/posts/$id/like", [], $hb)->assertOk();
        $c = $this->postJson("/api/v1/posts/$id/comments", ['body' => 'nice'], $hb)->json('comment.public_id');
        $r = $this->postJson("/api/v1/posts/$id/comments", ['body' => 'thanks', 'parent_id' => $c], $ha)->assertCreated()->assertJsonPath('comment.parent_id', $c);
        $types = collect($this->getJson('/api/v1/notifications', $ha)->assertOk()->json('data'))->pluck('type')->sort()->values()->all();
        $this->assertSame(['comment', 'follow', 'like'], $types);
        $this->deleteJson('/api/v1/comments/'.$c, [], $hb)->assertOk();
        $this->getJson('/api/v1/posts', $ha)->assertJsonPath('data.0.comments_count', 0);
    }

    public function test_block_hides_posts_and_report_is_stored(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $this->postJson('/api/v1/posts', ['body' => 'hi'], $ha)->assertCreated();
        $this->postJson('/api/v1/users/asha/block', [], $hb)->assertOk();
        $this->getJson('/api/v1/posts', $hb)->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/users/blocked', $hb)->assertJsonCount(1, 'data');
        $this->deleteJson('/api/v1/users/asha/block', [], $hb)->assertOk();
        $this->getJson('/api/v1/posts', $hb)->assertJsonCount(1, 'data');
        $this->postJson('/api/v1/reports', ['type' => 'user', 'target' => 'asha', 'reason' => 'spam'], $hb)->assertCreated();
        $this->assertDatabaseCount('reports', 1);
    }

    public function test_avatar_and_bio(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->patchJson('/api/v1/auth/me', ['bio' => 'Kathmandu'], $ha)->assertOk()->assertJsonPath('user.bio', 'Kathmandu');
        $res = $this->post('/api/v1/auth/me/avatar', ['avatar' => UploadedFile::fake()->image('a.jpg', 50, 50)], $ha + ['Accept' => 'application/json'])->assertOk();
        $this->assertNotNull($res->json('user.avatar_url'));
    }
}
