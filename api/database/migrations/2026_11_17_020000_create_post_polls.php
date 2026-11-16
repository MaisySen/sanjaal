<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('posts', fn (Blueprint $t) => $t->json('poll_options')->nullable());
        Schema::create('poll_votes', function (Blueprint $t) {
            $t->id();
            $t->foreignId('post_id')->constrained()->cascadeOnDelete();
            $t->foreignId('user_id')->constrained()->cascadeOnDelete();
            $t->unsignedTinyInteger('choice');
            $t->timestamps();
            $t->unique(['post_id', 'user_id']);
            $t->index(['post_id', 'choice']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('poll_votes');
        Schema::table('posts', fn (Blueprint $t) => $t->dropColumn('poll_options'));
    }
};
