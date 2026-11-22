<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Private operator queue, not a member API or an automated moderation worker. */
class ReportQueue extends Command
{
    protected $signature = 'reports:queue {--limit=20} {--after=}';
    protected $description = 'Read a bounded queue of received/in-review reports without changing them';

    public function handle(): int
    {
        $limit = filter_var($this->option('limit'), FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 50]]);
        $after = $this->option('after');
        if ($limit === false || ($after && ! Str::isUuid($after))) {
            $this->error('Use a limit from 1 to 50 and a valid receipt cursor.');

            return self::FAILURE;
        }
        $query = DB::table('reports')->whereIn('status', ['received', 'in_review']);
        if ($after) {
            $boundary = DB::table('reports')->where('public_id', $after)->value('id');
            if (! $boundary) {
                $this->error('Receipt cursor not found.');

                return self::FAILURE;
            }
            $query->where('id', '>', $boundary);
        }
        $columns = ['public_id', 'target_type', 'target_id as submitted_reference', 'reason', 'note', 'status', 'created_at'];
        if (\Illuminate\Support\Facades\Schema::hasColumn('reports', 'target_public_id')) $columns[] = 'target_public_id';
        $rows = $query->orderBy('id')->limit($limit + 1)->get($columns);
        $more = $rows->count() > $limit;
        $rows = $rows->take($limit)->values();
        $this->line(json_encode(['data' => $rows->all(), 'next_cursor' => $more ? $rows->last()->public_id : null], JSON_THROW_ON_ERROR));

        return self::SUCCESS;
    }
}
