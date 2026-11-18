<?php

namespace App\Support;

use Illuminate\Database\Connectors\ConnectorInterface;

/** Source-only experiment. Not registered in the container. Times connector work, not network handshake alone. */
final class MeasuredConnector implements ConnectorInterface
{
    public int $calls = 0;
    public float $milliseconds = 0.0;

    public function __construct(private ConnectorInterface $inner) {}

    public function connect(array $config)
    {
        $start = hrtime(true);
        try {
            return $this->inner->connect($config);
        } finally {
            $this->calls++;
            $this->milliseconds += (hrtime(true) - $start) / 1e6;
        }
    }
}
