<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Same locked-framework PostgreSQL connector, wrapped without eager PDO resolution.
        $this->app->scoped(\App\Support\ConnectionTiming::class);
        $this->app->bind('db.connector.pgsql', fn ($app) => new \App\Support\MeasuredConnector(
            new \Illuminate\Database\Connectors\PostgresConnector,
            $app->make(\App\Support\ConnectionTiming::class),
        ));

        // Cash out is off until a real, authorized PayoutProvider is bound here.
        $this->app->singleton(\App\Contracts\PayoutProvider::class, \App\Services\DisabledPayout::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        \Illuminate\Support\Facades\Auth::viaRequest('auth0', new \App\Auth\Auth0Guard());
    }
}
