<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('account_deletion_requests', function (Blueprint $t) {
            $t->id();
            $t->uuid('public_id')->unique();
            $t->foreignId('user_id')->unique()->constrained()->restrictOnDelete();
            $t->string('status', 24)->default('requested');
            $t->string('policy_version', 80);
            $t->text('completion_notice');
            $t->text('retention_notice');
            $t->timestamps();
        });
    }
    public function down(): void
    {
        if (Schema::hasTable('account_deletion_requests') && \Illuminate\Support\Facades\DB::table('account_deletion_requests')->exists()) {
            throw new \LogicException('Deletion requests exist. Preserve the request record before rollback.');
        }
        Schema::dropIfExists('account_deletion_requests');
    }
};
