<?php

namespace App\Http\Middleware;

use App\Support\ConnectionTiming;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Source-only experiment. Not registered in bootstrap/app.php. */
final class ConnectionTimingWindow
{
    public function __construct(private ConnectionTiming $timing) {}

    public function handle(Request $request, Closure $next): Response
    {
        $this->timing->begin();
        try {
            $response = $next($request);
        } finally {
            $result = $this->timing->finish();
        }
        // Connector work is nested in db duration, not an extra additive phase.
        $response->headers->set('Server-Timing', sprintf('connect;dur=%.3f;desc="%d connector calls"', $result['milliseconds'], $result['calls']), false);

        return $response;
    }
}
