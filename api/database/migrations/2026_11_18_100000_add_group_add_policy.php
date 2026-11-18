<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Additive: one column with a default, so existing groups keep today's behaviour ('members' = any member can add people)
 * and code from before this migration keeps working against the new column.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('conversations', fn (Blueprint $table) => $table->string('add_policy', 16)->default('members'));
    }

    public function down(): void
    {
        if (DB::table('conversations')->where('add_policy', '!=', 'members')->exists()) {
            throw new LogicException('Preserve owner-only group settings before rollback.');
        }
        Schema::table('conversations', fn (Blueprint $table) => $table->dropColumn('add_policy'));
    }
};
