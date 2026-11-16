<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/** Only enforced controls belong here. These do not make public media private. */
class MemberControls
{
    public static function get(int $owner): array
    {
        $row = DB::table('member_controls')->where('user_id', $owner)->first();
        return ['comments_from' => $row?->comments_from ?? 'everyone', 'share_to_chat' => $row ? (bool) $row->share_to_chat : true, 'revision' => $row ? (int) $row->revision : 0];
    }
    public static function canComment(int $owner, int $actor): bool
    {
        if ($owner === $actor) return true;
        return match (self::get($owner)['comments_from']) {
            'everyone' => true,
            // "People you follow" means the owner's following list, not people
            // who followed the owner without permission.
            'following' => DB::table('follows')->where(['follower_id' => $owner, 'followee_id' => $actor])->exists(),
            default => false,
        };
    }
    public static function canShare(int $owner, int $actor): bool
    {
        return $owner === $actor || self::get($owner)['share_to_chat'];
    }
}
