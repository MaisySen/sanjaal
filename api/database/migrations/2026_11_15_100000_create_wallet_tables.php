<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->unsignedBigInteger('coin_balance')->default(0);
        });

        // Append-only ledger. amount is signed coins. The balance on users is a cache of the sum.
        Schema::create('wallet_entries', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('kind', 24); // topup, transfer_in, transfer_out
            $table->bigInteger('amount');
            $table->unsignedBigInteger('balance_after');
            $table->foreignId('counterparty_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('reference', 80)->nullable()->unique();
            $table->string('note', 140)->nullable();
            $table->timestamps();
            $table->index(['user_id', 'id']);
        });

        // One row per eSewa top up attempt. Coins are credited once, when the payment verifies.
        Schema::create('wallet_topups', function (Blueprint $table) {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('provider', 16);
            $table->unsignedBigInteger('amount'); // NPR, whole rupees, 1 rupee = 1 coin
            $table->string('status', 16)->default('pending'); // pending, completed, failed
            $table->string('provider_ref', 80)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wallet_topups');
        Schema::dropIfExists('wallet_entries');
        Schema::table('users', fn (Blueprint $t) => $t->dropColumn('coin_balance'));
    }
};
