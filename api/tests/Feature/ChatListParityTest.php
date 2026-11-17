<?php

namespace Tests\Feature;

use App\Http\Resources\Present;
use App\Models\Conversation;
use App\Models\Message;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The chat list batches the last message, unread count and blocked-author reads. It must return exactly what the
 * older per-chat reads returned (history cut-offs, read marks, deleted messages, shared posts from blocked authors),
 * and the number of reads must not grow with the number of chats.
 */
class ChatListParityTest extends TestCase
{
    use RefreshDatabase;

    private function chat(string $type, array $users, ?string $title = null): Conversation
    {
        $c = Conversation::create(['type' => $type, 'title' => $title, 'created_by' => $users[0]->id, 'last_message_at' => now()->addSeconds(random_int(1, 1000)),
            'direct_key' => $type === 'direct' ? collect($users)->pluck('id')->sort()->implode(':') : null]);
        foreach ($users as $u) {
            DB::table('conversation_members')->insert(['conversation_id' => $c->id, 'user_id' => $u->id, 'role' => 'member', 'created_at' => now(), 'updated_at' => now()]);
        }
        return $c;
    }

    private function say(Conversation $c, $user, string $body, array $extra = []): Message
    {
        return Message::create(['conversation_id' => $c->id, 'user_id' => $user->id, 'body' => $body] + $extra);
    }

    private function legacy(Conversation $c, $me): array
    {
        $c->load('members');
        $pivot = $c->members->firstWhere('id', $me->id)?->pivot;
        $last = $c->messages()->with('user', 'conversation')->where('id', '>', $pivot?->history_from_id ?? 0)->latest('id')->first();
        $unread = $c->messages()->where('id', '>', max($pivot?->last_read_message_id ?? 0, $pivot?->history_from_id ?? 0))->where('user_id', '!=', $me->id)->count();
        return [
            'last' => $last ? json_decode(json_encode(Present::message($last, (int) ($pivot?->history_from_id ?? 0), Present::hiddenAuthors([$me->id]))), true) : null,
            'unread' => $unread,
        ];
    }

    public function test_list_matches_the_per_chat_reads(): void
    {
        [$me, $h] = $this->member('chatme');
        [$a] = $this->member('chata');
        [$b] = $this->member('chatb');
        [$c] = $this->member('chatc');
        [$d] = $this->member('chatd');
        $postId = DB::table('posts')->insertGetId(['public_id' => (string) \Illuminate\Support\Str::uuid(), 'user_id' => $c->id, 'kind' => 'post', 'body' => 'shared body', 'created_at' => now(), 'updated_at' => now()]);

        $empty = $this->chat('direct', [$me, $a]);
        $plain = $this->chat('direct', [$me, $b]);
        $this->say($plain, $b, 'one'); $this->say($plain, $me, 'mine'); $this->say($plain, $b, 'two');
        $group = $this->chat('group', [$me, $a, $b], 'Group');
        $g1 = $this->say($group, $a, 'old'); $g2 = $this->say($group, $b, 'mid'); $this->say($group, $a, 'new');
        DB::table('conversation_members')->where('conversation_id', $group->id)->where('user_id', $me->id)->update(['history_from_id' => $g2->id, 'last_read_message_id' => $g1->id, 'pinned' => true]);
        $cut = $this->chat('group', [$me, $a], 'Cut');
        $this->say($cut, $a, 'before');
        DB::table('conversation_members')->where('conversation_id', $cut->id)->where('user_id', $me->id)->update(['history_from_id' => PHP_INT_MAX >> 8]);
        $deleted = $this->chat('direct', [$me, $c]);
        $d1 = $this->say($deleted, $c, 'keep');
        $d2 = $this->say($deleted, $c, 'gone'); $d2->delete();
        $shared = $this->chat('group', [$me, $a, $c], 'Shared');
        $s1 = $this->say($shared, $a, 'look', ['shared_post_id' => $postId]);
        $archived = $this->chat('direct', [$me, $d]);
        $this->say($archived, $d, 'archived one');
        DB::table('conversation_members')->where('conversation_id', $archived->id)->where('user_id', $me->id)->update(['archived' => true]);
        $all = [$empty, $plain, $group, $cut, $deleted, $shared, $archived];

        foreach ([false, true] as $blocked) {
            if ($blocked) {
                DB::table('blocks')->insert(['blocker_id' => $me->id, 'blocked_id' => $c->id, 'created_at' => now()]);
            }
            foreach ([0, 1] as $archivedFlag) {
                $resp = $this->getJson('/api/v1/conversations'.($archivedFlag ? '?archived=1' : ''), $h)->assertOk()->json('data');
                $byId = collect($resp)->keyBy('public_id');
                $expectedIds = collect($all)->filter(fn ($x) => (bool) DB::table('conversation_members')->where('conversation_id', $x->id)->where('user_id', $me->id)->value('archived') === (bool) $archivedFlag)->pluck('public_id')->sort()->values()->all();
                $this->assertSame($expectedIds, $byId->keys()->sort()->values()->all());
                foreach ($all as $conv) {
                    if (! $byId->has($conv->public_id)) {
                        continue;
                    }
                    $row = $byId[$conv->public_id];
                    $want = $this->legacy($conv->fresh(), $me);
                    $this->assertSame($want['unread'], $row['unread'], $conv->public_id.' unread (blocked='.(int) $blocked.')');
                    $this->assertSame($want['last'], $row['last_message'], $conv->public_id.' last message (blocked='.(int) $blocked.')');
                }
            }
        }
        // The shared post from a blocked author is left out, the plain list still returns the message.
        $row = collect($this->getJson('/api/v1/conversations', $h)->json('data'))->firstWhere('public_id', $shared->public_id);
        $this->assertNull($row['last_message']['shared_post']);
        $this->assertSame('look', $row['last_message']['body']);
    }

    public function test_reads_do_not_grow_with_the_number_of_chats(): void
    {
        [$me, $h] = $this->member('chatcount');
        $count = function () use ($h): int {
            DB::enableQueryLog(); DB::flushQueryLog();
            $this->getJson('/api/v1/conversations', $h)->assertOk();
            $n = count(array_filter(DB::getQueryLog(), fn ($q) => str_starts_with(strtolower($q['query']), 'select') && ! str_contains($q['query'], 'personal_access_tokens') && ! str_contains($q['query'], '"auth0_sub"')));
            DB::disableQueryLog();
            return $n;
        };
        $make = function (int $n) use ($me) {
            for ($i = 0; $i < $n; $i++) {
                [$o] = $this->member('chatother'.$i.'x'.random_int(1000, 9999));
                $chat = $this->chat('direct', [$me, $o]);
                $this->say($chat, $o, 'hello '.$i);
            }
        };
        $make(2);
        $this->getJson('/api/v1/conversations', $h)->assertOk();
        $few = $count();
        $make(8);
        $many = $count();
        $this->assertSame($few, $many, 'reads must not grow with the number of chats');
        $this->assertLessThanOrEqual(8, $many);
    }
}
