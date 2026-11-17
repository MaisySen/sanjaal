<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('post_media', fn (Blueprint $table) => $table->string('thumbnail_path')->nullable());
    }

    public function down(): void
    {
        if (DB::table('post_media')->whereNotNull('thumbnail_path')->exists()) {
            throw new LogicException('Preserve populated video poster references before rollback.');
        }
        Schema::table('post_media', fn (Blueprint $table) => $table->dropColumn('thumbnail_path'));
    }
};
