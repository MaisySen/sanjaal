<?php

namespace Tests\Concurrency;

use App\Contracts\PayoutProvider;

/** Test-only enabled provider for race tests. Never bound outside tests. */
class FakePayout implements PayoutProvider
{
    public function name(): string { return 'fake'; }

    public function enabled(): bool { return true; }

    public function pay(string $withdrawalId, int $coins): array { return ['status' => 'paid', 'ref' => 'FAKE']; }
}
