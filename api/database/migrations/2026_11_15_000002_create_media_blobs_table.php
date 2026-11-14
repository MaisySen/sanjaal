<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Media lives in the database on the free tier (no separate object store).
        Schema::create('media_blobs', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->string('mime', 60);
            $table->unsignedBigInteger('size');
            $table->longText('data'); // base64
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('media_blobs');
    }
};
