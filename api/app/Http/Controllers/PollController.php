<?php

namespace App\Http\Controllers;

use App\Http\Resources\Present;
use App\Models\Post;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PollController extends Controller
{
    /** One choice per member. Repeating a choice is idempotent; a new choice replaces it. */
    public function vote(Request $request, string $publicId): JsonResponse
    {
        $data = $request->validate(['choice' => ['required', 'integer', 'min:0', 'max:3']]);

        return $this->change($request, $publicId, (int) $data['choice']);
    }

    public function remove(Request $request, string $publicId): JsonResponse
    {
        return $this->change($request, $publicId, null);
    }

    private function change(Request $request, string $publicId, ?int $choice): JsonResponse
    {
        $me = $request->user();
        $poll = DB::transaction(function () use ($publicId, $me, $choice) {
            // Serialize changes for the poll. The unique key also prevents multiple
            // votes for a member even if another write path is introduced later.
            $post = Post::where('public_id', $publicId)->lockForUpdate()->firstOrFail();
            abort_if(in_array($post->user_id, Present::hiddenAuthors([$me->id]), true), 404);
            abort_unless(is_array($post->poll_options), 404);
            abort_if($choice !== null && ! array_key_exists($choice, $post->poll_options), 422, 'Choose one of the poll options.');
            if ($choice === null) {
                DB::table('poll_votes')->where('post_id', $post->id)->where('user_id', $me->id)->delete();
            } else {
                DB::table('poll_votes')->upsert([
                    ['post_id' => $post->id, 'user_id' => $me->id, 'choice' => $choice, 'created_at' => now(), 'updated_at' => now()],
                ], ['post_id', 'user_id'], ['choice', 'updated_at']);
            }

            return Present::poll($post, $me);
        });

        return response()->json(['poll' => $poll]);
    }
}
