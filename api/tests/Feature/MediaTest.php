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
        $bytes = random_bytes(1000);
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
}
