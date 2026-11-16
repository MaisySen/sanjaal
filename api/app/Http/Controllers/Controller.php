<?php

namespace App\Http\Controllers;

abstract class Controller
{
    /** One policy for direct post reads and interactions, including bookmarked IDs. */
    protected function visiblePost(\Illuminate\Http\Request $request, string $publicId): \App\Models\Post
    {
        return \App\Models\Post::where('public_id', $publicId)
            ->whereNotIn('user_id', \App\Http\Resources\Present::hiddenAuthors([$request->user()->id]))
            ->firstOrFail();
    }

    protected function cannotContact(\App\Models\User $me, int $otherId): bool
    {
        return in_array($otherId, \App\Http\Resources\Present::hiddenAuthors([$me->id]), true);
    }
}
