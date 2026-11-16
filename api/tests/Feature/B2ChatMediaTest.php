<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** Chat media when files live in Backblaze B2. B2 is faked here: no real bucket, no real keys, no network. */
class B2ChatMediaTest extends TestCase
{
    use RefreshDatabase;

    private function fakeB2(int $downloadStatus = 200): void
    {
        config(['services.b2.key_id' => 'k', 'services.b2.key' => 's', 'services.b2.bucket' => 'b', 'services.b2.bucket_id' => 'bid']);
        Http::fake([
            '*b2_authorize_account*' => Http::response(['authorizationToken' => 'acct-token', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.test', 'downloadUrl' => 'https://dl.test']]]),
            '*b2_get_upload_url*' => Http::response(['authorizationToken' => 'u', 'uploadUrl' => 'https://up.test/x']),
            '*b2_get_download_authorization*' => Http::response(['authorizationToken' => 'BUCKET-WIDE-SECRET']),
            'https://up.test/*' => Http::response([], 200),
            'https://dl.test/*' => Http::response('PHOTO-BYTES', $downloadStatus, ['Content-Type' => 'image/jpeg']),
        ]);
    }

    private function downloads(): int
    {
        return Http::recorded(fn ($req) => str_starts_with($req->url(), 'https://dl.test/'))->count();
    }

    public function test_b2_chat_media_is_proxied_to_members_only_and_never_leaks_the_bucket_link(): void
    {
        $this->fakeB2();
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        [$c, $hc] = $this->member('chandra');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'group', 'title' => 'T', 'usernames' => ['bina']], $ha)->assertCreated()->json('conversation.public_id');
        $sent = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('a.jpg', 30, 30)], $ha)->assertCreated();
        $mid = $sent->json('message.public_id');
        $rawId = DB::table('messages')->where('public_id', $mid)->value('media_id');
        DB::table('media_blobs')->where('public_id', $rawId)->update(['storage' => 'b2', 'data' => '']);
        $this->assertSame('b2', DB::table('media_blobs')->where('public_id', $rawId)->value('storage'));
        $this->assertSame('', DB::table('media_blobs')->where('public_id', $rawId)->value('data'), 'no bytes kept in the database');

        // Nothing the API returns about the message carries a B2 address or token.
        foreach ([$sent->getContent(), $this->getJson("/api/v1/conversations/$cid/messages", $hb)->getContent(), $this->getJson('/api/v1/conversations', $hb)->getContent()] as $body) {
            $this->assertStringNotContainsString('dl.test', $body);
            $this->assertStringNotContainsString('BUCKET-WIDE-SECRET', $body);
        }

        $path = "/api/v1/conversations/$cid/messages/$mid/media";
        $this->assertSame(0, $this->downloads());
        $ok = $this->get($path, $hb)->assertOk();
        $this->assertSame('PHOTO-BYTES', $ok->getContent());
        $this->assertFalse($ok->headers->has('Location'), 'proxied, not redirected');
        $this->assertStringNotContainsString('BUCKET-WIDE-SECRET', json_encode($ok->headers->all()));
        $this->assertStringContainsString('no-store', (string) $ok->headers->get('Cache-Control'));
        $this->assertSame(1, $this->downloads());

        // Outsider, signed-out caller and the old public address get nothing, and B2 is never even asked.
        $this->get($path, $hc)->assertNotFound();
        $this->getJson($path)->assertUnauthorized();
        $this->get("/api/v1/media/$rawId")->assertNotFound();
        $this->assertSame(1, $this->downloads(), 'denied requests never reach B2');

        // A member who leaves loses access at once.
        $this->postJson("/api/v1/conversations/$cid/leave", [], $hb)->assertOk();
        $this->get($path, $hb)->assertNotFound();
        $this->assertSame(1, $this->downloads());
    }

    public function test_a_failed_b2_download_is_a_plain_404_not_a_redirect_or_leak(): void
    {
        $this->fakeB2(500);
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');
        $mid = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('a.jpg', 30, 30)], $ha)->assertCreated()->json('message.public_id');
        $rawId = DB::table('messages')->where('public_id', $mid)->value('media_id');
        DB::table('media_blobs')->where('public_id', $rawId)->update(['storage' => 'b2', 'data' => '']);
        $r = $this->get("/api/v1/conversations/$cid/messages/$mid/media", $ha)->assertNotFound();
        $this->assertStringNotContainsString('BUCKET-WIDE-SECRET', $r->getContent());
        $this->assertFalse($r->headers->has('Location'));
    }
    public function test_new_private_upload_never_enters_bucket_even_when_b2_enabled(): void
    {
        $this->fakeB2();
        [$a, $ha] = $this->member('asha');
        $this->member('bina');
        $cid = $this->postJson('/api/v1/conversations', ['type' => 'direct', 'username' => 'bina'], $ha)->assertCreated()->json('conversation.public_id');
        $mid = $this->post("/api/v1/conversations/$cid/messages", ['media' => UploadedFile::fake()->image('a.jpg', 30, 30)], $ha)->assertCreated()->json('message.public_id');
        $rawId = DB::table('messages')->where('public_id', $mid)->value('media_id');
        $this->assertSame('db', DB::table('media_blobs')->where('public_id', $rawId)->value('storage'));
        $this->assertNotEmpty(DB::table('media_blobs')->where('public_id', $rawId)->value('data'));
        Http::assertNothingSent();
        $this->artisan('media:move-to-b2')->assertSuccessful();
        Http::assertNothingSent();
        $this->assertSame('db', DB::table('media_blobs')->where('public_id', $rawId)->value('storage'));
        $this->get("/api/v1/media/$rawId")->assertNotFound();
        $this->get("/api/v1/conversations/$cid/messages/$mid/media", $ha)->assertOk()->assertHeader('Cache-Control', 'no-store, private');
    }

}
