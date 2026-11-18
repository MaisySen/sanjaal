<?php

namespace Tests\Feature;

use App\Models\Post;
use App\Http\Controllers\PostController;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\Support\LegacyFeedController;
use Tests\TestCase;

/** Equivalent complete read paths, not an inline query compared with an unrelated legacy query. CI only. */
class FeedPlanEvidenceTest extends TestCase
{
    use RefreshDatabase;

    public function test_equivalent_feed_paths_and_query_plans_on_larger_postgres_fixture(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') $this->markTestSkipped('PostgreSQL plan evidence only');
        $users = [];
        foreach (range(0, 11) as $i) {
            [$users[]] = $this->member('plan'.$i);
        }
        $rows = [];
        foreach (range(0, 2999) as $i) {
            $rows[] = ['public_id' => (string) Str::uuid(), 'user_id' => $users[$i % 12]->id, 'kind' => 'post', 'body' => 'Plan fixture '.$i, 'created_at' => now(), 'updated_at' => now()];
        }
        foreach (array_chunk($rows, 500) as $batch) DB::table('posts')->insert($batch);
        $likes = [];
        foreach (DB::table('posts')->pluck('id') as $id) {
            foreach (range(0, 5) as $j) $likes[] = ['post_id' => $id, 'user_id' => $users[$j]->id, 'reaction' => $j % 2 ? 'like' : 'love', 'created_at' => now(), 'updated_at' => now()];
        }
        foreach (array_chunk($likes, 1000) as $batch) DB::table('likes')->insert($batch);
        $request = Request::create('/api/v1/posts', 'GET', ['kind' => 'post']);
        $request->setUserResolver(fn () => $users[0]);
        DB::statement('analyze');
        $controllers = [new LegacyFeedController, new PostController];
        $canonical = function ($value) use (&$canonical) {
            if (!is_array($value)) return $value;
            if (!array_is_list($value)) ksort($value);
            return array_map($canonical, $value);
        };
        $legacy = $controllers[0]->index($request)->getData(true);
        $candidate = $controllers[1]->index($request)->getData(true);
        $this->assertSame($canonical($legacy), $canonical($candidate));
        $times = [[], []];
        $queries = [[], []];
        // Alternate order so one path is not always handed the warmer cache.
        foreach (range(0, 9) as $round) {
            foreach ($round % 2 ? [1, 0] : [0, 1] as $which) {
                DB::enableQueryLog(); DB::flushQueryLog();
                $start = hrtime(true);
                $controllers[$which]->index($request);
                $times[$which][] = (hrtime(true) - $start) / 1e6;
                $queries[$which] = DB::getQueryLog();
                DB::disableQueryLog();
            }
        }
        foreach ($times as &$values) sort($values);
        unset($values);
        fwrite(STDERR, "\nEQUIVALENT-FEED local-PG full-controller median-ms legacy=".$times[0][5].' candidate='.$times[1][5].' query-counts='.count($queries[0]).'/'.count($queries[1])."; not production latency\n");
        foreach ($queries as $which => $list) {
            foreach ($list as $query) {
                if (!str_starts_with(strtolower($query['query']), 'select')) continue;
                $plan = DB::select('explain (analyze, buffers, format json) '.$query['query'], $query['bindings']);
                $json = json_decode(current((array) $plan[0]), true)[0];
                fwrite(STDERR, 'FEED-PLAN path='.$which.' execution-ms='.$json['Execution Time'].' planning-ms='.$json['Planning Time'].' root='.$json['Plan']['Node Type']."\n");
            }
        }
        $this->assertCount(count($queries[0]) - 2, $queries[1]);
    }
}
