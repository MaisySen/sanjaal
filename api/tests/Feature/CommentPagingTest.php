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

    public function test_reply_parent_ids_are_read_together_and_a_deleted_parent_stays_null(): void
    {
        [$owner, $headers] = $this->member('parentread');
        $post = Post::create(['user_id' => $owner->id, 'kind' => 'post', 'body' => 'Threads', 'comments_count' => 0]);
        $a = $post->comments()->create(['user_id' => $owner->id, 'body' => 'A']);
        $b = $post->comments()->create(['user_id' => $owner->id, 'body' => 'B']);
        $DB = \Illuminate\Support\Facades\DB::class;
        $count = function () use ($post, $headers, $DB): int {
            $DB::enableQueryLog(); $DB::flushQueryLog();
            $this->getJson("/api/v1/posts/{$post->public_id}/comments", $headers)->assertOk();
            $n = count(array_filter($DB::getQueryLog(), fn ($q) => str_starts_with(strtolower($q['query']), 'select') && ! str_contains($q['query'], 'personal_access_tokens') && ! str_contains($q['query'], '"auth0_sub"')));
            $DB::disableQueryLog();
            return $n;
        };
        $post->comments()->create(['user_id' => $owner->id, 'body' => 'to A 1', 'parent_id' => $a->id]);
        $post->comments()->create(['user_id' => $owner->id, 'body' => 'to B 1', 'parent_id' => $b->id]);
        $this->getJson("/api/v1/posts/{$post->public_id}/comments", $headers)->assertOk();
        $few = $count();
        foreach (range(2, 12) as $i) {
            $post->comments()->create(['user_id' => $owner->id, 'body' => "to A $i", 'parent_id' => $a->id]);
            $post->comments()->create(['user_id' => $owner->id, 'body' => "to B $i", 'parent_id' => $b->id]);
        }
        $this->assertSame($few, $count(), 'reply parents must not cost one read each');
        $r = $this->getJson("/api/v1/posts/{$post->public_id}/comments", $headers)->assertOk();
        $byBody = collect($r->json('data'))->keyBy('body');
        $this->assertSame($a->public_id, $byBody['to A 3']['parent_id']);
        $this->assertSame($b->public_id, $byBody['to B 7']['parent_id']);
        $this->assertNull($byBody['A']['parent_id']);
        // Parent removed on its own (children kept): the reply is still listed and no longer names a parent, as before.
        $b->delete();
        $after = collect($this->getJson("/api/v1/posts/{$post->public_id}/comments", $headers)->assertOk()->json('data'));
        $this->assertTrue($after->where('body', 'to B 7')->every(fn ($c) => $c['parent_id'] === null) || $after->where('body', 'to B 7')->isEmpty());
    }
}
