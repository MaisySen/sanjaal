<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Operator-only status recording. This does not remove content or notify a target. */
class ReportStatus extends Command
{
    protected $signature = 'reports:status {receipt} {status : in_review or closed}';
    protected $description = 'Record report review progress without taking content or account action';

    public function handle(): int
    {
        $status = $this->argument('status');
        if (! in_array($status, ['in_review', 'closed'], true)) {
            $this->error('Use in_review or closed.');

            return self::FAILURE;
        }
        $receipt = $this->argument('receipt');
        if (! is_string($receipt) || ! Str::isUuid($receipt)) {
            $this->error('Use a valid report receipt.');

            return self::FAILURE;
        }
        $result = DB::transaction(function () use ($status, $receipt) {
            $report = DB::table('reports')->where('public_id', $receipt)->lockForUpdate()->first();
            if (! $report) return 'missing';
            if ($report->status === $status) return 'unchanged';
            if ($report->status === 'closed') return 'closed';
            DB::table('reports')->where('id', $report->id)->update(['status' => $status, 'updated_at' => now()]);
            DB::table('report_events')->insert(['report_id' => $report->id, 'status' => $status, 'created_at' => now()]);

            return 'updated';
        });
        if (in_array($result, ['missing', 'closed'], true)) {
            $this->error($result === 'missing' ? 'Report not found.' : 'A closed review cannot be moved backwards.');

            return self::FAILURE;
        }
        $this->info('Review status recorded. No content, account or notification action was performed.');

        return self::SUCCESS;
    }
}
