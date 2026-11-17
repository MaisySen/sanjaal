<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** Bounded database-only cleanup. No bucket calls or unclassified orphan deletion. */
class PruneExpiredStories extends Command
{
    protected $signature = 'stories:prune-expired {--limit=100 : at most 1000 protected stories} {--apply : commit deletion; default is dry-run}';

    protected $description = 'Preview or prune expired protected stories and exclusively-owned private database media';

    public function handle(): int
    {
        $limit = filter_var($this->option('limit'), FILTER_VALIDATE_INT);
        if ($limit === false || $limit < 1 || $limit > 1000) {
            $this->error('Limit must be between 1 and 1000.');

            return self::FAILURE;
        }
        $cutoff = now();
        $ids = DB::table('stories')->where('protected_media', true)->where('expires_at', '<=', $cutoff)->orderBy('id')->limit($limit)->pluck('id');
        $counts = ['stories' => 0, 'blobs' => 0, 'bytes' => 0, 'preserved' => 0];
        foreach ($ids as $id) {
            $result = DB::transaction(function () use ($id, $cutoff) {
                // Recheck the row at commit time, not just the initial candidate scan.
                $story = DB::table('stories')->where('id', $id)->where('protected_media', true)->where('expires_at', '<=', $cutoff)->lockForUpdate()->first();
                if (! $story) {
                    return null;
                }
                $blob = DB::table('media_blobs')->where('public_id', $story->media_id)->lockForUpdate()->first();
                $referenced = DB::table('stories')->where('media_id', $story->media_id)->where('id', '!=', $story->id)->exists()
                    || DB::table('messages')->where('media_id', $story->media_id)->exists()
                    || DB::table('post_media')->where(fn ($q) => $q->where('path', $story->media_id)->orWhere('thumbnail_path', $story->media_id))->exists()
                    || DB::table('users')->where('avatar', $story->media_id)->exists();
                $removeBlob = $blob && $blob->is_private && $blob->storage === 'db' && ! $referenced;
                if ($this->option('apply')) {
                    // FK cascade removes views. Durable upload receipts deliberately remain,
                    // so an old upload retry cannot publish the expired story again.
                    DB::table('stories')->where('id', $story->id)->delete();
                    if ($removeBlob) {
                        DB::table('media_blobs')->where('public_id', $story->media_id)->delete();
                    }
                }

                return ['stories' => 1, 'blobs' => $removeBlob ? 1 : 0, 'bytes' => $removeBlob ? (int) $blob->size : 0, 'preserved' => $blob && ! $removeBlob ? 1 : 0];
            });
            foreach ($result ?? [] as $key => $value) {
                $counts[$key] += $value;
            }
        }
        $this->info(($this->option('apply') ? 'Pruned ' : 'Dry-run only: ').json_encode($counts));

        return self::SUCCESS;
    }
}
