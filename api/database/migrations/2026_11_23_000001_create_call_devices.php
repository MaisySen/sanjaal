<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('call_devices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('transport', 16);
            $table->text('token');
            $table->string('environment', 16)->nullable();
            $table->string('token_hash', 64)->unique();
            $table->uuid('login_lease');
            $table->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('call_devices'); }
};
