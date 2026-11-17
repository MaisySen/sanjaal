<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * One request for the three reads the Home screen makes on open. Each part is produced by the same
 * controller method that serves its own endpoint, so every access, block and audience check is the
 * ordinary one and nothing is cached. It exists to save per-request overhead on a small host.
 */
class HomeController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $feedRequest = $request->duplicate(['kind' => 'post'], []);
        $feedRequest->setUserResolver($request->getUserResolver());

        return response()->json([
            'feed' => app(PostController::class)->index($feedRequest)->getData(true),
            'stories' => app(ExtrasController::class)->stories($request)->getData(true),
            'unread_messages' => app(ChatController::class)->summary($request)->getData(true)['unread_messages'],
        ])->header('Cache-Control', 'private, no-store');
    }
}
