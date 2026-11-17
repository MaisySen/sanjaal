<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('media_blobs', fn (Blueprint $t) => $t->boolean('is_private')->default(false));
        DB::table('media_blobs')->where(function ($q) {
            $q->whereIn('public_id', DB::table('messages')->whereNotNull('media_id')->select('media_id'))
                ->orWhereIn('public_id', DB::table('stories')->where('protected_media', true)->select('media_id'));
        })->update(['is_private' => true]);
    }

    public function down(): void
    {
        Schema::table('media_blobs', fn (Blueprint $t) => $t->dropColumn('is_private'));
    }
};
