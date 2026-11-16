<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('member_controls', function (Blueprint $table) {
            $table->foreignId('user_id')->primary()->constrained('users')->cascadeOnDelete();
            $table->string('comments_from', 16)->default('everyone');
            $table->boolean('share_to_chat')->default(true);
            $table->unsignedBigInteger('revision')->default(0);
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('member_controls'); }
};
