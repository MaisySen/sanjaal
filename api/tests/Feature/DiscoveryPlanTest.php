<?php
namespace Tests\Feature;
use App\Support\DiscoveryCatalog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Optional synthetic local measurements, never a device latency claim. */
class DiscoveryPlanTest extends TestCase
{
    use RefreshDatabase;
    public function test_optional_synthetic_postgres_plan(): void
    {
        $destination=getenv('DISCOVERY_PLAN_CAPTURE');
        if (!$destination || DB::getDriverName() !== 'pgsql') $this->markTestSkipped('Explicit local PostgreSQL plan capture required.');
        // Extracted local PostgreSQL has no optional LLVM runtime.
        DB::statement('SET jit = off');
        [$owner]=$this->member('planfixture');
        config(['app.key'=>'local-fixture-cursor-key-not-a-secret']);
        DB::statement("INSERT INTO posts (public_id,user_id,body,kind,created_at,updated_at) SELECT md5('plan-post-'||i)::uuid, ?, 'Synthetic plan fixture', 'post', now(), now() FROM generate_series(1,10000) i",[$owner->id]);
        DB::statement("INSERT INTO media_blobs (public_id,mime,size,data,storage,is_private,created_at,updated_at) SELECT md5('plan-media-'||id)::uuid,'image/png',8,'Zml4dHVyZSE=','db',false,now(),now() FROM posts WHERE user_id=?",[$owner->id]);
        DB::statement("INSERT INTO post_media (post_id,type,path,mime,size,created_at,updated_at) SELECT id,'image',md5('plan-media-'||id),'image/png',8,now(),now() FROM posts WHERE user_id=?",[$owner->id]);
        DB::statement("UPDATE post_media SET path=substr(path,1,8)||'-'||substr(path,9,4)||'-'||substr(path,13,4)||'-'||substr(path,17,4)||'-'||substr(path,21,12)");
        DB::statement("INSERT INTO discovery_eligibility (post_id,author_opted_in,public_post,moderation,revision,created_at,updated_at) SELECT id,true,true,'approved',0,now(),now() FROM posts WHERE user_id=?",[$owner->id]);
        foreach (['posts','media_blobs','post_media','discovery_eligibility','blocks','stories','messages'] as $table) DB::statement('ANALYZE '.$table);
        $catalog=new DiscoveryCatalog; $measurements=[];
        foreach (['dense','sparse','protected_sources'] as $shape) {
            if($shape==='sparse') { DB::statement('UPDATE discovery_eligibility SET author_opted_in=(post_id % 100 = 0)'); DB::statement('ANALYZE discovery_eligibility'); }
            if ($shape==='protected_sources') {
                $conversation=DB::table('conversations')->insertGetId(['public_id'=>(string) \Illuminate\Support\Str::uuid(),'type'=>'group','created_by'=>$owner->id,'created_at'=>now(),'updated_at'=>now()]);
                DB::statement("INSERT INTO stories (public_id,user_id,media_id,media_mime,protected_media,audience,expires_at,created_at,updated_at) SELECT md5('plan-story-'||i)::uuid, ?, md5(CASE WHEN i % 7=0 THEN 'plan-media-'||i ELSE 'unrelated-story-media-'||i END)::uuid, 'image/png', true,'only_me',now()+interval '1 hour',now(),now() FROM generate_series(1,10000) i",[$owner->id]);
                DB::statement("INSERT INTO messages (public_id,conversation_id,user_id,body,kind,media_id,created_at,updated_at) SELECT md5('plan-chat-'||i)::uuid, ?, ?, '', 'image', md5(CASE WHEN i % 11=0 THEN 'plan-media-'||i ELSE 'unrelated-chat-media-'||i END)::uuid,now(),now() FROM generate_series(1,10000) i",[$conversation,$owner->id]);
                DB::statement('ANALYZE stories');DB::statement('ANALYZE messages');
            }
            $samples=[];
            for($i=0;$i<5;$i++) { $start=hrtime(true);$page=$catalog->page($owner);$samples[]=(hrtime(true)-$start)/1e6; $this->assertCount(15,$page['data']); }
            DB::enableQueryLog();DB::flushQueryLog();$catalog->page($owner);$query=DB::getQueryLog()[0];DB::disableQueryLog();
            $plan=DB::select('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '.$query['query'],$query['bindings']);
            $measurements[$shape]=['fixture_posts'=>10000,'php_page_ms'=>$samples,'plan'=>json_decode($plan[0]->{'QUERY PLAN'},true),'query'=>$query['query']];
        }
        file_put_contents($destination,json_encode($measurements,JSON_PRETTY_PRINT|JSON_THROW_ON_ERROR));
    }
}
