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

    /**
     * Ask the rail what happened to a payment sent with this idempotency key, without sending anything.
     * 'unknown' must mean the provider positively has no record of the key. If it cannot tell (timeout, error), throw.
     * @return array{status: 'paid'|'pending'|'failed'|'unknown', ref?: string, reason?: string}
     */
    public function lookup(string $withdrawalId): array;
}
