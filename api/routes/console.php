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
