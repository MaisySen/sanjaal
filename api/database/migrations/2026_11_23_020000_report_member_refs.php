<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement("SET LOCAL lock_timeout = '2s'");
            DB::statement("SET LOCAL statement_timeout = '5s'");
        }
        Schema::table('reports', fn (Blueprint $table) => $table->uuid('target_public_id')->nullable());
    }

    public function down(): void
    {
        Schema::table('reports', fn (Blueprint $table) => $table->dropColumn('target_public_id'));
    }
};
