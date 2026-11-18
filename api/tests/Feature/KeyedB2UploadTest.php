<?php
namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** Keyed (replay-safe) post media in B2. B2 is faked: no bucket, keys or network. */
class KeyedB2UploadTest extends TestCase
{
    use RefreshDatabase;
    private const KEY = 'fixture-b2-intent-000001';
    private array $uploaded = [];
    private array $deleted = [];
    private bool $failUpload = false;
    private array $levels = [];
    private array $rowsAtUpload = [];

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.uploads.replay_safe' => true, 'services.b2.key_id' => 'k', 'services.b2.key' => 's', 'services.b2.bucket' => 'b', 'services.b2.bucket_id' => 'bid']);
        \Illuminate\Support\Facades\Cache::flush();
    }

    private function fakeB2(): void
    {
        Http::fake([
            '*b2_authorize_account*' => Http::response(['authorizationToken' => 'acct', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.test', 'downloadUrl' => 'https://dl.test']]]),
            '*b2_get_upload_url*' => Http::response(['authorizationToken' => 'u', 'uploadUrl' => 'https://up.test/x']),
            'https://up.test/*' => function ($req) {
                if ($this->failUpload) { return Http::response(['message' => 'down'], 503); }
                $this->uploaded[] = $req->header('X-Bz-File-Name')[0];
                $this->levels[] = DB::transactionLevel();
                $this->rowsAtUpload[] = DB::table('media_blobs')->count();
                return Http::response([], 200);
            },
            '*b2_list_file_versions*' => function ($req) {
                $prefix = $req->data()['prefix'];
                return Http::response(['files' => in_array($prefix, $this->uploaded, true) ? [['fileName' => $prefix, 'fileId' => 'fid-'.$prefix]] : []]);
            },
            '*b2_delete_file_version*' => function ($req) { $this->deleted[] = $req->data()['fileName']; return Http::response([]); },
        ]);
    }

    private function body(array $media): array { return ['body' => 'Hi', 'upload_intent' => self::KEY, 'media' => $media]; }
    private function img(string $n = 'a.png'): UploadedFile { return UploadedFile::fake()->image($n, 10, 10); }

    public function test_keyed_media_goes_to_b2_with_a_stable_name_and_replays_without_a_second_object(): void
    {
        $this->fakeB2();
        [$a, $h] = $this->member('asha');
        $body = $this->body([$this->img()]);
        $id = $this->post('/api/v1/posts', $body, $h)->assertCreated()->json('post.public_id');
        $row = DB::table('media_blobs')->first();
        $this->assertSame('b2', $row->storage); $this->assertSame('', $row->data);
        $this->assertSame([$row->public_id], $this->uploaded);
        $this->post('/api/v1/posts', $body, $h)->assertOk()->assertJsonPath('post.public_id', $id)->assertJsonPath('replayed', true);
        $this->assertCount(1, $this->uploaded, 'replay must not upload again');
        $this->assertDatabaseCount('posts', 1); $this->assertDatabaseCount('media_blobs', 1);
    }

    public function test_commit_failure_deletes_nothing_and_the_retry_reuses_the_same_name(): void
    {
        $this->fakeB2();
        [$a, $h] = $this->member('asha');
        \App\Models\PostMedia::creating(function () { throw new \RuntimeException('fixture failure after upload'); });
        try {
            $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertStatus(500);
        } finally { \App\Models\PostMedia::flushEventListeners(); }
        $this->assertDatabaseCount('posts', 0); $this->assertDatabaseCount('upload_receipts', 0);
        $this->assertDatabaseCount('media_blobs', 1); // the admission row stays, counted against the budget, until a reviewed cleanup
        $this->assertCount(1, $this->uploaded);
        $this->assertSame([], $this->deleted, 'no automatic deletion: the staged object is only ever reported by the sweep');
        $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertCreated();
        $this->assertSame($this->uploaded[0], $this->uploaded[1], 'retry uses the same content-hashed name');
        $this->assertSame($this->uploaded[0], DB::table('media_blobs')->value('public_id'));
        $this->assertSame([], $this->deleted);
    }

    public function test_b2_upload_happens_outside_any_database_transaction(): void
    {
        $this->fakeB2();
        [$a, $h] = $this->member('asha');
        $base = DB::transactionLevel();
        $this->post('/api/v1/posts', $this->body([$this->img(), $this->img('b.png')]), $h)->assertCreated();
        $this->assertCount(2, $this->levels);
        $this->assertSame([$base, $base], $this->levels, 'no DB transaction or member row lock is held during the B2 upload');
    }

    public function test_staged_bytes_are_admitted_against_a_budget_before_any_b2_call(): void
    {
        $this->fakeB2();
        [$a, $h] = $this->member('asha');
        config(['services.uploads.b2_budget_bytes' => 1]);
        $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertStatus(503);
        $this->assertSame([], $this->uploaded); $this->assertDatabaseCount('media_blobs', 0); $this->assertDatabaseCount('posts', 0);
        config(['services.uploads.b2_budget_bytes' => 10 * 1024 * 1024]);
        $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertCreated();
        $this->assertSame([1], $this->rowsAtUpload, 'the admission row is committed before the upload starts');
    }

    public function test_same_intent_with_different_bytes_can_never_share_or_overwrite_an_object_name(): void
    {
        $one = \App\Support\MediaStore::keyedName(1, 'fixture-intent-0000001', 0, hash('sha256', 'one'));
        $two = \App\Support\MediaStore::keyedName(1, 'fixture-intent-0000001', 0, hash('sha256', 'two'));
        $this->assertNotSame($one, $two);
        $this->assertSame($one, \App\Support\MediaStore::keyedName(1, 'fixture-intent-0000001', 0, hash('sha256', 'one')));
        $this->assertNotSame($one, \App\Support\MediaStore::keyedName(2, 'fixture-intent-0000001', 0, hash('sha256', 'one')));
        $this->assertNotSame($one, \App\Support\MediaStore::keyedName(1, 'fixture-intent-0000001', 1, hash('sha256', 'one')));
        $this->assertTrue(\Illuminate\Support\Str::isUuid($one));
    }

    public function test_b2_outage_leaves_no_post_row_receipt_and_a_safe_retry_works(): void
    {
        $this->fakeB2(); $this->failUpload = true;
        [$a, $h] = $this->member('asha');
        $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertStatus(500);
        $this->assertDatabaseCount('posts', 0); $this->assertDatabaseCount('media_blobs', 0); $this->assertDatabaseCount('upload_receipts', 0);
        $this->failUpload = false;
        $this->post('/api/v1/posts', $this->body([$this->img()]), $h)->assertCreated();
        $this->assertDatabaseCount('posts', 1);
    }

    public function test_names_differ_per_member_and_per_index_and_delete_removes_the_objects(): void
    {
        $this->fakeB2();
        [$a, $ha] = $this->member('asha'); [$b, $hb] = $this->member('bina');
        $id = $this->post('/api/v1/posts', $this->body([$this->img(), $this->img('b.png')]), $ha)->assertCreated()->json('post.public_id');
        $this->post('/api/v1/posts', $this->body([$this->img()]), $hb)->assertCreated();
        $this->assertCount(3, array_unique($this->uploaded));
        $this->deleteJson('/api/v1/posts/'.$id, [], $ha)->assertOk();
        $this->assertCount(2, $this->deleted, 'deleting the post removes exactly its own two objects');
        $this->post('/api/v1/posts', $this->body([$this->img(), $this->img('b.png')]), $ha)->assertStatus(410);
    }

    public function test_sweep_reports_only_unreferenced_protocol_objects_and_never_deletes(): void
    {
        $old = (now()->subDays(2)->getTimestamp()) * 1000; $new = now()->getTimestamp() * 1000;
        $u = fn () => (string) \Illuminate\Support\Str::uuid();
        [$kept, $orphan, $recent, $legacy] = [$u(), $u(), $u(), $u()];
        DB::table('media_blobs')->insert(['public_id' => $kept, 'mime' => 'image/png', 'size' => 1, 'storage' => 'b2', 'is_private' => false, 'data' => '', 'created_at' => now(), 'updated_at' => now()]);
        $p = ['sanjaal_protocol' => 'keyed-post-v1'];
        Http::fake([
            '*b2_authorize_account*' => Http::response(['authorizationToken' => 'acct', 'apiInfo' => ['storageApi' => ['apiUrl' => 'https://api.test', 'downloadUrl' => 'https://dl.test']]]),
            '*b2_list_file_names*' => Http::response(['files' => [
                ['fileName' => $kept, 'uploadTimestamp' => $old, 'contentLength' => 5, 'fileInfo' => $p],
                ['fileName' => $orphan, 'uploadTimestamp' => $old, 'contentLength' => 7, 'fileInfo' => $p],
                ['fileName' => $recent, 'uploadTimestamp' => $new, 'contentLength' => 9, 'fileInfo' => $p],
                ['fileName' => $legacy, 'uploadTimestamp' => $old, 'contentLength' => 11, 'fileInfo' => []],
                ['fileName' => 'not-a-media-name.txt', 'uploadTimestamp' => $old, 'contentLength' => 3, 'fileInfo' => $p],
            ], 'nextFileName' => null]),
        ]);
        $this->artisan('media:sweep-b2-orphans')->expectsOutputToContain('1 unreferenced keyed-upload object(s), 7 bytes')->assertSuccessful();
        Http::assertNotSent(fn ($r) => str_contains($r->url(), 'delete'));
    }

    public function test_marker_is_sent_with_the_upload_and_a_committed_name_is_never_reused_destructively(): void
    {
        $this->fakeB2();
        [$a, $h] = $this->member('asha');
        $body = $this->body([$this->img()]);
        $this->post('/api/v1/posts', $body, $h)->assertCreated();
        Http::assertSent(fn ($r) => str_starts_with($r->url(), 'https://up.test') && $r->header('X-Bz-Info-sanjaal_protocol') === ['keyed-post-v1']);
        $deletedBefore = $this->deleted;
        // Same intent, changed payload: conflict is decided from the receipt before any B2 call.
        $calls = count(Http::recorded());
        $this->post('/api/v1/posts', $this->body([UploadedFile::fake()->image('o.png', 30, 10)]), $h)->assertStatus(409);
        $this->assertSame($calls, count(Http::recorded()), 'a conflicting retry makes no B2 call at all');
        $this->post('/api/v1/posts', $body, $h)->assertOk();
        $this->assertSame($calls, count(Http::recorded()), 'a replay makes no B2 call at all');
        $this->assertSame($deletedBefore, $this->deleted);
    }
}
