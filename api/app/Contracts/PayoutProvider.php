<?php

namespace App\Contracts;

/**
 * A real payout rail (bank, wallet, partner). No implementation ships enabled: the default is
 * App\Services\DisabledPayout. Implementations must be idempotent on $withdrawalId, so a retry after a
 * timeout never pays twice, and must say plainly whether a payment is paid, pending or failed.
 */
interface PayoutProvider
{
    public function name(): string;

    /** True only when real, authorized configuration exists. */
    public function enabled(): bool;

    /** @return array{status: 'paid'|'pending'|'failed', ref?: string, reason?: string} */
    public function pay(string $withdrawalId, int $coins): array;
}
