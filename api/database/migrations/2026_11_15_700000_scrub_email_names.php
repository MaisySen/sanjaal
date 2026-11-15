<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /** Early sign-ups stored the email address as the display name. Replace it with the username. */
    public function up(): void
    {
        DB::table('users')->where('name', 'like', '%@%')->update(['name' => DB::raw('username')]);
    }

    public function down(): void
    {
    }
};
