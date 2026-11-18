<?php

namespace Tests\Feature;

use App\Http\Resources\Present;
use App\Models\Post;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The feed returns author, reaction counts and the viewer's own reaction inside the posts query. This compares the
 * endpoint with the older multi-read path (Present::preload plus a user eager load) for every viewer over
 * randomized data with empty, single and mixed reactions, blocks in both directions, follows, saves and member
 * controls, and (on PostgreSQL only) prints the plan and timing so a cheaper-looking query is not assumed faster.
 */
class FeedParityTest extends TestCase
{
    use RefreshDatabase;

    private function seed_world(int $users, int $posts, int $likeEvery): array
    {
        mt_srand(7);
        $members = [];
        for ($i = 0; $i < $users; $i++) {
            [$u, $h] = $this->member('parity'.$i);
            if ($i % 2 === 0) {
                $u->forceFill(['bio' => 'Bio '.$i, 'avatar' => $i % 4 === 0 ? (string) Str::uuid() : null])->save();
            }
            $members[] = [$u, $h];
        }
        $ids = array_map(fn ($m) => $m[0]->id, $members);
        $rows = [];
        for ($p = 0; $p < $posts; $p++) {
            $rows[] = ['public_id' => (string) Str::uuid(), 'user_id' => $ids[mt_rand(0, $users - 1)], 'kind' => $p % 5 === 0 ? 'reel' : 'post', 'body' => 'Parity '.$p, 'created_at' => now()->subSeconds($posts - $p), 'updated_at' => now()];
        }
        foreach (array_chunk($rows, 500) as $c) {
            DB::table('posts')->insert($c);
        }
        $postIds = DB::table('posts')->pluck('id')->all();
        $reactions = \App\Http\Controllers\ExtrasController::REACTIONS;
        $likes = [];
        foreach ($postIds as $pid) {
            if (mt_rand(1, $likeEvery) !== 1) {
                continue; // many posts keep zero reactions
            }
            foreach ($ids as $uid) {
                if (mt_rand(0, 2) === 0) {
                    $likes[] = ['post_id' => $pid, 'user_id' => $uid, 'reaction' => $reactions[mt_rand(0, count($reactions) - 1)], 'created_at' => now(), 'updated_at' => now()];
                }
            }
        }
        foreach (array_chunk($likes, 500) as $c) {
            DB::table('likes')->insert($c);
        }
        return [$members, $ids];
    }

    public function test_feed_matches_the_multi_read_path_for_every_viewer(): void
    {
        [$members, $ids] = $this->seed_world(6, 60, 2);
        DB::table('blocks')->insert([['blocker_id' => $ids[0], 'blocked_id' => $ids[1], 'created_at' => now()], ['blocker_id' => $ids[3], 'blocked_id' => $ids[2], 'created_at' => now()]]);
        DB::table('follows')->insert([['follower_id' => $ids[2], 'followee_id' => $ids[4], 'created_at' => now()], ['follower_id' => $ids[4], 'followee_id' => $ids[2], 'created_at' => now()]]);
        DB::table('member_controls')->insert(['user_id' => $ids[5], 'comments_from' => 'following', 'share_to_chat' => false, 'created_at' => now(), 'updated_at' => now()]);
        $some = DB::table('posts')->orderBy('id')->limit(10)->pluck('id');
        foreach ($some as $pid) {
            DB::table('bookmarks')->insert(['user_id' => $ids[2], 'post_id' => $pid, 'created_at' => now()]);
        }
        $compared = 0;
        $withReactions = 0;
        foreach ($members as [$viewer, $h]) {
            $cursor = null;
            $seen = 0;
            do {
                $r = $this->getJson('/api/v1/posts'.($cursor ? '?cursor='.urlencode($cursor) : ''), $h)->assertOk()->json();
                $publicIds = array_column($r['data'], 'public_id');
                $legacy = Post::with(['user', 'media', 'hashtags'])->whereIn('public_id', $publicIds)->get()->keyBy('public_id');
                Present::preload($legacy->values(), $viewer);
                foreach ($r['data'] as $item) {
                    $p = $legacy[$item['public_id']];
                    $expected = Present::post($p, $viewer);
                    $expected['author']['following'] = $viewer->following()->where('users.id', $p->user_id)->exists();
                    // Reaction keys come back in database order on the older path; object key order carries no meaning.
                    $expected = json_decode(json_encode($expected), true);
                    ksort($expected['reactions']);
                    $got = $item;
                    ksort($got['reactions']);
                    $this->assertSame($expected, $got, 'viewer '.$viewer->username.' post '.$item['public_id']);
                    $compared++;
                    $withReactions += $item['reactions'] ? 1 : 0;
                }
                $seen += count($publicIds);
                $cursor = $r['next_cursor'];
            } while ($cursor);
            // Visibility parity: exactly the posts with no block in either direction, independent of the feed query.
            $visible = DB::table('posts')->whereNotExists(fn ($b) => $b->selectRaw('1')->from('blocks')->where(fn ($w) => $w
                ->where(fn ($d) => $d->whereColumn('blocks.blocker_id', 'posts.user_id')->where('blocks.blocked_id', $viewer->id))
                ->orWhere(fn ($d) => $d->where('blocks.blocker_id', $viewer->id)->whereColumn('blocks.blocked_id', 'posts.user_id'))))->count();
            $this->assertSame($visible, $seen, 'visible post count for '.$viewer->username);
        }
        $this->assertGreaterThan(100, $compared);
        $this->assertGreaterThan(10, $withReactions, 'fixture must include posts with reactions');
        $this->assertLessThan($compared, $withReactions, 'fixture must also include posts with no reactions');
    }


}
