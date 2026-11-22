<?php

namespace Tests\Feature;

use App\Models\Conversation;
use App\Models\Message;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class StoryReplyTest extends TestCase
{
    use RefreshDatabase;

    private function fixture(string $audience = 'followers'): array
    {
        [$owner, $ha] = $this->member('owner');
        [$reader, $hb] = $this->member('reader');
        $reader->following()->attach($owner->id);
        $id = (string) Str::uuid();
        DB::table('stories')->insert(['public_id' => $id, 'user_id' => $owner->id, 'media_id' => (string) Str::uuid(), 'media_mime' => 'image/jpeg', 'protected_media' => true, 'audience' => $audience, 'caption' => 'Private caption must not copy', 'expires_at' => now()->addHour(), 'created_at' => now(), 'updated_at' => now()]);

        return [$owner, $reader, $ha, $hb, $id];
    }

    public function test_reply_creates_only_text_in_stable_owner_chat_and_retries_once(): void
    {
        [$a, $b, $ha, $hb, $id] = $this->fixture();
        $a->update(['username' => 'renamed_owner']);
        $body = ['body' => 'Wonderful view', 'client_id' => (string) Str::uuid()];
        $first = $this->postJson("/api/v1/stories/$id/reply", $body, $hb)->assertCreated();
        $first->assertJsonPath('message.kind', 'storyreply')->assertJsonPath('message.body', 'Wonderful view')->assertJsonPath('message.media_url', null)->assertJsonPath('message.shared_post', null);
        $this->assertStringNotContainsString('Private caption', $first->getContent());
        $this->assertStringNotContainsString('/media', $first->getContent());
        $this->assertSame(0, DB::table('media_blobs')->count());
        $this->assertSame(1, Message::count());
        $c = Conversation::first();
        $this->assertTrue($c->hasMember($a) && $c->hasMember($b));
        DB::table('stories')->where('public_id', $id)->update(['expires_at' => now()->subSecond()]);
        $this->postJson("/api/v1/stories/$id/reply", $body, $hb)->assertOk()->assertJsonPath('message.public_id', $first->json('message.public_id'));
        $this->assertSame(1, Message::count());
        $this->getJson('/api/v1/conversations/'.$c->public_id.'/messages', $ha)->assertOk()->assertJsonPath('data.0.kind', 'storyreply');
    }

    public function test_expired_deleted_hidden_nonfollower_and_own_stories_do_not_create_chats(): void
    {
        [$a, $b, $ha, $hb, $id] = $this->fixture();
        $route = "/api/v1/stories/$id/reply";
        $body = ['body' => 'Hello', 'client_id' => (string) Str::uuid()];
        $this->postJson($route, $body)->assertUnauthorized();
        $this->postJson($route, $body, $ha)->assertNotFound();
        $b->following()->detach($a->id);
        $this->postJson($route, $body, $hb)->assertNotFound();
        $b->following()->attach($a->id);
        DB::table('story_relationships')->insert(['owner_id' => $a->id, 'member_id' => $b->id, 'hide_story' => true, 'close_friend' => false, 'revision' => 1, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson($route, $body, $hb)->assertNotFound();
        DB::table('story_relationships')->where('owner_id', $a->id)->update(['hide_story' => false]);
        DB::table('stories')->where('public_id', $id)->update(['expires_at' => now()->subSecond()]);
        $this->postJson($route, $body, $hb)->assertNotFound();
        DB::table('stories')->where('public_id', $id)->delete();
        $this->postJson($route, $body, $hb)->assertNotFound();
        $this->assertSame(0, Message::count());
        $this->assertSame(0, Conversation::count());
    }

    public function test_close_friend_revocation_and_both_block_directions_reject_send_and_replay(): void
    {
        [$a, $b, $ha, $hb, $id] = $this->fixture('close_friends');
        $route = "/api/v1/stories/$id/reply";
        $body = ['body' => 'Hello', 'client_id' => (string) Str::uuid()];
        $this->postJson($route, $body, $hb)->assertNotFound();
        DB::table('story_relationships')->insert(['owner_id' => $a->id, 'member_id' => $b->id, 'hide_story' => false, 'close_friend' => true, 'revision' => 1, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson($route, $body, $hb)->assertCreated();
        DB::table('story_relationships')->where('owner_id', $a->id)->update(['close_friend' => false]);
        $this->postJson($route, ['body' => 'Again', 'client_id' => (string) Str::uuid()], $hb)->assertNotFound();
        foreach ([[$a->id, $b->id], [$b->id, $a->id]] as [$blocker, $blocked]) {
            DB::table('blocks')->insert(['blocker_id' => $blocker, 'blocked_id' => $blocked, 'created_at' => now(), 'updated_at' => now()]);
            $this->postJson($route, $body, $hb)->assertNotFound();
            DB::table('blocks')->delete();
        }
        $this->assertSame(1, Message::count());
    }

    public function test_replay_key_is_scoped_to_story_and_old_history_is_not_returned(): void
    {
        [$a, $b, $ha, $hb, $id] = $this->fixture();
        $body = ['body' => 'Hello', 'client_id' => str_repeat('a', 48)];
        $this->postJson("/api/v1/stories/$id/reply", $body, $hb)->assertCreated()->assertJsonPath('message.client_id', $body['client_id']);
        $original = DB::table('stories')->where('public_id', $id)->first();
        $otherId = (string) Str::uuid();
        $second = (array) $original;
        unset($second['id']);
        $second['public_id'] = $otherId;
        DB::table('stories')->insert($second);
        $this->postJson("/api/v1/stories/$otherId/reply", $body, $hb)->assertCreated();
        $this->assertSame(2, Message::count());
        $this->assertSame(1, Conversation::count());
        $convo = Conversation::first();
        $convo->members()->updateExistingPivot($b->id, ['history_from_id' => Message::max('id')]);
        $this->postJson("/api/v1/stories/$id/reply", $body, $hb)->assertGone();
        $this->assertSame(2, Message::count());
    }

    public function test_validation_and_soft_removed_replay_never_resend(): void
    {
        [$a, $b, $ha, $hb, $id] = $this->fixture();
        $route = "/api/v1/stories/$id/reply";
        foreach ([[], ['body' => '   ', 'client_id' => (string) Str::uuid()], ['body' => 'Hi', 'client_id' => 'invalid'], ['body' => str_repeat('x', 4001), 'client_id' => (string) Str::uuid()]] as $body) {
            $this->postJson($route, $body, $hb)->assertUnprocessable();
        }
        $body = ['body' => 'Hello', 'client_id' => (string) Str::uuid()];
        $this->postJson($route, $body, $hb)->assertCreated();
        Message::first()->delete();
        $this->postJson($route, $body, $hb)->assertGone();
        $this->assertSame(1, Message::withTrashed()->count());
    }
}
