<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gifts', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('receiver_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('post_id')->nullable()->constrained('posts')->nullOnDelete();
            $table->string('gift', 16);
            $table->unsignedInteger('coins');
            $table->timestamps();
            $table->index(['post_id', 'id']);
            $table->index(['receiver_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gifts');
    }
};
