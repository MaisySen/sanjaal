<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('upload_receipts', function (Blueprint $t) {
            $t->id();
            $t->foreignId('user_id')->constrained()->cascadeOnDelete();
            $t->string('operation', 12);
            $t->string('intent_id', 80);
            $t->char('fingerprint', 64);
            $t->uuid('resource_id');
            $t->timestamps();
            $t->unique(['user_id', 'operation', 'intent_id']);
        });
    }
    public function down(): void
    {
        // Once used, losing tombstones would let delayed retries recreate content.
        if (Schema::hasTable('upload_receipts') && \Illuminate\Support\Facades\DB::table('upload_receipts')->exists()) {
            throw new \LogicException('Upload receipts are in use. Preserve them before any rollback.');
        }
        Schema::dropIfExists('upload_receipts');
    }
};
