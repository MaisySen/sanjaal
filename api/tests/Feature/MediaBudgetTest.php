<?php

namespace Tests\Feature;

use App\Support\MediaStore;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

class MediaBudgetTest extends TestCase
{
    use RefreshDatabase;

    public function test_encoded_byte_budget_accepts_exact_fit_and_rejects_next_byte_without_row(): void
    {
        config(['services.uploads.database_media_budget_bytes' => 8]);
        MediaStore::put((string) Str::uuid(), 'image/png', 'abcd', true);
        $this->assertSame(1, DB::table('media_blobs')->count());
        try {
            MediaStore::put((string) Str::uuid(), 'image/png', 'e', true);
            $this->fail('An over-budget admission must be rejected.');
        } catch (HttpException $e) {
            $this->assertSame(503, $e->getStatusCode());
        }
        $this->assertSame(1, DB::table('media_blobs')->count());
        $this->assertSame('abcd', base64_decode(DB::table('media_blobs')->value('data')));
    }

    public function test_admission_counts_old_db_rows_but_not_remote_rows_and_delete_releases_budget(): void
    {
        config(['services.uploads.database_media_budget_bytes' => 8]);
        $id = (string) Str::uuid();
        DB::table('media_blobs')->insert(['public_id' => $id, 'mime' => 'image/png', 'size' => 3, 'data' => base64_encode('old'), 'storage' => 'db', 'created_at' => now(), 'updated_at' => now()]);
        DB::table('media_blobs')->insert(['public_id' => (string) Str::uuid(), 'mime' => 'image/png', 'size' => 99999999, 'data' => '', 'storage' => 'b2', 'created_at' => now(), 'updated_at' => now()]);
        MediaStore::put((string) Str::uuid(), 'image/png', 'new', false, true);
        MediaStore::delete([$id]);
        MediaStore::put((string) Str::uuid(), 'image/png', 'ok', true);
        $this->assertSame(2, DB::table('media_blobs')->where('storage', 'db')->count());
    }

    public function test_invalid_or_zero_budget_fails_closed(): void
    {
        foreach ([0, -1, 'bad'] as $cap) {
            config(['services.uploads.database_media_budget_bytes' => $cap]);
            try {
                MediaStore::put((string) Str::uuid(), 'image/png', 'x', true);
                $this->fail('Invalid media budget accepted.');
            } catch (HttpException $e) {
                $this->assertSame(503, $e->getStatusCode());
            }
        }
        $this->assertSame(0, DB::table('media_blobs')->count());
    }

    public function test_full_story_upload_rolls_back_media_story_and_receipt_then_explicit_retry_works(): void
    {
        [$u, $h] = $this->member('budget');
        config(['services.uploads.replay_safe' => true, 'services.uploads.database_media_budget_bytes' => 1]);
        $file = UploadedFile::fake()->image('photo.png', 12, 12);
        $body = ['upload_intent' => 'budget-same-intent', 'audience' => 'only_me', 'media' => $file];
        $this->post('/api/v1/stories', $body, $h + ['Accept' => 'application/json'])->assertStatus(503)->assertJsonPath('message', 'Media storage is temporarily full. Try again later.');
        foreach (['stories', 'media_blobs', 'upload_receipts'] as $table) {
            $this->assertSame(0, DB::table($table)->count());
        }
        config(['services.uploads.database_media_budget_bytes' => 1000000]);
        $created = $this->post('/api/v1/stories', $body, $h)->assertCreated()->json('story.public_id');
        config(['services.uploads.database_media_budget_bytes' => 1]);
        // Completed replay still reads the original, it is not a new admission.
        $this->post('/api/v1/stories', $body, $h)->assertOk()->assertJsonPath('story.public_id', $created);
        $this->assertSame(1, DB::table('media_blobs')->count());
        $this->get('/api/v1/stories/'.$created.'/media', $h)->assertOk();
        $this->delete('/api/v1/stories/'.$created, [], $h)->assertOk();
    }

    public function test_postgres_overall_database_ceiling_rejects_new_bytes(): void
    {
        if (DB::getDriverName() !== 'pgsql') {
            $this->markTestSkipped('Actual database size check requires PostgreSQL.');
        }
        config(['services.uploads.database_budget_bytes' => 1]);
        try {
            MediaStore::put((string) Str::uuid(), 'image/png', 'x', true);
            $this->fail('Database ceiling was ignored.');
        } catch (HttpException $e) {
            $this->assertSame(503, $e->getStatusCode());
        }
        $this->assertSame(0, DB::table('media_blobs')->count());
    }
}
