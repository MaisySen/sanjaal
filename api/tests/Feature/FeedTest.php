<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Tests\TestCase;

class FeedTest extends TestCase
{
    use RefreshDatabase;

    public function test_post_like_comment_and_hashtags(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/posts', ['body' => 'Namaste #Nepal #pokhara'], $ha)
            ->assertCreated()->json('post.public_id');
        $this->getJson('/api/v1/posts?hashtag=nepal', $hb)->assertOk()->assertJsonCount(1, 'data');

        $this->postJson("/api/v1/posts/$id/like", [], $hb)->assertOk()->assertJsonPath('liked', true)->assertJsonPath('likes_count', 1);
        $this->postJson("/api/v1/posts/$id/like", [], $hb)->assertOk()->assertJsonPath('likes_count', 1);
        $this->deleteJson("/api/v1/posts/$id/like", [], $hb)->assertOk()->assertJsonPath('likes_count', 0);

        $this->postJson("/api/v1/posts/$id/comments", ['body' => 'sundar'], $hb)->assertCreated();
        $this->getJson("/api/v1/posts/$id/comments", $ha)->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.body', 'sundar');
        $this->getJson('/api/v1/posts', $ha)->assertJsonPath('data.0.comments_count', 1);
    }

    public function test_only_author_can_delete(): void
    {
        [$a, $ha] = $this->member('asha');
        [$b, $hb] = $this->member('bina');
        $id = $this->postJson('/api/v1/posts', ['body' => 'mine'], $ha)->json('post.public_id');
        $this->deleteJson("/api/v1/posts/$id", [], $hb)->assertForbidden();
        $this->deleteJson("/api/v1/posts/$id", [], $ha)->assertOk();
        $this->getJson("/api/v1/posts/$id", $ha)->assertNotFound();
    }

    public function test_empty_post_is_rejected(): void
    {
        [$a, $ha] = $this->member('asha');
        $this->postJson('/api/v1/posts', [], $ha)->assertUnprocessable();
    }

    public function test_image_upload_is_stored_in_database_and_served_with_range(): void
    {
        [$a, $ha] = $this->member('asha');
        $file = UploadedFile::fake()->image('p.png', 40, 40);
        $res = $this->post('/api/v1/posts', ['body' => 'pic', 'media' => [$file]], $ha)->assertCreated();
        $url = $res->json('post.media.0.url');
        $this->assertStringContainsString('/api/v1/media/', $url);
        $path = parse_url($url, PHP_URL_PATH);

        $full = $this->get($path)->assertOk();
        $this->assertSame(file_get_contents($file->getRealPath()), $full->getContent());
        $this->assertSame('image/png', $full->headers->get('Content-Type'));

        $part = $this->get($path, ['Range' => 'bytes=0-9'])->assertStatus(206);
        $this->assertSame(10, strlen($part->getContent()));
        $this->assertStringStartsWith('bytes 0-9/', $part->headers->get('Content-Range'));

        $this->deleteJson('/api/v1/posts/'.$res->json('post.public_id'), [], $ha)->assertOk();
        $this->get($path)->assertNotFound();
        $this->assertDatabaseCount('media_blobs', 0);
    }

    public function test_non_image_upload_is_rejected(): void
    {
        [$a, $ha] = $this->member('asha');
        $tmp = tempnam(sys_get_temp_dir(), 'bad');
        file_put_contents($tmp, 'this is plain text, not an image');
        $file = new UploadedFile($tmp, 'x.png', 'image/png', null, true);
        $this->post('/api/v1/posts', ['body' => 'x', 'media' => [$file]], $ha)->assertUnprocessable();
    }

    public function test_unknown_media_is_404(): void
    {
        $this->get('/api/v1/media/00000000-0000-4000-8000-000000000000')->assertNotFound();
    }
}
