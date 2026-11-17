<?php

namespace App\Support;

use App\Http\Resources\Present;
use Illuminate\Support\Facades\DB;

class StoryAudience
{
    /** Dynamic policy, including follow removal, blocks, hide and close-friend removal. */
    public static function visible($story, int $viewer): bool
    {
        $owner = (int) $story->user_id;
        if ($owner === $viewer) {
            return true;
        }
        if (in_array($owner, Present::hiddenAuthors([$viewer]), true)) {
            return false;
        }
        if (! (bool) $story->protected_media) {
            return true;
        } // Never promise revocation of old public bytes.
        $r = DB::table('story_relationships')->where(['owner_id' => $owner, 'member_id' => $viewer])->first();
        if ($r && $r->hide_story) {
            return false;
        }
        if ($story->audience === 'close_friends') {
            return $r && (bool) $r->close_friend;
        }
        if ($story->audience === 'only_me') {
            return false;
        }

        if ($story->audience !== 'followers') {
            return false;
        }

        return DB::table('follows')->where(['follower_id' => $viewer, 'followee_id' => $owner])->exists();
    }

    public static function filter($query, int $viewer): void
    {
        $query->where(function ($q) use ($viewer) {
            $q->where('user_id', $viewer)->orWhere(function ($q) use ($viewer) {
                $q->where('protected_media', false)->orWhere(function ($q) use ($viewer) {
                    $q->where('protected_media', true)->whereNotExists(function ($q) use ($viewer) {
                        $q->selectRaw('1')->from('story_relationships as sr')->whereColumn('sr.owner_id', 'stories.user_id')->where('sr.member_id', $viewer)->where('sr.hide_story', true);
                    })
                        ->where(function ($q) use ($viewer) {
                            $q->where(function ($q) use ($viewer) {
                                $q->where('audience', 'followers')->whereExists(function ($q) use ($viewer) {
                                    $q->selectRaw('1')->from('follows as sf')->whereColumn('sf.followee_id', 'stories.user_id')->where('sf.follower_id', $viewer);
                                });
                            })
                                ->orWhere(function ($q) use ($viewer) {
                                    $q->where('audience', 'close_friends')->whereExists(function ($q) use ($viewer) {
                                        $q->selectRaw('1')->from('story_relationships as sc')->whereColumn('sc.owner_id', 'stories.user_id')->where('sc.member_id', $viewer)->where('sc.close_friend', true);
                                    });
                                });
                        });
                });
            });
        });
    }
}
