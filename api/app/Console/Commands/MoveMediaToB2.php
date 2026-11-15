<?php

namespace App\Console\Commands;

use App\Support\MediaStore;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** Moves media rows still stored in the database to Backblaze B2, one row at a time, keeping the row if anything fails. */
class MoveMediaToB2 extends Command
{
    protected $signature = 'media:move-to-b2 {--limit=100 : rows per run} {--dry-run}';

    protected $description = 'Copy database-stored media to B2 and empty the database copy once the upload succeeded';

    public function handle(): int
    {
        if (! MediaStore::enabled()) {
            $this->error('B2 is not configured.');

            return self::FAILURE;
        }
        $rows = DB::table('media_blobs')->where('storage', 'db')->orderBy('id')->limit((int) $this->option('limit'))->get(['public_id', 'mime', 'size', 'data']);
        $moved = 0;
        $failed = 0;
        foreach ($rows as $row) {
            $bytes = base64_decode((string) $row->data, true);
            if ($bytes === false || strlen($bytes) !== (int) $row->size) {
                $this->warn("skip {$row->public_id}: stored bytes do not match recorded size");
                $failed++;

                continue;
            }
            if ($this->option('dry-run')) {
                $moved++;

                continue;
            }
            try {
                MediaStore::uploadExisting($row->public_id, $row->mime, $bytes);
                if (! MediaStore::verifyRemote($row->public_id, $bytes)) {
                    $this->warn("read-back mismatch {$row->public_id}: database copy kept");
                    $failed++;

                    continue;
                }
                DB::table('media_blobs')->where('public_id', $row->public_id)->where('storage', 'db')
                    ->update(['storage' => 'b2', 'data' => '', 'updated_at' => now()]);
                $moved++;
            } catch (\Throwable $e) {
                $this->warn("failed {$row->public_id}: ".get_class($e));
                $failed++;
            }
        }
        $this->info(($this->option('dry-run') ? 'would move ' : 'moved ').$moved.', failed '.$failed.', remaining '.DB::table('media_blobs')->where('storage', 'db')->count());

        return $failed ? self::FAILURE : self::SUCCESS;
    }
}
