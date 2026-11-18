<?php

namespace App\Console\Commands;

use App\Support\MediaStore;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Finds bucket objects no media row references (a crash between upload and commit). Dry-run by default. */
class SweepB2Orphans extends Command
{
    protected $signature = 'media:sweep-b2-orphans {--hours=24 : only objects older than this, at least 1} {--limit=200 : at most this many deletions, 1 to 1000} {--apply : delete; default is dry-run}';

    protected $description = 'Preview or delete B2 objects with a UUID name that no media_blobs row references';

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
        $deleted = 0;
        foreach (MediaStore::listObjects() as $o) {
            // Only generated media names, only old enough that no upload can still be committing.
            if (! Str::isUuid($o['name']) || $o['uploaded_ms'] > $cutoffMs) {
                continue;
            }
            if (DB::table('media_blobs')->where('public_id', $o['name'])->exists()) {
                continue;
            }
            $found++;
            $bytes += $o['size'];
            if ($this->option('apply') && $deleted < $limit) {
                // Recheck at deletion time.
                if (! DB::table('media_blobs')->where('public_id', $o['name'])->exists()) {
                    MediaStore::removeObject($o['name']);
                    $deleted++;
                }
            }
            if ($found >= $limit) {
                break;
            }
        }
        $this->info(sprintf('%s: %d orphan object(s), %d bytes%s.', $this->option('apply') ? 'applied' : 'dry-run', $found, $bytes, $this->option('apply') ? ", $deleted deleted" : ''));

        return self::SUCCESS;
    }
}
