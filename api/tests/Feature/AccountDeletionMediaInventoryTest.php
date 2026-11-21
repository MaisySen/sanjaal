<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Support\AccountDeletionMediaInventory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class AccountDeletionMediaInventoryTest extends TestCase
{
    use RefreshDatabase;

    private function blob(string $storage = 'db', bool $private = true): string
    {
        $id = (string) Str::uuid();
        DB::table('media_blobs')->insert(['public_id' => $id, 'mime' => 'image/png', 'size' => 4, 'data' => 'PRIVATE_BLOB_BYTES', 'storage' => $storage, 'is_private' => $private, 'created_at' => now(), 'updated_at' => now()]);
        return $id;
    }

    private function media(int $userId, string $path): void
    {
        $post = Post::create(['user_id' => $userId, 'body' => 'PRIVATE_POST_CONTENT']);
        DB::table('post_media')->insert(['post_id' => $post->id, 'type' => 'image', 'path' => $path, 'mime' => 'image/png', 'size' => 4, 'created_at' => now(), 'updated_at' => now()]);
    }

    public function test_own_references_only_shared_references_and_no_blob_content_or_writes(): void
    {
        [$a] = $this->member('asha'); [$b] = $this->member('bina');
        $shared = $this->blob(); $private = $this->blob(); $other = $this->blob();
        $this->media($a->id, $shared); $this->media($a->id, $private); $this->media($b->id, $other);
        DB::table('users')->where('id', $b->id)->update(['avatar' => $shared]);
        Http::fake(); DB::enableQueryLog(); DB::flushQueryLog();
        $result = AccountDeletionMediaInventory::inspect($a->id);
        $queries = DB::getQueryLog(); DB::disableQueryLog();
        foreach ($queries as $query) $this->assertStringStartsWith('select ', strtolower(ltrim($query['query'])));
        $this->assertSame(2, $result['candidate_ids_inspected']); $this->assertSame(1, $result['other_member_referenced_candidates']);
        $this->assertSame(1, $result['storage_counts']['private_db_without_observed_other_member_reference']);
        $this->assertFalse($result['inventory_complete']); $this->assertFalse($result['deletion_allowed']);
        $output = json_encode($result);
        foreach ([$shared, $private, $other, 'PRIVATE_BLOB_BYTES', 'PRIVATE_POST_CONTENT'] as $privateValue) $this->assertStringNotContainsString($privateValue, $output);
        $this->assertDatabaseCount('posts', 3); $this->assertDatabaseCount('media_blobs', 3); Http::assertNothingSent();
    }

    public function test_external_storage_missing_and_unrecognized_paths_remain_unresolved(): void
    {
        [$a] = $this->member('asha'); $this->media($a->id, $this->blob('b2')); $this->media($a->id, (string) Str::uuid());
        $this->media($a->id, '../untrusted-object-path');
        $result = AccountDeletionMediaInventory::inspect($a->id);
        $this->assertSame(2, $result['candidate_ids_inspected']); $this->assertSame(1, $result['unsupported_reference_shapes']);
        $this->assertSame(1, $result['missing_blob_rows_in_sample']); $this->assertSame(1, $result['storage_counts']['b2']);
        $this->assertFalse($result['deletion_allowed']);
    }

    public function test_candidates_are_bounded_and_truncation_never_claims_complete_inventory(): void
    {
        [$a] = $this->member('asha'); $rows = [];
        for ($i = 0; $i <= AccountDeletionMediaInventory::LIMIT; $i++) {
            $rows[] = ['public_id' => (string) Str::uuid(), 'user_id' => $a->id, 'media_id' => (string) Str::uuid(), 'media_mime' => 'image/png', 'expires_at' => now()->addHour(), 'created_at' => now(), 'updated_at' => now()];
        }
        DB::table('stories')->insert($rows);
        $result = AccountDeletionMediaInventory::inspect($a->id);
        $this->assertSame(AccountDeletionMediaInventory::LIMIT, $result['candidate_ids_inspected']); $this->assertTrue($result['candidate_sample_truncated']);
        $this->assertFalse($result['inventory_complete']); $this->assertDatabaseCount('stories', AccountDeletionMediaInventory::LIMIT + 1);
    }
}
