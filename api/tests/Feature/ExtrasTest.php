<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class ExtrasTest extends TestCase
{
    use RefreshDatabase;

    public function test_reactions_switch_and_remove(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/posts', ['body' => 'hi'], $ha)->json('post.public_id');
        $this->postJson("/api/v1/posts/$id/reaction", ['type' => 'love'], $hb)->assertOk()->assertJsonPath('my_reaction', 'love')->assertJsonPath('likes_count', 1);
        $this->postJson("/api/v1/posts/$id/reaction", ['type' => 'wow'], $hb)->assertOk()->assertJsonPath('my_reaction', 'wow')->assertJsonPath('likes_count', 1);
        $this->postJson("/api/v1/posts/$id/reaction", ['type' => 'nope'], $hb)->assertStatus(422);
        $this->getJson('/api/v1/posts', $hb)->assertJsonPath('data.0.reactions.wow', 1);
        $this->deleteJson("/api/v1/posts/$id/reaction", [], $hb)->assertOk()->assertJsonPath('likes_count', 0);
    }

    public function test_stories_flow(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $h = $ha + ['Accept' => 'application/json'];
        $s = $this->post('/api/v1/stories', ['media' => UploadedFile::fake()->image('s.jpg', 40, 40), 'caption' => 'Tihar'], $h)->assertCreated()->json('story.public_id');
        $this->getJson('/api/v1/stories', $hb)->assertJsonCount(0, 'data');
        $this->postJson('/api/v1/users/asha/follow', [], $hb)->assertOk();
        $this->getJson('/api/v1/stories', $hb)->assertJsonPath('data.0.author.username', 'asha')->assertJsonPath('data.0.all_viewed', false);
        $this->postJson("/api/v1/stories/$s/view", [], $hb)->assertOk();
        $this->getJson('/api/v1/stories', $hb)->assertJsonPath('data.0.all_viewed', true);
        $this->getJson("/api/v1/stories/$s/viewers", $ha)->assertJsonPath('data.0.username', 'bina');
        $this->deleteJson("/api/v1/stories/$s", [], $ha)->assertOk();
    }

    public function test_chat_media_reply_settings_typing_and_calls(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $m1 = $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'namaste'], $ha)->assertCreated()->json('message.public_id');
        $this->postJson("/api/v1/conversations/$cid/messages", ['body' => 'hello', 'reply_to' => $m1], $hb)->assertCreated()->assertJsonPath('message.reply_to.body', 'namaste');
        $img = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('p.jpg', 30, 30)], $ha + ['Accept' => 'application/json'])->assertCreated();
        $this->assertSame('image', $img->json('message.kind'));
        $this->assertNotNull($img->json('message.media_url'));
        $this->patchJson("/api/v1/conversations/$cid/settings", ['pinned' => true, 'muted' => true], $hb)->assertOk()->assertJsonPath('pinned', true);
        $this->getJson('/api/v1/conversations', $hb)->assertJsonPath('data.0.pinned', true);
        $this->patchJson("/api/v1/conversations/$cid/settings", ['archived' => true], $hb)->assertOk();
        $this->getJson('/api/v1/conversations', $hb)->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/conversations?archived=1', $hb)->assertJsonCount(1, 'data');
        $this->postJson("/api/v1/conversations/$cid/typing", [], $ha)->assertOk();
        $this->getJson("/api/v1/conversations/$cid/messages", $hb)->assertJsonPath('typing.0', 'asha');
    }

    public function test_call_history_and_incoming(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->json('conversation.public_id');
        $call = \App\Http\Controllers\ExtrasController::ring(\App\Models\Conversation::where('public_id', $cid)->first(), $a, 'video');
        $this->getJson('/api/v1/calls/incoming', $ha)->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/calls/incoming', $hb)->assertJsonPath('data.0.kind', 'video')->assertJsonPath('data.0.caller.username', 'asha');
        $this->postJson("/api/v1/calls/$call/action", ['action' => 'decline'], $hb)->assertOk()->assertJsonPath('call.status', 'declined');
        $this->getJson('/api/v1/calls/incoming', $hb)->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/calls', $hb)->assertJsonPath('data.0.direction', 'incoming');
        $this->getJson('/api/v1/calls', $ha)->assertJsonPath('data.0.direction', 'outgoing');
    }
}
