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

        return $id;
    }

    public function test_range_slices_match_the_original_bytes(): void
    {
        // No NUL bytes: the test client reports a lone "\0" body as empty, which is a harness quirk, not the slicer.
        $bytes = strtr(random_bytes(1000), "\0", "\1");
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
        $bytes = random_bytes(300);
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

        $get = $this->get('/api/v1/media/'.$row->public_id);
        $get->assertStatus(302);
        $this->assertSame('https://dl.b2.test/file/bkt/'.$row->public_id.'?Authorization=dl-token', $get->headers->get('Location'));
    }
}
