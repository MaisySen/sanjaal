<?php

namespace Tests\Feature;

use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\Message;
use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Shared-post cards and reply previews of a messages page are read together; the output must match the per-message reads. */
class MessagesPreviewTest extends TestCase
{
    use RefreshDatabase;

    private function mkPost($user, string $body): int
    {
        return DB::table('posts')->insertGetId(['public_id' => (string) \Illuminate\Support\Str::uuid(), 'user_id' => $user->id, 'kind' => 'post', 'body' => $body, 'created_at' => now(), 'updated_at' => now()]);
    }

    private function chat($me, $o): Conversation
    {
        $c = Conversation::create(['type' => 'direct', 'created_by' => $me->id, 'last_message_at' => now(), 'direct_key' => collect([$me, $o])->pluck('id')->sort()->implode(':')]);
        foreach ([$me, $o] as $u) {
            DB::table('conversation_members')->insert(['conversation_id' => $c->id, 'user_id' => $u->id, 'role' => 'member', 'created_at' => now(), 'updated_at' => now()]);
        }

        return $c;
    }

    private function say(Conversation $c, $u, string $body, array $x = []): Message
    {
        return Message::create(['conversation_id' => $c->id, 'user_id' => $u->id, 'body' => $body] + $x);
    }

    private function reads(array $h, string $cid): int
    {
        DB::enableQueryLog(); DB::flushQueryLog();
        $this->getJson("/api/v1/conversations/$cid/messages", $h)->assertOk();
        $n = count(array_filter(DB::getQueryLog(), fn ($q) => str_starts_with(strtolower($q['query']), 'select') && ! str_contains($q['query'], 'personal_access_tokens') && ! str_contains($q['query'], '"auth0_sub"')));
        DB::disableQueryLog();

        return $n;
    }

    public function test_page_matches_per_message_previews_for_live_gone_and_blocked(): void
    {
        [$me, $h] = $this->member('mpme');
        [$o] = $this->member('mpother');
        [$bl] = $this->member('mpblocked');
        $c = $this->chat($me, $o);
        $live = $this->mkPost($o, 'live post');
        $gone = $this->mkPost($o, 'gone post');
        $blockedPost = $this->mkPost($bl, 'blocked author post');
        DB::table('blocks')->insert(['blocker_id' => $me->id, 'blocked_id' => $bl->id, 'created_at' => now()]);
        $m1 = $this->say($c, $o, 'first');
        $m2 = $this->say($c, $me, 'second');
        $gm = $this->say($c, $o, 'will go');
        $this->say($c, $o, 'live share', ['shared_post_id' => $live, 'reply_to_id' => $m1->id]);
        $this->say($c, $o, 'gone share', ['shared_post_id' => $gone, 'reply_to_id' => $gm->id]);
        $this->say($c, $me, 'blocked share', ['shared_post_id' => $blockedPost, 'reply_to_id' => $m2->id]);
        Post::whereKey($gone)->first()?->delete();
        $gm->delete();

        $got = collect($this->getJson("/api/v1/conversations/{$c->public_id}/messages", $h)->assertOk()->json('data'))->keyBy('seq');
        $hidden = Present::hiddenAuthors([$me->id]);
        $expected = Message::with('user', 'conversation')->where('conversation_id', $c->id)->orderBy('id')->get()
            ->map(fn ($m) => json_decode(json_encode(Present::message($m, 0, $hidden)), true))->keyBy('seq');
        $this->assertNotEmpty($expected);
        foreach ($got as $seq => $row) {
            $this->assertEquals($expected[$seq], $row, "message $seq differs from the per-message read");
        }
        $by = $got->keyBy('body');
        $this->assertNotNull($by['live share']['shared_post']);
        $this->assertNotNull($by['live share']['reply_to']);
        $this->assertNull($by['gone share']['shared_post']);
        $this->assertNull($by['blocked share']['shared_post']);
        $this->assertNotNull($by['blocked share']['reply_to']);
    }

    public function test_reads_do_not_grow_with_the_number_of_shares_and_replies(): void
    {
        [$me, $h] = $this->member('mpcount');
        [$o] = $this->member('mpcounto');
        $c = $this->chat($me, $o);
        $make = function (int $n) use ($c, $o) {
            for ($i = 0; $i < $n; $i++) {
                $first = $this->say($c, $o, 'hello '.$i);
                $this->say($c, $o, 'look '.$i, ['shared_post_id' => $this->mkPost($o, 'p'.$i), 'reply_to_id' => $first->id]);
            }
        };
        $make(2);
        $this->getJson("/api/v1/conversations/{$c->public_id}/messages", $h)->assertOk();
        $few = $this->reads($h, $c->public_id);
        $make(15);
        $this->assertSame($few, $this->reads($h, $c->public_id), 'reads must not grow with shares and replies on the page');
    }
}
