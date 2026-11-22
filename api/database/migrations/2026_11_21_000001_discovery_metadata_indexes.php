<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

// Local candidate only. Index construction on a deployed database needs a
// separate size, lock and rollout review. No live migration is authorized.
return new class extends Migration {
    public function up(): void
    {
        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) {
            DB::statement('CREATE INDEX discovery_media_public_text ON media_blobs ((CAST(public_id AS text)))');
        }
        Schema::table('post_media', fn (Blueprint $t) => $t->index(['post_id', 'id'], 'discovery_post_preview'));
        Schema::table('stories', fn (Blueprint $t) => $t->index(['media_id', 'protected_media'], 'discovery_story_source'));
        Schema::table('messages', fn (Blueprint $t) => $t->index('media_id', 'discovery_chat_source'));
        Schema::table('discovery_eligibility', fn (Blueprint $t) => $t->index(['author_opted_in', 'public_post', 'moderation', 'post_id'], 'discovery_approved_recent'));
    }
    public function down(): void
    {
        if (in_array(DB::getDriverName(), ['pgsql', 'sqlite'], true)) DB::statement('DROP INDEX IF EXISTS discovery_media_public_text');
        Schema::table('post_media', fn (Blueprint $t) => $t->dropIndex('discovery_post_preview'));
        Schema::table('stories', fn (Blueprint $t) => $t->dropIndex('discovery_story_source'));
        Schema::table('messages', fn (Blueprint $t) => $t->dropIndex('discovery_chat_source'));
        Schema::table('discovery_eligibility', fn (Blueprint $t) => $t->dropIndex('discovery_approved_recent'));
    }
};
