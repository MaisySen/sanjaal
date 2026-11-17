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
            $data = base64_encode($bytes);
        }
        DB::table('media_blobs')->insert([
            'public_id' => $publicId, 'mime' => $mime, 'size' => strlen($bytes), 'storage' => $storage, 'is_private' => $private,
            'data' => $data, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $publicId;
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

    private static function upload(string $name, string $mime, string $bytes): void
    {
        $a = self::account();
        $u = Http::withHeaders(['Authorization' => $a['token']])->timeout(15)
            ->post($a['apiUrl'].'/b2api/v3/b2_get_upload_url', ['bucketId' => config('services.b2.bucket_id')])->throw()->json();
        Http::withHeaders([
            'Authorization' => $u['authorizationToken'], 'X-Bz-File-Name' => $name,
            'X-Bz-Content-Sha1' => sha1($bytes), 'Content-Type' => $mime,
        ])->withBody($bytes, $mime)->timeout(120)->post($u['uploadUrl'])->throw();
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
