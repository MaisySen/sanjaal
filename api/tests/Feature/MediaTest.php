<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class MediaTest extends TestCase
{
    use RefreshDatabase;

    private function blob(string $bytes): string
    {
        $id = (string) Str::uuid();
        DB::table('media_blobs')->insert([
            'public_id' => $id, 'mime' => 'video/mp4', 'size' => strlen($bytes),
            'data' => base64_encode($bytes), 'created_at' => now(), 'updated_at' => now(),
        ]);

        $user = \App\Models\User::factory()->create();
        $post = \App\Models\Post::create(['user_id' => $user->id, 'kind' => 'post', 'body' => 'Public range fixture']);
        $post->media()->create(['path' => $id, 'type' => 'video', 'mime' => 'video/mp4', 'size' => strlen($bytes)]);

        return $id;
    }

    public function test_range_slices_match_the_original_bytes(): void
    {
        // Avoid the six bytes PHP's trim() strips (NUL, tab, LF, VT, CR, space): a lone one as a whole
        // body reads back empty in the test client, which is a harness quirk, not the slicer.
        $bytes = strtr(random_bytes(1000), "\0\t\n\x0B\r ", 'ABCDEF');
        $id = $this->blob($bytes);

        foreach ([[0, 0], [1, 1], [2, 5], [3, 3], [4, 10], [997, 999], [500, 999], [0, 999]] as [$a, $b]) {
            $r = $this->call('GET', "/api/v1/media/$id", [], [], [], ['HTTP_RANGE' => "bytes=$a-$b"]);
            $r->assertStatus(206);
            $this->assertSame(substr($bytes, $a, $b - $a + 1), $r->getContent(), "range $a-$b");
            $r->assertHeader('Content-Range', "bytes $a-$b/1000");
        }
    }

    public function test_open_ended_suffix_and_full_and_etag(): void
    {
        $bytes = strtr(random_bytes(300), "\0\t\n\x0B\r ", 'ABCDEF');
        $id = $this->blob($bytes);

        $this->call('GET', "/api/v1/media/$id", [], [], [], ['HTTP_RANGE' => 'bytes=290-'])
            ->assertStatus(206);
        $r = $this->call('GET', "/api/v1/media/$id", [], [], [], ['HTTP_RANGE' => 'bytes=-10']);
        $this->assertSame(substr($bytes, -10), $r->getContent());

        $this->get("/api/v1/media/$id")->assertOk();
        $this->call('GET', "/api/v1/media/$id", [], [], [], ['HTTP_IF_NONE_MATCH' => '"'.$id.'"'])->assertStatus(304);
        $this->call('GET', "/api/v1/media/$id", [], [], [], ['HTTP_RANGE' => 'bytes=999-1000'])->assertStatus(416);
    }

    public function test_b2_storage_keeps_bytes_out_of_the_database_and_redirects_reads(): void
    {
        config(['services.b2' => ['key_id' => 'k', 'key' => 's', 'bucket' => 'bkt', 'bucket_id' => 'bid']]);
        \Illuminate\Support\Facades\Cache::flush();
        \Illuminate\Support\Facades\Http::fake([
            '*b2_authorize_account' => \Illuminate\Support\Facades\Http::response(['authorizationToken' => 'acct', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.b2.test', 'downloadUrl' => 'https://dl.b2.test']]]),
            '*b2_get_upload_url' => \Illuminate\Support\Facades\Http::response(['uploadUrl' => 'https://up.b2.test/u', 'authorizationToken' => 'upl']),
            'https://up.b2.test/u' => \Illuminate\Support\Facades\Http::response(['fileId' => 'f1']),
            '*b2_get_download_authorization' => \Illuminate\Support\Facades\Http::response(['authorizationToken' => 'dl-token']),
        ]);

        [$user, $h] = $this->member('bina');
        $file = \Illuminate\Http\UploadedFile::fake()->image('a.jpg', 20, 20);
        $res = $this->post('/api/v1/posts', ['body' => 'hi', 'media' => [$file]], $h + ['Accept' => 'application/json']);
        $res->assertCreated();

        $row = DB::table('media_blobs')->first();
        $this->assertSame('b2', $row->storage);
        $this->assertSame('', $row->data);
        \Illuminate\Support\Facades\Http::assertSent(fn ($r) => $r->url() === 'https://up.b2.test/u' && $r->hasHeader('X-Bz-File-Name') && $r->hasHeader('X-Bz-Content-Sha1'));

        // A legacy bucket-wide cached token must never be reused.
        \Illuminate\Support\Facades\Cache::put('b2.download', 'LEGACY-BUCKET-TOKEN', 3600);
        $get = $this->get('/api/v1/media/'.$row->public_id);
        $get->assertStatus(302);
        \Illuminate\Support\Facades\Http::assertSent(fn ($r) => str_ends_with($r->url(), 'b2_get_download_authorization') && $r['fileNamePrefix'] === $row->public_id && $r['validDurationInSeconds'] === 3600);
        $this->assertStringNotContainsString('LEGACY-BUCKET-TOKEN', (string) $get->headers->get('Location'));
        $this->assertSame('https://dl.b2.test/file/bkt/'.$row->public_id.'?Authorization=dl-token', $get->headers->get('Location'));
    }
    public function test_private_attachment_cannot_become_public_after_the_last_group_member_leaves(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'Fixture group', 'usernames' => ['bina']], $ha)->assertCreated()->json('conversation.public_id');
        $message = $this->post("/api/v1/conversations/$cid/messages", ['media' => \Illuminate\Http\UploadedFile::fake()->image('fixture.jpg', 20, 20)], $ha + ['Accept' => 'application/json'])->assertCreated()->json('message.public_id');
        $blob = DB::table('messages')->where('public_id', $message)->value('media_id');
        $this->getJson("/api/v1/conversations/$cid/messages/$message/media", $hb)->assertOk();
        $this->get("/api/v1/media/$blob")->assertNotFound();
        $this->postJson("/api/v1/conversations/$cid/leave", [], $ha)->assertOk();
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hb)->assertOk();
        $this->assertDatabaseMissing('messages', ['public_id' => $message]);
        $this->get("/api/v1/media/$blob")->assertNotFound();
    }

    public function test_anonymous_media_requires_a_current_public_owner_even_for_conditional_requests(): void
    {
        $orphan = (string) Str::uuid();
        \App\Support\MediaStore::put($orphan, 'image/jpeg', 'PRIVATE-FIXTURE', true);
        $this->get("/api/v1/media/$orphan")->assertNotFound();
        $this->call('GET', "/api/v1/media/$orphan", [], [], [], ['HTTP_IF_NONE_MATCH' => '"'.$orphan.'"'])->assertNotFound();
        $public = $this->blob('PUBLIC-FIXTURE');
        $post = \App\Models\Post::findOrFail(DB::table('post_media')->where('path', $public)->value('post_id'));
        $post->delete();
        $this->get("/api/v1/media/$public")->assertNotFound();
        $this->assertDatabaseHas('media_blobs', ['public_id' => $orphan]);
    }

    public function test_current_avatar_and_active_story_still_serve_but_expired_or_removed_story_does_not(): void
    {
        [$user] = $this->member('asha');
        $avatar = (string) Str::uuid();
        \App\Support\MediaStore::put($avatar, 'image/jpeg', 'AVATAR-FIXTURE');
        $user->forceFill(['avatar' => $avatar])->save();
        $this->get("/api/v1/media/$avatar")->assertOk();
        $story = (string) Str::uuid();
        \App\Support\MediaStore::put($story, 'image/jpeg', 'STORY-FIXTURE');
        $id = DB::table('stories')->insertGetId(['public_id' => (string) Str::uuid(), 'user_id' => $user->id, 'media_id' => $story, 'media_mime' => 'image/jpeg', 'expires_at' => now()->addHour(), 'created_at' => now(), 'updated_at' => now()]);
        $this->get("/api/v1/media/$story")->assertOk();
        DB::table('stories')->where('id', $id)->update(['expires_at' => now()->subSecond()]);
        $this->get("/api/v1/media/$story")->assertNotFound();
        DB::table('stories')->where('id', $id)->delete();
        $this->get("/api/v1/media/$story")->assertNotFound();
    }

}
