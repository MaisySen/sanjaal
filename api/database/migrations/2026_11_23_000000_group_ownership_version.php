<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // PostgreSQL migrations run in a transaction. Bound the exclusive DDL
        // wait and statement so a busy conversation table fails deployment
        // instead of queuing unbounded locks ahead of live requests.
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("SET LOCAL lock_timeout = '2s'");
            DB::statement("SET LOCAL statement_timeout = '5s'");
        }
        Schema::table('conversations', function (Blueprint $table) {
            $table->unsignedBigInteger('ownership_version')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('conversations', fn (Blueprint $table) => $table->dropColumn('ownership_version'));
    }
};
