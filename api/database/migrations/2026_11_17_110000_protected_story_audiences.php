<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stories', function (Blueprint $t) {
            $t->boolean('protected_media')->default(false);
            $t->string('audience', 20)->default('followers');
        });
        Schema::create('story_relationships', function (Blueprint $t) {
            $t->foreignId('owner_id')->constrained('users')->cascadeOnDelete();
            $t->foreignId('member_id')->constrained('users')->cascadeOnDelete();
            $t->boolean('close_friend')->default(false);
            $t->boolean('hide_story')->default(false);
            $t->unsignedBigInteger('revision')->default(0);
            $t->timestamps();
            $t->primary(['owner_id', 'member_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('story_relationships');
        Schema::table('stories', fn (Blueprint $t) => $t->dropColumn(['protected_media', 'audience']));
    }
};
