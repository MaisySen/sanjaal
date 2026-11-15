<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('media_blobs', function (Blueprint $table) {
            $table->string('storage', 8)->default('db')->after('size');
        });
    }

    public function down(): void
    {
        Schema::table('media_blobs', function (Blueprint $table) {
            $table->dropColumn('storage');
        });
    }
};
