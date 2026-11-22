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
        Schema::table('reports', function (Blueprint $table) {
            $table->uuid('submission_id')->nullable();
            $table->char('submission_fingerprint', 64)->nullable();
            $table->unique(['reporter_id', 'submission_id']);
        });
    }

    public function down(): void
    {
        Schema::table('reports', function (Blueprint $table) {
            $table->dropUnique(['reporter_id', 'submission_id']);
            $table->dropColumn(['submission_id', 'submission_fingerprint']);
        });
    }
};
