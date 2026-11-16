<?php

namespace Tests\Feature;

use App\Models\Comment;
use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CommentPagingTest extends TestCase
{
    use RefreshDatabase;

    public function test_cursor_paging_is_stable_and_delete_reports_unloaded_replies(): void
    {
        [$owner, $headers] = $this->member('asha');
        $post = Post::create(['user_id' => $owner->id, 'kind' => 'post', 'body' => 'Discussion', 'comments_count' => 36]);
        $root = $post->comments()->create(['user_id' => $owner->id, 'body' => 'Root']);
        foreach (range(1, 35) as $i) {
            $post->comments()->create(['user_id' => $owner->id, 'body' => "Reply $i", 'parent_id' => $root->id]);
        }
        $page = $this->getJson("/api/v1/posts/{$post->public_id}/comments", $headers)->assertOk()->assertJsonCount(30, 'data');
        $this->assertSame($root->public_id, $page->json('data.0.public_id'));
        $cursor = $page->json('next_cursor');
        $this->assertNotEmpty($cursor);
        $this->getJson("/api/v1/posts/{$post->public_id}/comments?cursor=".urlencode($cursor), $headers)->assertOk()->assertJsonCount(6, 'data')->assertJsonPath('next_cursor', null);
        $this->deleteJson("/api/v1/comments/{$root->public_id}", [], $headers)->assertOk()->assertJsonPath('deleted_count', 36);
        $this->assertSame(0, Comment::count());
        $this->assertSame(0, $post->fresh()->comments_count);
        $this->getJson("/api/v1/posts/{$post->public_id}/comments?cursor=".urlencode($cursor), $headers)->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/posts/{$post->public_id}/comments", ['body' => 'Late reply', 'parent_id' => $root->public_id], $headers)->assertUnprocessable();
        $this->deleteJson("/api/v1/comments/{$root->public_id}", [], $headers)->assertNotFound();
        $this->assertSame(0, $post->fresh()->comments_count);
    }

    public function test_only_author_or_post_owner_can_delete_and_count_is_exact(): void
    {
        [$owner, $ho] = $this->member('owner');
        [$author, $ha] = $this->member('author');
        [$other, $hx] = $this->member('other');
        $post = Post::create(['user_id' => $owner->id, 'kind' => 'post', 'body' => 'Discussion']);
        $a = $this->postJson("/api/v1/posts/{$post->public_id}/comments", ['body' => 'Root'], $ha)->assertCreated()->json('comment.public_id');
        $b = $this->postJson("/api/v1/posts/{$post->public_id}/comments", ['body' => 'Reply', 'parent_id' => $a], $hx)->assertCreated()->json('comment.public_id');
        $this->deleteJson("/api/v1/comments/$a", [], $hx)->assertForbidden();
        $this->deleteJson("/api/v1/comments/$b", [], $hx)->assertOk()->assertJsonPath('deleted_count', 1);
        $this->assertSame(1, $post->fresh()->comments_count);
        $this->deleteJson("/api/v1/comments/$a", [], $ho)->assertOk()->assertJsonPath('deleted_count', 1);
        $this->assertSame(0, $post->fresh()->comments_count);
    }
}
