<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('wallet:payouts', function () {
    $r = \App\Services\Withdrawals::run();
    $this->info(\App\Services\Withdrawals::enabled() ? json_encode($r) : 'Payout provider is disabled: nothing was sent.');
})->purpose('Send requested cash outs to the bound payout provider (no-op while disabled)');

Artisan::command('wallet:resolve {id} {outcome : paid or failed} {--ref=} {--confirm : I checked the provider records}', function (string $id, string $outcome) {
    if (! $this->option('confirm')) {
        $this->error('Check the provider records first, then pass --confirm.');

        return 1;
    }
    $ok = \App\Services\Withdrawals::resolveReview($id, $outcome, $this->option('ref'));
    $this->info($ok ? "Resolved as $outcome." : 'Not in review: nothing changed.');

    return $ok ? 0 : 1;
})->purpose('Settle a cash out that is in review (operator only)');
