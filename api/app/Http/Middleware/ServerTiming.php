<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/** Adds a Server-Timing header: total app time, database time and query count. */
class ServerTiming
{
    public function handle(Request $request, Closure $next): Response
    {
        $queries = 0;
        $dbMs = 0.0;
        DB::listen(function ($q) use (&$queries, &$dbMs) {
            $queries++;
            $dbMs += $q->time;
        });
        $response = $next($request);
        $total = (microtime(true) - (defined('LARAVEL_START') ? LARAVEL_START : $request->server('REQUEST_TIME_FLOAT'))) * 1000;
        $response->headers->set('Server-Timing', sprintf('app;dur=%.0f, db;dur=%.0f;desc="%d queries"', $total, $dbMs, $queries));

        return $response;
    }
}
