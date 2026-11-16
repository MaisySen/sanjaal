<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // One row per cash-out request. Coins are held (debited into the ledger) when the request is made,
        // and released exactly once if it is canceled or fails. States: requested, processing, paid, failed, canceled.
        Schema::create('wallet_withdrawals', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('client_id', 64);
            $table->unsignedBigInteger('coins');
            $table->string('status', 16)->default('requested');
            $table->string('provider', 24)->nullable();
            $table->string('provider_ref', 80)->nullable();
            $table->string('failure_reason', 140)->nullable();
            $table->timestamps();
            $table->unique(['user_id', 'client_id']);
            $table->index(['status', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wallet_withdrawals');
    }
};
