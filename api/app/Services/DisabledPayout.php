<?php

namespace App\Services;

use App\Contracts\PayoutProvider;

/** Default provider: pays nothing and says so. Cash out stays off while this is the bound provider. */
class DisabledPayout implements PayoutProvider
{
    public function name(): string
    {
        return 'disabled';
    }

    public function enabled(): bool
    {
        return false;
    }

    public function pay(string $withdrawalId, int $coins): array
    {
        return ['status' => 'failed', 'reason' => 'No payout provider is configured.'];
    }
}
