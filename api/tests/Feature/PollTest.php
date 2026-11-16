<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class PollTest extends TestCase
{
    use RefreshDatabase;

    public function test_create_vote_replace_remove_and_private_aggregate(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chitra');
        $id = $this->postJson('/api/v1/posts', ['body' => 'Meetup day?', 'poll_options' => ['Saturday', 'Sunday']], $ha)
            ->assertCreated()->assertJsonPath('post.kind', 'post')->assertJsonPath('post.poll.total_votes', 0)->json('post.public_id');
        $url = "/api/v1/posts/$id/poll/vote";
        $this->postJson($url, ['choice' => 0], $hb)->assertOk()->assertJsonPath('poll.total_votes', 1)->assertJsonPath('poll.my_choice', 0);
        $this->postJson($url, ['choice' => 0], $hb)->assertOk()->assertJsonPath('poll.total_votes', 1);
        $this->postJson($url, ['choice' => 1], $hb)->assertOk()->assertJsonPath('poll.options.0.votes', 0)->assertJsonPath('poll.options.1.votes', 1);
        $this->postJson($url, ['choice' => 0], $hc)->assertOk()->assertJsonPath('poll.total_votes', 2);
        $poll = $this->getJson('/api/v1/posts', $ha)->assertOk()->assertJsonPath('data.0.poll.my_choice', null)->json('data.0.poll');
        $this->assertSame(['options', 'total_votes', 'my_choice'], array_keys($poll));
        $this->assertSame(['choice', 'text', 'votes'], array_keys($poll['options'][0]));
        $this->getJson("/api/v1/posts/$id", $hb)->assertJsonPath('post.poll.my_choice', 1);
        $this->deleteJson($url, [], $hb)->assertOk()->assertJsonPath('poll.my_choice', null)->assertJsonPath('poll.total_votes', 1);
        $this->deleteJson($url, [], $hb)->assertOk()->assertJsonPath('poll.total_votes', 1);
        $this->assertDatabaseCount('poll_votes', 1);
    }

    public function test_invalid_options_question_kind_and_choice_are_rejected(): void
    {
        [$a, $ha] = $this->member('asha');
        foreach ([[], ['One'], ['A', 'B', 'C', 'D', 'E'], ['A', ' a '], ['A', ' '], ['A', str_repeat('x', 81)]] as $options) {
            $this->postJson('/api/v1/posts', ['body' => 'Question?', 'poll_options' => $options], $ha)->assertUnprocessable();
        }
        $this->postJson('/api/v1/posts', ['poll_options' => ['A', 'B']], $ha)->assertUnprocessable();
        $this->postJson('/api/v1/posts', ['kind' => 'reel', 'body' => 'Question?', 'poll_options' => ['A', 'B']], $ha)->assertUnprocessable();
        $id = $this->postJson('/api/v1/posts', ['body' => 'Question?', 'poll_options' => ['A', 'B']], $ha)->json('post.public_id');
        foreach ([-1, 2, 4, 'x'] as $choice) $this->postJson("/api/v1/posts/$id/poll/vote", ['choice' => $choice], $ha)->assertUnprocessable();
        $this->assertDatabaseCount('poll_votes', 0);
    }

    public function test_block_deleted_nonpoll_and_unauthenticated_access(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/posts', ['body' => 'Question?', 'poll_options' => ['A', 'B']], $ha)->json('post.public_id');
        $url = "/api/v1/posts/$id/poll/vote";
        $this->postJson($url, ['choice' => 0])->assertUnauthorized();
        $this->postJson($url, ['choice' => 0], $hb)->assertOk();
        DB::table('blocks')->insert(['blocker_id' => $b->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson($url, ['choice' => 1], $hb)->assertNotFound();
        $this->getJson("/api/v1/posts/$id", $hb)->assertNotFound();
        $this->getJson('/api/v1/posts', $hb)->assertJsonCount(0, 'data');
        $this->deleteJson("/api/v1/posts/$id", [], $ha)->assertOk();
        $this->assertDatabaseCount('poll_votes', 0);
        $this->postJson($url, ['choice' => 0], $ha)->assertNotFound();
        $plain = $this->postJson('/api/v1/posts', ['body' => 'Plain post'], $ha)->json('post.public_id');
        $this->postJson("/api/v1/posts/$plain/poll/vote", ['choice' => 0], $ha)->assertNotFound();
    }
    public function test_capability_media_exclusion_and_batch_poll_query(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->getJson('/api/v1/auth/me', $ha)->assertOk()->assertJsonPath('features.polls', true);
        $this->postJson('/api/v1/posts', ['body' => 'Question?', 'poll_options' => ['A', 'B'], 'media' => [\Illuminate\Http\UploadedFile::fake()->image('pic.jpg')]], $ha)->assertUnprocessable();
        $this->assertDatabaseCount('posts', 0);
        for ($i = 0; $i < 15; $i++) {
            $this->postJson('/api/v1/posts', ['body' => "Question $i?", 'poll_options' => ['A', 'B']], $ha)->assertCreated();
        }
        DB::enableQueryLog();
        $this->getJson('/api/v1/posts', $ha)->assertOk()->assertJsonCount(15, 'data');
        $pollQueries = collect(DB::getQueryLog())->filter(fn ($q) => str_contains($q['query'], 'poll_votes'));
        DB::disableQueryLog();
        $this->assertCount(1, $pollQueries, 'Poll aggregate must load once per page, not per post.');
    }

}
