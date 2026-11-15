<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('rooms', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('host_id')->constrained('users')->cascadeOnDelete();
            $table->string('title', 80);
            $table->string('status', 8)->default('live');
            $table->timestamp('ended_at')->nullable();
            $table->timestamps();
            $table->index(['status', 'id']);
        });
        Schema::table('gifts', function (Blueprint $table) {
            $table->foreignId('room_id')->nullable()->constrained('rooms')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('gifts', fn (Blueprint $t) => $t->dropConstrainedForeignId('room_id'));
        Schema::dropIfExists('rooms');
    }
};
