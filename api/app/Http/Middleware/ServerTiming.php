<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * Adds a Server-Timing header: total app time, database time, query count and the time spent booting before
 * this middleware started. It is a global middleware (run first), because Laravel sorts the authentication and
 * throttle middleware ahead of group middleware: registered in the api group it did not cover the signed-in
 * user lookup. dbconn (only when the request ran a query) is the time the first query waited for the database
 * connection to be opened or reused and set up (Laravel resolves the connection lazily inside the first query, so the
 * first query's own time includes it). The probe only resolves the same connection a moment earlier.
 */
class ServerTiming
{
    public function handle(Request $request, Closure $next): Response
    {
        $start = defined('LARAVEL_START') ? LARAVEL_START : $request->server('REQUEST_TIME_FLOAT');
        $bootMs = (microtime(true) - $start) * 1000;
        $queries = 0;
        $dbMs = 0.0;
        $connMs = null;
        DB::beforeExecuting(function ($query, $bindings, $connection) use (&$connMs) {
            if ($connMs === null) {
                $t = microtime(true);
                $connection->getPdo();
                $connMs = (microtime(true) - $t) * 1000;
            }
        });
        DB::listen(function ($q) use (&$queries, &$dbMs) {
            $queries++;
            $dbMs += $q->time;
        });
        $response = $next($request);
        $total = (microtime(true) - $start) * 1000;
        $header = sprintf('app;dur=%.0f, db;dur=%.0f;desc="%d queries", boot;dur=%.0f', $total, $dbMs, $queries, $bootMs);
        if ($connMs !== null) {
            $header .= sprintf(', dbconn;dur=%.0f', $connMs);
        }
        $response->headers->set('Server-Timing', $header);

        return $response;
    }
}
