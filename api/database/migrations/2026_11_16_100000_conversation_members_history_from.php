<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** People added to a group later see messages from the moment they joined, not the earlier history. */
    public function up(): void
    {
        Schema::table('conversation_members', function (Blueprint $t) {
            $t->unsignedBigInteger('history_from_id')->default(0);
        });
    }

    public function down(): void
    {
        Schema::table('conversation_members', function (Blueprint $t) {
            $t->dropColumn('history_from_id');
        });
    }
};
