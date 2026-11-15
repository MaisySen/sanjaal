<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('likes', function (Blueprint $t) {
            $t->string('reaction', 10)->default('like');
        });
        Schema::table('messages', function (Blueprint $t) {
            $t->string('kind', 10)->default('text'); // text | image | voice
            $t->uuid('media_id')->nullable();
            $t->string('media_mime', 60)->nullable();
            $t->unsignedInteger('duration_ms')->nullable();
            $t->unsignedBigInteger('reply_to_id')->nullable();
        });
        Schema::table('conversation_members', function (Blueprint $t) {
            $t->boolean('pinned')->default(false);
            $t->boolean('muted')->default(false);
            $t->boolean('archived')->default(false);
        });
        Schema::create('stories', function (Blueprint $t) {
            $t->id();
            $t->uuid('public_id')->unique();
            $t->foreignId('user_id')->constrained()->cascadeOnDelete();
            $t->uuid('media_id');
            $t->string('media_mime', 60);
            $t->string('caption', 200)->nullable();
            $t->timestamp('expires_at')->index();
            $t->timestamps();
        });
        Schema::create('story_views', function (Blueprint $t) {
            $t->id();
            $t->foreignId('story_id')->constrained()->cascadeOnDelete();
            $t->foreignId('user_id')->constrained()->cascadeOnDelete();
            $t->timestamps();
            $t->unique(['story_id', 'user_id']);
        });
        Schema::create('calls', function (Blueprint $t) {
            $t->id();
            $t->uuid('public_id')->unique();
            $t->foreignId('conversation_id')->constrained()->cascadeOnDelete();
            $t->foreignId('caller_id')->constrained('users')->cascadeOnDelete();
            $t->string('kind', 10); // voice | video
            $t->string('status', 10)->default('ringing'); // ringing | answered | missed | ended | declined
            $t->timestamp('answered_at')->nullable();
            $t->timestamp('ended_at')->nullable();
            $t->timestamps();
            $t->index(['conversation_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('calls');
        Schema::dropIfExists('story_views');
        Schema::dropIfExists('stories');
    }
};
