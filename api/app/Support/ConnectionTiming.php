<?php

namespace App\Support;

/** Explicit request window. Source-only, no production container binding or middleware registration. */
final class ConnectionTiming
{
    private bool $active = false;
    private int $calls = 0;
    private float $milliseconds = 0.0;

    public function begin(): void
    {
        if ($this->active) {
            throw new \LogicException('Connection timing windows must not overlap.');
        }
        $this->calls = 0;
        $this->milliseconds = 0.0;
        $this->active = true;
    }

    public function record(float $milliseconds): void
    {
        if ($this->active) {
            $this->calls++;
            $this->milliseconds += $milliseconds;
        }
    }

    /** @return array{calls:int, milliseconds:float} */
    public function finish(): array
    {
        $result = ['calls' => $this->calls, 'milliseconds' => $this->milliseconds];
        $this->active = false;
        $this->calls = 0;
        $this->milliseconds = 0.0;

        return $result;
    }
}
