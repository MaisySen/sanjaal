<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Bounded DB-only media reference sample. Never returns paths or blob contents. */
class AccountDeletionMediaInventory
{
    public const LIMIT = 250;

    public static function inspect(int $userId): array
    {
        $paths = []; $truncated = false;
        $sources = [
            DB::table('post_media')->join('posts', 'posts.id', '=', 'post_media.post_id')->where('posts.user_id', $userId)->orderBy('post_media.id')->select('post_media.path as value'),
            DB::table('post_media')->join('posts', 'posts.id', '=', 'post_media.post_id')->where('posts.user_id', $userId)->whereNotNull('post_media.thumbnail_path')->orderBy('post_media.id')->select('post_media.thumbnail_path as value'),
            DB::table('messages')->where('user_id', $userId)->whereNotNull('media_id')->orderBy('id')->select('media_id as value'),
            DB::table('stories')->where('user_id', $userId)->orderBy('id')->select('media_id as value'),
            DB::table('users')->where('id', $userId)->whereNotNull('avatar')->select('avatar as value'),
        ];
        foreach ($sources as $source) {
            $values = $source->limit(self::LIMIT + 1)->pluck('value');
            $truncated = $truncated || $values->count() > self::LIMIT;
            foreach ($values->take(self::LIMIT) as $value) $paths[] = $value;
        }
        $paths = array_values(array_unique($paths)); $ids = []; $unsupported = 0;
        foreach ($paths as $path) {
            if (is_string($path) && Str::isUuid($path)) $ids[] = $path;
            else $unsupported++;
        }
        sort($ids);
        $truncated = $truncated || count($ids) > self::LIMIT;
        $ids = array_slice($ids, 0, self::LIMIT);
        $shared = [];
        if ($ids) {
            $queries = [
                DB::table('users')->where('id', '!=', $userId)->whereIn('avatar', $ids)->select('avatar as value'),
                DB::table('messages')->where('user_id', '!=', $userId)->whereIn('media_id', $ids)->select('media_id as value'),
                DB::table('stories')->where('user_id', '!=', $userId)->whereIn('media_id', $ids)->select('media_id as value'),
                DB::table('post_media')->join('posts', 'posts.id', '=', 'post_media.post_id')->where('posts.user_id', '!=', $userId)->whereIn('post_media.path', $ids)->select('post_media.path as value'),
                DB::table('post_media')->join('posts', 'posts.id', '=', 'post_media.post_id')->where('posts.user_id', '!=', $userId)->whereIn('post_media.thumbnail_path', $ids)->select('post_media.thumbnail_path as value'),
            ];
            foreach ($queries as $query) foreach ($query->distinct()->pluck('value') as $value) $shared[$value] = true;
        }
        $counts = ['db' => 0, 'b2' => 0, 'other_storage' => 0, 'private_db_without_observed_other_member_reference' => 0];
        $blobs = $ids ? DB::table('media_blobs')->whereIn('public_id', $ids)->get(['public_id', 'storage', 'is_private']) : collect();
        foreach ($blobs as $blob) {
            $counts[in_array($blob->storage, ['db', 'b2'], true) ? $blob->storage : 'other_storage']++;
            if ($blob->storage === 'db' && $blob->is_private && ! isset($shared[$blob->public_id])) $counts['private_db_without_observed_other_member_reference']++;
        }
        return ['candidate_ids_inspected' => count($ids), 'candidate_sample_truncated' => $truncated, 'unsupported_reference_shapes' => $unsupported,
            'other_member_referenced_candidates' => count($shared), 'missing_blob_rows_in_sample' => count($ids) - $blobs->count(), 'storage_counts' => $counts,
            'scope' => 'Bounded DB reference sample, not a consistent snapshot, provider object inventory or erasure eligibility decision',
            'inventory_complete' => false, 'deletion_allowed' => false];
    }
}
