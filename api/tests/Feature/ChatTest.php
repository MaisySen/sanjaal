<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class ChatTest extends TestCase
{
    use RefreshDatabase;

    public function test_direct_chat_send_and_poll(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');
        // Same pair returns the same conversation.
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'asha'], $hb)->assertOk()->assertJsonPath('conversation.public_id', $cid);

        $m1 = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'namaste', 'client_id' => 'c1'], $ha)->assertCreated()->json('message.seq');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'k xa', 'client_id' => 'c2'], $hb)->assertCreated();

        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonCount(2, 'data');
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=$m1", $ha)->assertJsonCount(1, 'data')->assertJsonPath('data.0.body', 'k xa');
        $this->getJson('/api/v1/conversations', $ha)->assertJsonPath('data.0.unread', 1)->assertJsonPath('data.0.title', $b->name);
        $this->getJson('/api/v1/notifications/summary', $ha)->assertOk()->assertJsonPath('unread_messages', 1);
        $this->postJson("/api/v1/conversations/$cid/read", [], $ha)->assertOk();
        $this->getJson('/api/v1/conversations', $ha)->assertJsonPath('data.0.unread', 0);
        $this->getJson('/api/v1/notifications/summary', $ha)->assertJsonPath('unread_messages', 0);
    }

    private function group(array $headers, array $usernames, string $title = 'Trek'): string
    {
        return $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => $title, 'usernames' => $usernames], $headers)->assertCreated()->json('conversation.public_id');
    }

    public function test_group_add_members_by_a_member_only(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $this->member('dipesh');
        $cid = $this->group($ha, ['bina']);

        // An outsider can neither add anyone nor see the group.
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['dipesh']], $hc)->assertNotFound();
        $this->assertSame(2, \DB::table('conversation_members')->count());
        // A member adds two people; adding someone who is already in is a no-op.
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra', 'bina', 'dipesh']], $hb)->assertOk()->assertJsonCount(4, 'conversation.members');
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $hb)->assertOk()->assertJsonCount(4, 'conversation.members');
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertOk();
    }

    public function test_group_add_with_an_unknown_name_writes_nothing(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $this->member('chandra');
        $cid = $this->group($ha, ['bina']);
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra', 'nobody_here']], $ha)->assertStatus(422);
        $this->assertSame(2, \DB::table('conversation_members')->count());
    }

    public function test_group_add_skips_people_blocked_either_way(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        [$d, $hd] = $this->member('dipesh');
        $cid = $this->group($ha, ['bina']);
        \DB::table('blocks')->insert(['blocker_id' => $a->id, 'blocked_id' => $c->id, 'created_at' => now(), 'updated_at' => now()]);
        \DB::table('blocks')->insert(['blocker_id' => $d->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra', 'dipesh']], $ha)->assertOk()->assertJsonCount(2, 'conversation.members');
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertNotFound();
        $this->getJson("/api/v1/conversations/$cid/messages", $hd)->assertNotFound();
    }

    public function test_new_members_do_not_see_earlier_messages(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->group($ha, ['bina']);
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'before', 'client_id' => 'x1'], $ha)->assertCreated();
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $ha)->assertOk();

        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/conversations', $hc)->assertJsonPath('data.0.last_message', null)->assertJsonPath('data.0.unread', 0);
        $this->getJson('/api/v1/notifications/summary', $hc)->assertJsonPath('unread_messages', 0);

        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'after', 'client_id' => 'x2'], $hb)->assertCreated();
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertJsonCount(1, 'data')->assertJsonPath('data.0.body', 'after');
        $this->getJson('/api/v1/conversations', $hc)->assertJsonPath('data.0.unread', 1);
        // Existing members keep the whole history.
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonCount(2, 'data');
    }

    public function test_earlier_media_and_quoted_replies_do_not_reach_a_new_member(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->group($ha, ['bina']);
        $img = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('p.jpg', 30, 30)], $ha)->assertCreated();
        $imgId = $img->json('message.public_id');
        $mediaUrl = $img->json('message.media_url');
        $old = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'private plan from before', 'client_id' => 'o1'], $ha)->assertCreated()->json('message.public_id');
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $ha)->assertOk();

        // The earlier photo and text are not in the new member's list, last message or live feed.
        $list = $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertOk()->assertJsonCount(0, 'data');
        $this->assertStringNotContainsString($mediaUrl, $list->getContent());
        $this->assertStringNotContainsString('private plan', $this->getJson('/api/v1/conversations', $hc)->getContent());

        // An old member replies to the old message: bina sees the quote, chandra does not.
        $r = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'agreed', 'reply_to' => $old, 'client_id' => 'r1'], $hb)->assertCreated();
        $this->assertSame('private plan from before', $r->json('message.reply_to.body'));
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonPath('data.2.reply_to.body', 'private plan from before');
        $forC = $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertJsonCount(1, 'data')->assertJsonPath('data.0.reply_to', null);
        $this->assertStringNotContainsString('private plan', $forC->getContent());
        $this->assertStringNotContainsString('private plan', $this->getJson('/api/v1/conversations', $hc)->getContent());
        // The one live payload all members receive leaves the quote out too.
        $msg = \App\Models\Message::where('client_id', 'r1')->first();
        $payload = json_encode((new \App\Events\MessageSent($msg))->broadcastWith());
        $this->assertStringNotContainsString('private plan', $payload);

        // The new member cannot quote or probe an earlier message.
        $q = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'what plan?', 'reply_to' => $old, 'client_id' => 'q1'], $hc)->assertCreated();
        $this->assertNull($q->json('message.reply_to'));
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'x', 'reply_to' => $imgId, 'client_id' => 'q2'], $hc)->assertCreated()->assertJsonPath('message.reply_to', null);
        // A removed member cannot read, fetch the live channel, or post.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hc)->assertOk();
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'still here?', 'client_id' => 'q3'], $hc)->assertNotFound();
    }

    public function test_chat_media_needs_sign_in_and_current_membership(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        [$d, $hd] = $this->member('dipesh');
        $cid = $this->group($ha, ['bina']);
        $first = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('a.jpg', 30, 30)], $ha)->assertCreated();
        $url = $first->json('message.media_url');
        $this->assertStringContainsString("/conversations/$cid/messages/", $url);
        $this->assertStringEndsWith('/media', $url);
        $path = parse_url($url, PHP_URL_PATH);
        $rawId = \DB::table('messages')->where('public_id', $first->json('message.public_id'))->value('media_id');

        // Members can fetch it; nobody without a token can; an outsider cannot; the old public address no longer works.
        $this->get($path, $ha)->assertOk()->assertHeader('Cache-Control', 'no-store, private');
        $this->get($path, $hb)->assertOk();
        $this->getJson($path)->assertUnauthorized();
        $this->get($path, $hc)->assertNotFound();
        $this->get("/api/v1/media/$rawId")->assertNotFound();
        // A message from a different conversation cannot be reached through this one.
        $other = $this->group($hb, ['dipesh'], 'Other');
        $this->get("/api/v1/conversations/$other/messages/".$first->json('message.public_id').'/media', $hb)->assertNotFound();

        // Joined later: the earlier photo stays closed, a later one opens.
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $ha)->assertOk();
        $this->get($path, $hc)->assertNotFound();
        $later = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('b.jpg', 30, 30)], $ha)->assertCreated();
        $laterPath = parse_url($later->json('message.media_url'), PHP_URL_PATH);
        $this->get($laterPath, $hc)->assertOk();
        // Removed: access ends at once, including for photos that were open to them.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hc)->assertOk();
        $this->get($laterPath, $hc)->assertNotFound();
        // Text-only messages have no media route.
        $txt = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi', 'client_id' => 't1'], $ha)->assertCreated()->json('message');
        $this->assertNull($txt['media_url']);
        $this->get("/api/v1/conversations/$cid/messages/{$txt['public_id']}/media", $ha)->assertNotFound();
    }

    public function test_the_live_channel_payload_carries_no_content(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->group($ha, ['bina']);
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'secret words', 'client_id' => 'e1'], $ha)->assertCreated();
        $payload = (new \App\Events\MessageSent(\App\Models\Message::where('client_id', 'e1')->firstOrFail()))->broadcastWith();
        $this->assertSame(['seq', 'conversation_id'], array_keys($payload['message']));
        $this->assertStringNotContainsString('secret', json_encode($payload));
    }

    public function test_sharing_a_post_into_a_chat(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $post = $this->postJson('/api/v1/posts', ['body' => 'Sunrise over Phewa lake'], $hc)->assertCreated()->json('post.public_id');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');

        $sent = $this->postJson("/api/v1/conversations/$cid/messages", ['shared_post' => $post, 'client_id' => 's1'], $ha)->assertCreated();
        $sent->assertJsonPath('message.kind', 'post')->assertJsonPath('message.shared_post.public_id', $post)->assertJsonPath('message.shared_post.author.username', 'chandra');
        $list = $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonPath('data.0.shared_post.excerpt', 'Sunrise over Phewa lake');
        $this->getJson('/api/v1/conversations', $hb)->assertJsonPath('data.0.last_message.shared_post.public_id', $post);

        // Someone who has blocked the author sees no preview, only that a post was shared.
        \DB::table('blocks')->insert(['blocker_id' => $b->id, 'blocked_id' => $c->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonPath('data.0.shared_post', null);
        $this->assertStringNotContainsString('Phewa', $this->getJson('/api/v1/conversations', $hb)->getContent());
        \DB::table('blocks')->delete();

        // A sender cannot share a post by someone blocked either way, a missing post, or nothing at all.
        \DB::table('blocks')->insert(['blocker_id' => $c->id, 'blocked_id' => $a->id, 'created_at' => now(), 'updated_at' => now()]);
        $this->postJson("/api/v1/conversations/$cid/messages", ['shared_post' => $post, 'client_id' => 's2'], $ha)->assertStatus(422);
        \DB::table('blocks')->delete();
        $this->postJson("/api/v1/conversations/$cid/messages", ['shared_post' => (string) \Illuminate\Support\Str::uuid(), 'client_id' => 's3'], $ha)->assertStatus(422);
        $this->postJson("/api/v1/conversations/$cid/messages", ['client_id' => 's4'], $ha)->assertStatus(422);

        // The author deleting the post removes the preview.
        $this->deleteJson("/api/v1/posts/$post", [], $hc)->assertOk();
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonPath('data.0.shared_post', null);
    }

    public function test_group_capacity_is_fifty(): void
    {
        [$a, $ha] = $this->member('asha');
        $names = [];
        for ($i = 1; $i <= 49; $i++) {
            $this->member("user$i");
            $names[] = "user$i";
        }
        $this->member('extra');
        $this->member('extra2');
        $cid = $this->group($ha, $names);
        $this->assertSame(50, \DB::table('conversation_members')->count());
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['extra']], $ha)->assertStatus(422);
        $this->assertSame(50, \DB::table('conversation_members')->count());
        // One leaves, then exactly one more fits, and the second does not.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $this->hdr('user1'))->assertOk();
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['extra', 'extra2']], $ha)->assertStatus(422);
        $this->assertSame(49, \DB::table('conversation_members')->count());
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['extra']], $ha)->assertOk();
        $this->assertSame(50, \DB::table('conversation_members')->count());
    }

    public function test_only_the_owner_renames_a_group(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->group($ha, ['bina']);

        $this->patchJson("/api/v1/conversations/$cid", ['title' => '  Dashain   plans '], $ha)->assertOk()->assertJsonPath('conversation.title', 'Dashain plans');
        $this->assertSame('owner', $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Dashain plans'], $ha)->json('conversation.my_role'));
        $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Mine now'], $hb)->assertForbidden();
        $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Nope'], $hc)->assertNotFound();
        $this->patchJson("/api/v1/conversations/$cid", ['title' => '   '], $ha)->assertStatus(422);
        $this->patchJson("/api/v1/conversations/$cid", ['title' => str_repeat('x', 81)], $ha)->assertStatus(422);
        $this->assertSame('Dashain plans', \DB::table('conversations')->value('title'));
        // After the owner leaves, the promoted member can rename.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $ha)->assertOk();
        $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Bina runs it'], $hb)->assertOk()->assertJsonPath('conversation.title', 'Bina runs it');
        // A direct chat has no name to change.
        $direct = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'chandra'], $hb)->json('conversation.public_id');
        $this->patchJson("/api/v1/conversations/$direct", ['title' => 'x'], $hb)->assertStatus(422);
    }

    public function test_only_the_owner_removes_a_member_and_the_removed_member_loses_access(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        [$d, $hd] = $this->member('dipesh');
        $cid = $this->group($ha, ['bina', 'chandra']);
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'before', 'client_id' => 'r1'], $hb)->assertCreated();

        // A plain member cannot remove anyone, including the owner; an outsider sees nothing.
        $this->deleteJson("/api/v1/conversations/$cid/members/chandra", [], $hb)->assertForbidden();
        $this->deleteJson("/api/v1/conversations/$cid/members/asha", [], $hb)->assertForbidden();
        $this->deleteJson("/api/v1/conversations/$cid/members/chandra", [], $hd)->assertNotFound();
        $this->assertSame(3, \DB::table('conversation_members')->count());
        // The owner cannot remove themself or a person who is not in the group.
        $this->deleteJson("/api/v1/conversations/$cid/members/asha", [], $ha)->assertStatus(422);
        $this->deleteJson("/api/v1/conversations/$cid/members/dipesh", [], $ha)->assertNotFound();
        $this->assertSame(3, \DB::table('conversation_members')->count());

        $r = $this->deleteJson("/api/v1/conversations/$cid/members/chandra", [], $ha)->assertOk();
        $this->assertSame(['asha', 'bina'], collect($r->json('conversation.members'))->pluck('username')->sort()->values()->all());
        // The removed member no longer reads, sends or sees the chat; the others keep their messages.
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'still here?', 'client_id' => 'r2'], $hc)->assertNotFound();
        $this->assertSame([], collect($this->getJson('/api/v1/conversations', $hc)->json('data'))->pluck('public_id')->all());
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertOk()->assertJsonCount(1, 'data');
        // Removing twice is not repeated, and a direct chat has no member list.
        $this->deleteJson("/api/v1/conversations/$cid/members/chandra", [], $ha)->assertNotFound();
        $direct = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->deleteJson("/api/v1/conversations/$direct/members/bina", [], $ha)->assertStatus(422);
    }

    public function test_owner_hands_the_group_to_a_chosen_member(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        [$d, $hd] = $this->member('dipesh');
        $cid = $this->group($ha, ['bina', 'chandra']);

        // Only the owner can hand over; the target must be another member; direct chats have no owner.
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'chandra'], $hb)->assertForbidden();
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'chandra'], $hd)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'dipesh'], $ha)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'asha'], $ha)->assertStatus(422);
        $this->postJson("/api/v1/conversations/$cid/owner", [], $ha)->assertStatus(422);
        $this->assertSame('owner', \DB::table('conversation_members')->where('user_id', $a->id)->value('role'));

        $r = $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'chandra'], $ha)->assertOk();
        $this->assertSame('member', $r->json('conversation.my_role'));
        $this->assertSame('owner', \DB::table('conversation_members')->where('user_id', $c->id)->value('role'));
        $this->assertSame('member', \DB::table('conversation_members')->where('user_id', $a->id)->value('role'));
        $this->assertSame(1, \DB::table('conversation_members')->where('role', 'owner')->count());
        // The old owner can no longer rename, remove or hand over; the new owner can.
        $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Mine'], $ha)->assertForbidden();
        $this->deleteJson("/api/v1/conversations/$cid/members/bina", [], $ha)->assertForbidden();
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'bina'], $ha)->assertForbidden();
        $this->patchJson("/api/v1/conversations/$cid", ['title' => 'Chandra runs it'], $hc)->assertOk();
        // Handing back works; the former owner leaving no longer changes who owns it.
        $this->postJson("/api/v1/conversations/$cid/owner", ['username' => 'asha'], $hc)->assertOk();
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hb)->assertOk();
        $this->assertSame('owner', \DB::table('conversation_members')->where('user_id', $a->id)->value('role'));
        $direct = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'dipesh'], $ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$direct/owner", ['username' => 'dipesh'], $ha)->assertStatus(422);
    }

    public function test_owner_chooses_who_can_add_people_and_existing_groups_keep_today_s_behaviour(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        [$d, $hd] = $this->member('dipesh');
        [$e, $he] = $this->member('esha');
        $cid = $this->group($ha, ['bina']);
        $url = "/api/v1/conversations/$cid";

        // A group made before the setting existed (row without the value) behaves as it always did: any member can add.
        $this->assertSame('members', \DB::table('conversations')->where('public_id', $cid)->value('add_policy'));
        $this->postJson("$url/members", ['usernames' => ['chandra']], $hb)->assertOk();

        // Only the owner changes it, to a known value, in a group.
        $this->patchJson("$url/add-policy", ['add_policy' => 'owner'], $hb)->assertForbidden();
        $this->patchJson("$url/add-policy", ['add_policy' => 'owner'], $hd)->assertNotFound();
        $this->patchJson("$url/add-policy", ['add_policy' => 'everyone'], $ha)->assertStatus(422);
        $this->patchJson("$url/add-policy", [], $ha)->assertStatus(422);
        $this->assertSame('members', \DB::table('conversations')->where('public_id', $cid)->value('add_policy'));
        $this->patchJson("$url/add-policy", ['add_policy' => 'owner'], $ha)->assertOk()->assertJsonPath('conversation.add_policy', 'owner');

        // Under owner-only, a member cannot add (nothing is added), the owner still can.
        $this->postJson("$url/members", ['usernames' => ['dipesh']], $hb)->assertForbidden();
        $this->assertSame(3, \DB::table('conversation_members')->count());
        $this->postJson("$url/members", ['usernames' => ['dipesh']], $ha)->assertOk();
        // Hand-over moves the right with the role: the old owner can no longer add, the new owner can.
        $this->postJson("$url/owner", ['username' => 'bina'], $ha)->assertOk();
        $this->postJson("$url/members", ['usernames' => ['esha']], $ha)->assertForbidden();
        $this->postJson("$url/members", ['usernames' => ['esha']], $hb)->assertOk();
        // Back to members: anyone can add again.
        $this->patchJson("$url/add-policy", ['add_policy' => 'members'], $hb)->assertOk();
        $this->postJson("$url/members", ['usernames' => ['asha']], $hc)->assertOk();
    }

    public function test_group_leave_transfers_ownership_and_last_leaver_removes_the_group(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->group($ha, ['bina', 'chandra']);
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi', 'client_id' => 'x1'], $ha)->assertCreated();

        $this->postJson("/api/v1/conversations/$cid/leave", [], $ha)->assertOk()->assertJsonPath('left', true);
        $this->getJson("/api/v1/conversations/$cid/messages", $ha)->assertNotFound();
        $this->assertSame('owner', \DB::table('conversation_members')->where('user_id', $b->id)->value('role'));
        $this->assertSame('member', \DB::table('conversation_members')->where('user_id', $c->id)->value('role'));
        // Leaving twice is rejected, not repeated.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $ha)->assertNotFound();

        $this->postJson("/api/v1/conversations/$cid/leave", [], $hb)->assertOk();
        $this->assertSame('owner', \DB::table('conversation_members')->where('user_id', $c->id)->value('role'));
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hc)->assertOk();
        $this->assertSame(0, \DB::table('conversations')->count());
        $this->assertSame(0, \DB::table('messages')->count());
        // A non-member cannot leave someone else's group.
        $cid2 = $this->group($hb, ['chandra']);
        [$d, $hd] = $this->member('dipesh');
        $this->postJson("/api/v1/conversations/$cid2/leave", [], $hd)->assertNotFound();
        $this->assertSame(2, \DB::table('conversation_members')->count());
    }

    public function test_cannot_add_to_or_leave_a_direct_chat(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $this->member('chandra');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$cid/members", ['usernames' => ['chandra']], $ha)->assertStatus(422);
        $this->postJson("/api/v1/conversations/$cid/leave", [], $ha)->assertStatus(422);
    }

    public function test_send_is_idempotent_by_client_id(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'once', 'client_id' => 'same'], $ha)->assertCreated();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'once', 'client_id' => 'same'], $ha)->assertOk();
        $this->getJson("/api/v1/conversations/$cid/messages", $ha)->assertJsonCount(1, 'data');
    }

    public function test_non_member_cannot_read_or_send(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $this->getJson("/api/v1/conversations/$cid/messages", $hc)->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi'], $hc)->assertNotFound();
    }

    public function test_group_chat_and_validation(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $this->member('chandra');
        $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Family', 'usernames' => ['bina', 'chandra']], $ha)
            ->assertCreated()->assertJsonCount(3, 'conversation.members');
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'nobody'], $ha)->assertUnprocessable();
        $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'asha'], $ha)->assertUnprocessable();
        $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'X', 'usernames' => ['ghost']], $ha)->assertUnprocessable();
    }

    public function test_long_poll_returns_empty_after_wait_when_nothing_new(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $m1 = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hi', 'client_id' => 'p1'], $ha)->json('message.seq');
        $t = microtime(true);
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=$m1&wait=1", $ha)->assertOk()->assertJsonCount(0, 'data');
        $this->assertGreaterThan(0.8, microtime(true) - $t);
        $t = microtime(true);
        $this->getJson("/api/v1/conversations/$cid/messages?after_seq=0&wait=5", $ha)->assertJsonCount(1, 'data');
        $this->assertLessThan(1.0, microtime(true) - $t);
    }
    public function test_call_token_needs_membership_and_config(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chet');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');

        $this->postJson("/api/v1/conversations/$cid/call-token", [], $ha)->assertStatus(503);

        config(['services.livekit' => ['url' => 'wss://example.livekit.cloud', 'key' => 'APItest', 'secret' => 'secret-for-tests-only-0123456789abcdef']]);
        $r = $this->postJson("/api/v1/conversations/$cid/call-token", [], $ha)->assertOk()->assertJsonPath('room', "convo-$cid");
        [$h, $p, $sig] = explode('.', $r->json('token'));
        $claims = json_decode(base64_decode(strtr($p, '-_', '+/')), true);
        $this->assertSame('APItest', $claims['iss']);
        $this->assertSame("convo-$cid", $claims['video']['room']);
        $this->assertSame(rtrim(strtr(base64_encode(hash_hmac('sha256', "$h.$p", 'secret-for-tests-only-0123456789abcdef', true)), '+/', '-_'), '='), $sig);
        $this->postJson("/api/v1/conversations/$cid/call-token", [], $hc)->assertStatus(404);
    }

}
