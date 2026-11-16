<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('wallet_transfers', function (Blueprint $t) {
            $t->id();
            $t->foreignId('user_id')->constrained()->cascadeOnDelete();
            $t->string('client_id', 80);
            $t->char('fingerprint', 64);
            $t->uuid('public_id')->unique();
            $t->string('recipient_id', 80);
            $t->unsignedBigInteger('amount');
            $t->unsignedBigInteger('balance_after');
            $t->timestamps();
            $t->unique(['user_id', 'client_id']);
        });
    }
    public function down(): void
    {
        if (Schema::hasTable('wallet_transfers') && DB::table('wallet_transfers')->exists()) {
            throw new \LogicException('Transfer receipts are in use. Preserve them before rollback.');
        }
        Schema::dropIfExists('wallet_transfers');
    }
};
