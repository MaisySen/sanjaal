<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

/**
 * Adds a Server-Timing header: total app time, database time, query count and the time spent booting before
 * this middleware started. It is a global middleware (run first), because Laravel sorts the authentication and
 * throttle middleware ahead of group middleware: registered in the api group it missed the database connection
 * and the signed-in user lookup, so earlier "database" figures understated every authenticated request.
 */
class ServerTiming
{
    public function handle(Request $request, Closure $next): Response
    {
        $start = defined('LARAVEL_START') ? LARAVEL_START : $request->server('REQUEST_TIME_FLOAT');
        $bootMs = (microtime(true) - $start) * 1000;
        $queries = 0;
        $dbMs = 0.0;
        DB::listen(function ($q) use (&$queries, &$dbMs) {
            $queries++;
            $dbMs += $q->time;
        });
        $response = $next($request);
        $total = (microtime(true) - $start) * 1000;
        $response->headers->set('Server-Timing', sprintf('app;dur=%.0f, db;dur=%.0f;desc="%d queries", boot;dur=%.0f', $total, $dbMs, $queries, $bootMs));

        return $response;
    }
}
