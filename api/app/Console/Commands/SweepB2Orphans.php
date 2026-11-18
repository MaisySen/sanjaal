<?php

namespace App\Console\Commands;

use App\Support\MediaStore;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Reports bucket objects written by the keyed-upload protocol that no media row references (a crash between upload and commit). Report only: it never deletes. */
class SweepB2Orphans extends Command
{
    protected $signature = 'media:sweep-b2-orphans {--hours=24 : only objects older than this, at least 1} {--limit=200 : report at most this many, 1 to 1000}';

    protected $description = 'Report keyed-protocol B2 objects older than the grace period that no media_blobs row references';

    public function handle(): int
    {
        $hours = filter_var($this->option('hours'), FILTER_VALIDATE_INT);
        $limit = filter_var($this->option('limit'), FILTER_VALIDATE_INT);
        if ($hours === false || $hours < 1 || $limit === false || $limit < 1 || $limit > 1000) {
            $this->error('Hours must be at least 1 and limit between 1 and 1000.');

            return self::FAILURE;
        }
        if (! MediaStore::enabled()) {
            $this->error('B2 is not configured.');

            return self::FAILURE;
        }
        $cutoffMs = (now()->subHours($hours)->getTimestamp()) * 1000;
        $found = 0;
        $bytes = 0;
        foreach (MediaStore::listObjects() as $o) {
            // Only objects this protocol wrote (marker set at upload), old enough that no upload can still be committing.
            if ($o['protocol'] !== MediaStore::PROTOCOL || ! Str::isUuid($o['name']) || $o['uploaded_ms'] > $cutoffMs) {
                continue;
            }
            if (DB::table('media_blobs')->where('public_id', $o['name'])->exists()) {
                continue;
            }
            $found++;
            $bytes += $o['size'];
            if ($found >= $limit) {
                break;
            }
        }
        // Rows left behind by a failed upload or commit: counted against the budget, never served.
        $cutoff = now()->subHours($hours);
        $stranded = DB::table('media_blobs as m')->where('m.storage', 'b2')->where('m.created_at', '<', $cutoff)
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('post_media')->whereRaw('CAST(post_media.path AS VARCHAR(64)) = CAST(m.public_id AS VARCHAR(64))'))
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('post_media')->whereRaw('CAST(post_media.thumbnail_path AS VARCHAR(64)) = CAST(m.public_id AS VARCHAR(64))'))
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('messages')->whereRaw('CAST(messages.media_id AS VARCHAR(64)) = CAST(m.public_id AS VARCHAR(64))'))
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('stories')->whereRaw('CAST(stories.media_id AS VARCHAR(64)) = CAST(m.public_id AS VARCHAR(64))'))
            ->whereNotExists(fn ($q) => $q->selectRaw('1')->from('users')->whereRaw('CAST(users.avatar AS VARCHAR(64)) = CAST(m.public_id AS VARCHAR(64))'))
            ->selectRaw('COUNT(*) AS n, COALESCE(SUM(m.size), 0) AS bytes')->first();
        $this->info(sprintf('report only: %d unreferenced B2 media row(s), %d bytes counted against the budget.', $stranded->n, $stranded->bytes));
        $this->info(sprintf('report only: %d unreferenced keyed-upload object(s), %d bytes. Nothing was deleted.', $found, $bytes));

        return self::SUCCESS;
    }
}
