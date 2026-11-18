<?php
// Only for the isolated CI database seeded by seed_v40.php.
$owner = \App\Models\User::where('username', 'cowner')->firstOrFail();
$peer = \App\Models\User::factory()->create(['username' => 'fixturepeer']);
$blocked = \App\Models\User::factory()->create(['username' => 'fixtureblocked']);
$post = \App\Models\Post::where('user_id', $owner->id)->firstOrFail();
$hidden = \App\Models\Post::create(['user_id' => $blocked->id, 'kind' => 'post', 'body' => 'blocked fixture must not appear']);
\Illuminate\Support\Facades\DB::table('blocks')->insert(['blocker_id' => $blocked->id, 'blocked_id' => $owner->id, 'created_at' => now()]);
$owner->following()->attach($peer->id);
\Illuminate\Support\Facades\DB::table('likes')->insert([
    ['post_id' => $post->id, 'user_id' => $owner->id, 'reaction' => 'love', 'created_at' => now(), 'updated_at' => now()],
    ['post_id' => $post->id, 'user_id' => $peer->id, 'reaction' => 'like', 'created_at' => now(), 'updated_at' => now()],
]);
\Illuminate\Support\Facades\DB::table('bookmarks')->insert(['post_id' => $post->id, 'user_id' => $owner->id, 'created_at' => now()]);
$parent = $post->comments()->create(['user_id' => $owner->id, 'body' => 'fixture parent']);
foreach (range(1, 12) as $n) $post->comments()->create(['user_id' => $peer->id, 'body' => 'fixture reply '.$n, 'parent_id' => $parent->id]);
$chats = [];
foreach (range(1, 5) as $n) {
    $c = \App\Models\Conversation::create(['type' => 'group', 'title' => 'Read fixture '.$n, 'created_by' => $owner->id, 'last_message_at' => now()->subSeconds($n)]);
    foreach ([$owner, $peer] as $u) $c->members()->attach($u->id, ['role' => $u->id === $owner->id ? 'owner' : 'member']);
    $first = \App\Models\Message::create(['conversation_id' => $c->id, 'user_id' => $peer->id, 'body' => 'fixture first']);
    foreach (range(1, 8) as $i) \App\Models\Message::create(['conversation_id' => $c->id, 'user_id' => $peer->id, 'body' => 'fixture preview '.$i, 'shared_post_id' => $i % 2 ? $post->id : $hidden->id, 'reply_to_id' => $first->id]);
    $chats[] = $c;
}
$outsiderChat = \App\Models\Conversation::create(['type' => 'group', 'title' => 'Denied fixture', 'created_by' => $peer->id]);
$outsiderChat->members()->attach($peer->id, ['role' => 'owner']);
file_put_contents('/tmp/compat/read_specs', implode('|', [
    '/api/v1/posts?scope=following 1',
    '/api/v1/posts?hashtag=fixture 1',
    '/api/v1/posts?username=fixtureblocked 1',
    '/api/v1/posts/'.$post->public_id.'/comments 1',
    '/api/v1/posts/'.$hidden->public_id.'/comments 1',
    '/api/v1/conversations/'.$chats[0]->public_id.'/messages 1',
    '/api/v1/conversations/'.$outsiderChat->public_id.'/messages 1',
]));
