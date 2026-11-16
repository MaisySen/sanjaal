<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wallet_withdrawals', function (Blueprint $table) {
            // Written BEFORE the provider is called, so a crash mid-call still leaves a record that a call may have gone out.
            $table->unsignedSmallInteger('attempts')->default(0);
            $table->timestamp('last_attempt_at')->nullable();
            $table->string('review_note', 140)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('wallet_withdrawals', function (Blueprint $table) {
            $table->dropColumn(['attempts', 'last_attempt_at', 'review_note']);
        });
    }
};
