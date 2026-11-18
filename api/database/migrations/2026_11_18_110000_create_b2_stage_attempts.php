<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** Additive: one reservation per physical keyed B2 upload attempt, so every retained object version is counted. */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('b2_stage_attempts', function (Blueprint $table) {
            $table->id();
            $table->string('name', 64)->index();
            $table->unsignedBigInteger('size');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('b2_stage_attempts');
    }
};
