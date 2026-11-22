<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('reports', function (Blueprint $table) {
            $table->uuid('public_id')->nullable()->unique();
            $table->string('status', 16)->default('received');
            $table->index(['reporter_id', 'id']);
        });
        Schema::create('report_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('report_id')->constrained('reports')->cascadeOnDelete();
            $table->string('status', 16);
            $table->timestamp('created_at')->nullable();
        });
        // Existing submissions receive a receipt, not a fabricated review outcome.
        DB::table('reports')->orderBy('id')->chunkById(200, function ($reports) {
            foreach ($reports as $report) {
                DB::table('reports')->where('id', $report->id)->update(['public_id' => (string) Str::uuid()]);
                DB::table('report_events')->insert(['report_id' => $report->id, 'status' => 'received', 'created_at' => $report->created_at]);
            }
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('report_events');
        Schema::table('reports', function (Blueprint $table) {
            $table->dropIndex(['reporter_id', 'id']);
            $table->dropUnique(['public_id']);
            $table->dropColumn(['public_id', 'status']);
        });
    }
};
