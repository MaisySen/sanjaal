<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MoveMediaTest extends TestCase
{
    use RefreshDatabase;

    private function row(string $id, string $bytes, ?int $size = null): void
    {
        DB::table('media_blobs')->insert(['public_id' => $id, 'mime' => 'image/png', 'size' => $size ?? strlen($bytes), 'storage' => 'db',
            'data' => base64_encode($bytes), 'created_at' => now(), 'updated_at' => now()]);
    }

    private function b2(int $uploadStatus = 200): void
    {
        config(['services.b2.key_id' => 'k', 'services.b2.key' => 's', 'services.b2.bucket' => 'b', 'services.b2.bucket_id' => 'bid']);
        Http::fake([
            '*b2_authorize_account*' => Http::response(['authorizationToken' => 't', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.test', 'downloadUrl' => 'https://dl.test']]]),
            '*b2_get_upload_url*' => Http::response(['authorizationToken' => 'u', 'uploadUrl' => 'https://up.test/x']),
            'https://up.test/*' => Http::response([], $uploadStatus),
        ]);
    }

    public function test_moves_rows_and_empties_database_copy(): void
    {
        $this->b2();
        $this->row('a1', 'hello');
        $this->artisan('media:move-to-b2')->assertSuccessful();
        $r = DB::table('media_blobs')->where('public_id', 'a1')->first();
        $this->assertSame('b2', $r->storage);
        $this->assertSame('', $r->data);
        Http::assertSent(fn ($req) => $req->url() === 'https://up.test/x' && $req->body() === 'hello' && $req->header('X-Bz-Content-Sha1')[0] === sha1('hello'));
    }

    public function test_failed_upload_keeps_the_database_copy(): void
    {
        $this->b2(500);
        $this->row('a2', 'bytes');
        $this->artisan('media:move-to-b2')->assertFailed();
        $r = DB::table('media_blobs')->where('public_id', 'a2')->first();
        $this->assertSame('db', $r->storage);
        $this->assertSame(base64_encode('bytes'), $r->data);
    }

    public function test_size_mismatch_is_skipped_and_dry_run_changes_nothing(): void
    {
        $this->b2();
        $this->row('a3', 'xyz', 99);
        $this->artisan('media:move-to-b2')->assertFailed();
        $this->row('a4', 'ok');
        $this->artisan('media:move-to-b2 --dry-run');
        $this->assertSame('db', DB::table('media_blobs')->where('public_id', 'a4')->value('storage'));
    }
}
