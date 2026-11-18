<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

/**
 * Stores uploaded media. With Backblaze B2 configured the bytes go to a private bucket and the
 * database keeps only a small metadata row. Without it (tests, local runs) the bytes stay in the
 * database as base64, which is the old behaviour and still served by MediaController.
 */
class MediaStore
{
    public static function enabled(): bool
    {
        return (bool) config('services.b2.key_id') && (bool) config('services.b2.bucket');
    }

    /** Save bytes under a public id. Returns the id. */
    public static function put(string $publicId, string $mime, string $bytes, bool $private = false, bool $forceDatabase = false): string
    {
        // Private attachments stay behind the authenticated DB-media endpoint.
        // Previously issued bucket-wide B2 download tokens may still be valid,
        // so object-scoped NEW tokens alone cannot protect NEW private B2 files.
        $storage = 'db';
        $data = '';
        if (! $private && ! $forceDatabase && self::enabled()) {
            self::upload($publicId, $mime, $bytes);
            $storage = 'b2';
        } else {
            return DB::transaction(function () use ($publicId, $mime, $bytes, $private) {
                // All database-media writers share one transaction-scoped gate.
                // Keep this lock after per-owner/conversation locks, never before.
                if (DB::getDriverName() === 'pgsql') {
                    DB::select('SELECT pg_advisory_xact_lock(736200831)');
                } elseif (DB::getDriverName() !== 'sqlite') {
                    abort(503, 'Database media storage is temporarily unavailable.');
                }
                $cap = filter_var(config('services.uploads.database_media_budget_bytes'), FILTER_VALIDATE_INT);
                $databaseCap = filter_var(config('services.uploads.database_budget_bytes'), FILTER_VALIDATE_INT);
                abort_if($cap === false || $cap < 1 || $databaseCap === false || $databaseCap < 1, 503, 'Database media storage is temporarily unavailable.');
                // Base64 occupies four bytes for every three original bytes.
                // Sum metadata, not blob payloads, so admission does not read media.
                $used = (int) DB::table('media_blobs')->where('storage', 'db')->selectRaw('COALESCE(SUM(4 * ((size + 2) / 3)), 0) AS used')->value('used');
                $incoming = 4 * intdiv(strlen($bytes) + 2, 3);
                abort_if($used + $incoming > $cap, 503, 'Media storage is temporarily full. Try again later.');
                if (DB::getDriverName() === 'pgsql') {
                    $databaseBytes = (int) DB::selectOne('SELECT pg_database_size(current_database()) AS bytes')->bytes;
                    abort_if($databaseBytes + $incoming > $databaseCap, 503, 'Media storage is temporarily full. Try again later.');
                }
                DB::table('media_blobs')->insert([
                    'public_id' => $publicId, 'mime' => $mime, 'size' => strlen($bytes), 'storage' => 'db', 'is_private' => $private,
                    'data' => base64_encode($bytes), 'created_at' => now(), 'updated_at' => now(),
                ]);
                return $publicId;
            });
        }
        DB::table('media_blobs')->insert([
            'public_id' => $publicId, 'mime' => $mime, 'size' => strlen($bytes), 'storage' => $storage, 'is_private' => $private,
            'data' => $data, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $publicId;
    }

    public const PROTOCOL = 'keyed-post-v1';

    /**
     * Name of a keyed object: member + intent + index + content hash. The hash means two different payloads
     * can never share a name, so a racing request with the same intent but other bytes cannot overwrite
     * what a committed post references. The same payload always maps to the same name.
     */
    public static function keyedName(int $userId, string $intent, int $index, string $sha256): string
    {
        return \Ramsey\Uuid\Uuid::uuid5(\Ramsey\Uuid\Uuid::NAMESPACE_URL, 'sanjaal:post-media:'.$userId.':'.$intent.':'.$index.':'.$sha256)->toString();
    }

    /**
     * Upload keyed bytes to B2 outside any database transaction, so no DB connection or row lock is held
     * during the network call (admission is a separate short transaction before it). Never deletes anything: a repeat upload of identical bytes is harmless, and
     * an unreferenced staged object is only reported by the sweep. No-op without B2 (bytes then stay in
     * the database under the admission caps, see putKeyed).
     */
    public static function stageKeyed(string $name, string $mime, string $bytes): void
    {
        if (! self::enabled()) {
            return;
        }
        // An existing row may or may not have its object. Skip the upload only when the bucket confirms this
        // exact object (same name, size, protocol marker). Any doubt means a new, separately reserved attempt.
        $size = strlen($bytes);
        if (DB::table('media_blobs')->where('public_id', $name)->exists() && self::remoteMatches($name, $size)) {
            return;
        }
        // Reservation: every physical upload attempt gets its own committed reservation row (short transaction,
        // before the network call). Identical racing or retried uploads can each leave a retained B2 version, so
        // each is counted. Reservations and admission rows are never removed automatically.
        DB::transaction(function () use ($name, $mime, $size) {
            if (DB::getDriverName() === 'pgsql') {
                DB::select('SELECT pg_advisory_xact_lock(736200832)');
            }
            $cap = filter_var(config('services.uploads.b2_budget_bytes'), FILTER_VALIDATE_INT);
            abort_if($cap === false || $cap < 1, 503, 'Media storage is temporarily unavailable.');
            $reserved = (int) DB::table('b2_stage_attempts')->sum('size');
            $other = (int) DB::table('media_blobs')->where('storage', 'b2')
                ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('b2_stage_attempts')->whereRaw('b2_stage_attempts.name = CAST(media_blobs.public_id AS VARCHAR(64))'))
                ->sum('size');
            abort_if($reserved + $other + $size > $cap, 503, 'Media storage is temporarily full. Try again later.');
            DB::table('b2_stage_attempts')->insert(['name' => $name, 'size' => $size, 'created_at' => now(), 'updated_at' => now()]);
            DB::table('media_blobs')->insertOrIgnore([
                'public_id' => $name, 'mime' => $mime, 'size' => $size, 'storage' => 'b2', 'is_private' => false,
                'data' => '', 'created_at' => now(), 'updated_at' => now(),
            ]);
        });
        self::upload($name, $mime, $bytes, ['X-Bz-Info-sanjaal_protocol' => self::PROTOCOL]);
    }

    /** True only if B2 lists this exact name with the protocol marker and the expected size. Errors mean "not sure". */
    private static function remoteMatches(string $name, int $size): bool
    {
        try {
            $a = self::account();
            $r = Http::withHeaders(['Authorization' => $a['token']])->timeout(15)->post($a['apiUrl'].'/b2api/v3/b2_list_file_names', [
                'bucketId' => config('services.b2.bucket_id'), 'prefix' => $name, 'startFileName' => $name, 'maxFileCount' => 1,
            ])->throw()->json('files', []);
            $f = $r[0] ?? null;

            return $f && ($f['fileName'] ?? null) === $name && (int) ($f['contentLength'] ?? -1) === $size
                && ($f['fileInfo']['sanjaal_protocol'] ?? null) === self::PROTOCOL;
        } catch (\Throwable $e) {
            return false;
        }
    }

    /** Inside the transaction: ensure the staged B2 object has its media row, or fall back to a capped DB write. */
    public static function putKeyed(string $name, string $mime, string $bytes): string
    {
        if (! self::enabled()) {
            return self::put($name, $mime, $bytes, false, true);
        }
        if (! DB::table('media_blobs')->where('public_id', $name)->exists()) {
            DB::table('media_blobs')->insert([
                'public_id' => $name, 'mime' => $mime, 'size' => strlen($bytes), 'storage' => 'b2', 'is_private' => false,
                'data' => '', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }

        return $name;
    }

    public static function putKeyedFile(string $name, UploadedFile $file): string
    {
        return self::putKeyed($name, (string) $file->getMimeType(), (string) file_get_contents($file->getRealPath()));
    }

    /** Objects in the bucket with their upload time (ms). Used only by the orphan sweep. */
    public static function listObjects(): \Generator
    {
        $a = self::account();
        $start = null;
        do {
            $body = ['bucketId' => config('services.b2.bucket_id'), 'maxFileCount' => 1000];
            if ($start !== null) {
                $body['startFileName'] = $start;
            }
            $r = Http::withHeaders(['Authorization' => $a['token']])->timeout(30)->post($a['apiUrl'].'/b2api/v3/b2_list_file_names', $body)->throw()->json();
            foreach ($r['files'] ?? [] as $f) {
                yield ['name' => $f['fileName'], 'protocol' => $f['fileInfo']['sanjaal_protocol'] ?? null, 'uploaded_ms' => (int) ($f['uploadTimestamp'] ?? 0), 'size' => (int) ($f['contentLength'] ?? 0)];
            }
            $start = $r['nextFileName'] ?? null;
        } while ($start !== null);
    }

    public static function removeObject(string $name): void
    {
        self::remove($name);
    }

    public static function putFile(string $publicId, UploadedFile $file, bool $private = false, bool $forceDatabase = false): string
    {
        return self::put($publicId, (string) $file->getMimeType(), (string) file_get_contents($file->getRealPath()), $private, $forceDatabase);
    }

    /** Remove rows and, for B2 rows, the stored file. Failures to delete remote files never block the request. */
    public static function delete(iterable $publicIds): void
    {
        $ids = collect($publicIds)->filter()->values()->all();
        if (! $ids) {
            return;
        }
        $remote = DB::table('media_blobs')->whereIn('public_id', $ids)->where('storage', 'b2')->pluck('public_id');
        DB::table('media_blobs')->whereIn('public_id', $ids)->delete();
        foreach ($remote as $id) {
            try {
                self::remove($id);
            } catch (\Throwable $e) {
                report($e);
            }
        }
    }

    /** A time-limited link straight to B2 for a stored file. */
    public static function url(string $publicId): string
    {
        $auth = self::account();

        return $auth['downloadUrl'].'/file/'.config('services.b2.bucket').'/'.$publicId.'?Authorization='.urlencode(self::downloadToken($publicId));
    }

    private static function account(): array
    {
        return Cache::remember('b2.account', 60 * 60 * 20, function () {
            $r = Http::withBasicAuth(config('services.b2.key_id'), config('services.b2.key'))
                ->timeout(15)->get('https://api.backblazeb2.com/b2api/v3/b2_authorize_account')->throw()->json();
            $api = $r['apiInfo']['storageApi'];

            return ['token' => $r['authorizationToken'], 'apiUrl' => $api['apiUrl'], 'downloadUrl' => $api['downloadUrl']];
        });
    }

    private static function downloadToken(string $publicId): string
    {
        // All object names are generated UUIDs. A full UUID prefix cannot authorize
        // a different object. Never hand clients a token for the entire bucket.
        if (! Str::isUuid($publicId)) {
            throw new \InvalidArgumentException('Invalid media identifier.');
        }

        return Cache::remember('b2.object-download.'.$publicId, 50 * 60, function () use ($publicId) {
            $a = self::account();
            $r = Http::withHeaders(['Authorization' => $a['token']])->timeout(15)
                ->post($a['apiUrl'].'/b2api/v3/b2_get_download_authorization', [
                    'bucketId' => config('services.b2.bucket_id'), 'fileNamePrefix' => $publicId, 'validDurationInSeconds' => 60 * 60,
                ])->throw()->json();

            return $r['authorizationToken'];
        });
    }

    /** Upload bytes for an existing row and return true once B2 accepted them. Used by media:move-to-b2. */
    public static function uploadExisting(string $name, string $mime, string $bytes): void
    {
        self::upload($name, $mime, $bytes);
    }

    /** Read the file back from B2 through the normal download link and confirm its size and SHA1 match. */
    public static function verifyRemote(string $name, string $bytes): bool
    {
        $r = Http::timeout(60)->get(self::url($name));
        if (! $r->successful()) {
            return false;
        }
        $body = $r->body();

        return strlen($body) === strlen($bytes) && hash_equals(sha1($bytes), sha1($body));
    }

    private static function upload(string $name, string $mime, string $bytes, array $info = []): void
    {
        $a = self::account();
        $u = Http::withHeaders(['Authorization' => $a['token']])->timeout(15)
            ->post($a['apiUrl'].'/b2api/v3/b2_get_upload_url', ['bucketId' => config('services.b2.bucket_id')])->throw()->json();
        Http::withHeaders([
            'Authorization' => $u['authorizationToken'], 'X-Bz-File-Name' => $name,
            'X-Bz-Content-Sha1' => sha1($bytes), 'Content-Type' => $mime,
        ] + $info)->withBody($bytes, $mime)->timeout(120)->post($u['uploadUrl'])->throw();
    }

    private static function remove(string $name): void
    {
        $a = self::account();
        $h = ['Authorization' => $a['token']];
        $list = Http::withHeaders($h)->timeout(15)->post($a['apiUrl'].'/b2api/v3/b2_list_file_versions', [
            'bucketId' => config('services.b2.bucket_id'), 'prefix' => $name, 'maxFileCount' => 5,
        ])->throw()->json('files', []);
        foreach ($list as $f) {
            if ($f['fileName'] === $name) {
                Http::withHeaders($h)->timeout(15)->post($a['apiUrl'].'/b2api/v3/b2_delete_file_version', [
                    'fileName' => $name, 'fileId' => $f['fileId'],
                ])->throw();
            }
        }
    }
}
