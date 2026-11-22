<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Local-only candidate. No consent backfill and no production migration run.
return new class extends Migration {
    public function up(): void
    {
        Schema::create('discovery_eligibility', function (Blueprint $t) {
            $t->foreignId('post_id')->primary()->constrained()->cascadeOnDelete();
            $t->boolean('author_opted_in')->default(false);
            $t->boolean('public_post')->default(false);
            $t->string('moderation', 16)->default('pending');
            $t->unsignedBigInteger('revision')->default(0);
            $t->timestamps();
        });
    }
    public function down(): void { Schema::dropIfExists('discovery_eligibility'); }
};
