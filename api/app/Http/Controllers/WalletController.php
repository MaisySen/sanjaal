<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Services\Esewa;
use App\Services\Wallet;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

class WalletController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $me = $request->user()->fresh();

        return response()->json([
            'balance' => (int) $me->coin_balance,
            'topup' => [
                'esewa' => Esewa::configured(),
                'esewa_mode' => config('services.esewa.env') === 'live' ? 'live' : 'test',
                'khalti' => false,
                'min' => 10,
                'max' => 100000,
            ],
            'cashout' => ['available' => \App\Services\Withdrawals::enabled(), 'min' => \App\Services\Withdrawals::MIN, 'max' => \App\Services\Withdrawals::MAX],
            'entries' => $this->entries($me->id, 20),
        ]);
    }

    public function entriesList(Request $request): JsonResponse
    {
        $before = (int) $request->query('before', 0);

        return response()->json(['data' => $this->entries($request->user()->id, 30, $before)]);
    }

    public function transfer(Request $request): JsonResponse
    {
        $data = $request->validate([
            'username' => ['required', 'string', 'max:40'],
            'amount' => ['required', 'integer', 'min:1', 'max:'.Wallet::MAX_TRANSFER],
            'note' => ['nullable', 'string', 'max:140'],
        ]);
        $to = User::where('username', ltrim($data['username'], '@'))->first();
        if (! $to) {
            return response()->json(['message' => 'No member with that username.'], 404);
        }
        try {
            Wallet::transfer($request->user(), $to, (int) $data['amount'], $data['note'] ?? null);
        } catch (InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json(['balance' => (int) $request->user()->fresh()->coin_balance]);
    }

    /** Start an eSewa top up. The app opens pay_url in the browser. */
    public function startTopup(Request $request): JsonResponse
    {
        if (! Esewa::configured()) {
            return response()->json(['message' => 'Top up is not switched on yet.'], 503);
        }
        $data = $request->validate(['amount' => ['required', 'integer', 'min:10', 'max:100000']]);
        $id = (string) Str::uuid();
        DB::table('wallet_topups')->insert([
            'public_id' => $id, 'user_id' => $request->user()->id, 'provider' => 'esewa',
            'amount' => $data['amount'], 'status' => 'pending', 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['topup_id' => $id, 'pay_url' => url('/pay/esewa/'.$id)], 201);
    }

    public function withdrawals(Request $request): JsonResponse
    {
        $rows = DB::table('wallet_withdrawals')->where('user_id', $request->user()->id)->orderByDesc('id')->limit(30)->get();

        return response()->json(['data' => $rows->map(fn ($w) => \App\Services\Withdrawals::present($w))->values()]);
    }

    public function requestWithdrawal(Request $request): JsonResponse
    {
        if (! \App\Services\Withdrawals::enabled()) {
            return response()->json(['message' => 'Cash out is not switched on yet.'], 503);
        }
        $data = $request->validate([
            'coins' => ['required', 'integer'],
            'client_id' => ['required', 'string', 'min:8', 'max:64'],
        ]);
        try {
            [$w, $created] = \App\Services\Withdrawals::request($request->user(), (int) $data['coins'], $data['client_id']);
        } catch (InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return response()->json([
            'withdrawal' => \App\Services\Withdrawals::present($w),
            'balance' => (int) $request->user()->fresh()->coin_balance,
        ], $created ? 201 : 200);
    }

    public function cancelWithdrawal(Request $request, string $id): JsonResponse
    {
        if (! \App\Services\Withdrawals::cancel($request->user(), $id)) {
            return response()->json(['message' => 'This cash out is already being processed and cannot be canceled.'], 409);
        }

        return response()->json(['canceled' => true, 'balance' => (int) $request->user()->fresh()->coin_balance]);
    }

    public function topupStatus(Request $request, string $id): JsonResponse
    {
        $t = DB::table('wallet_topups')->where('public_id', $id)->where('user_id', $request->user()->id)->first();
        abort_unless($t, 404);

        return response()->json(['status' => $t->status, 'amount' => (int) $t->amount]);
    }

    /** Public page that posts the signed form to eSewa. The topup id is unguessable. */
    public function payPage(string $id): Response
    {
        $t = DB::table('wallet_topups')->where('public_id', $id)->where('status', 'pending')->first();
        abort_unless($t && Esewa::configured(), 404);
        $fields = Esewa::form($id, (int) $t->amount, url('/pay/esewa/'.$id));
        $inputs = '';
        foreach ($fields as $k => $v) {
            $inputs .= '<input type="hidden" name="'.e($k).'" value="'.e($v).'">';
        }
        $mode = config('services.esewa.env') === 'live' ? '' : '<p>Test mode. No real money moves.</p>';
        $html = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            .'<title>Sanjaal top up</title><body style="font-family:sans-serif;text-align:center;padding:3rem">'
            .'<h2>Opening eSewa</h2>'.$mode.'<form id="f" method="POST" action="'.e(Esewa::formUrl()).'">'.$inputs
            .'<noscript><button type="submit">Continue to eSewa</button></noscript></form>'
            .'<script>document.getElementById("f").submit()</script></body>';

        return response($html);
    }

    /** eSewa redirects here after payment. Coins are credited only after verification. */
    public function payReturn(Request $request, string $id, string $result): Response
    {
        $t = DB::table('wallet_topups')->where('public_id', $id)->first();
        abort_unless($t, 404);
        $ok = false;
        if ($result === 'success' && $request->filled('data')) {
            $payload = Esewa::verify((string) $request->query('data'), $id, (int) $t->amount);
            if ($payload) {
                $user = User::find($t->user_id);
                Wallet::credit($user, (int) $t->amount, 'topup', 'esewa:'.$id, 'eSewa top up');
                DB::table('wallet_topups')->where('id', $t->id)->update([
                    'status' => 'completed', 'provider_ref' => $payload['transaction_code'] ?? null, 'updated_at' => now(),
                ]);
                $ok = true;
            }
        }
        if (! $ok && $t->status === 'pending') {
            DB::table('wallet_topups')->where('id', $t->id)->update(['status' => 'failed', 'updated_at' => now()]);
        } elseif ($t->status === 'completed') {
            $ok = true;
        }
        $msg = $ok ? 'Payment received. Your coins are in your wallet. You can go back to Sanjaal.'
                   : 'The payment did not go through and no coins were added. You can go back to Sanjaal and try again.';

        return response('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            .'<title>Sanjaal</title><body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>'
            .($ok ? 'Done' : 'Not completed').'</h2><p>'.e($msg).'</p></body>');
    }

    private function entries(int $uid, int $limit, int $before = 0): array
    {
        $q = DB::table('wallet_entries as w')->leftJoin('users as c', 'c.id', '=', 'w.counterparty_id')
            ->where('w.user_id', $uid)->orderByDesc('w.id')->limit($limit)
            ->select('w.id', 'w.public_id', 'w.kind', 'w.amount', 'w.balance_after', 'w.note', 'w.created_at', 'c.username as counterparty');
        if ($before) {
            $q->where('w.id', '<', $before);
        }

        return $q->get()->map(fn ($r) => [
            'seq' => (int) $r->id, 'public_id' => $r->public_id, 'kind' => $r->kind, 'amount' => (int) $r->amount,
            'balance_after' => (int) $r->balance_after, 'note' => $r->note, 'counterparty' => $r->counterparty,
            'created_at' => \Illuminate\Support\Carbon::parse($r->created_at)->toIso8601String(),
        ])->all();
    }

    public function gifts(): JsonResponse
    {
        return response()->json(['data' => collect(Wallet::GIFTS)->map(fn ($g, $k) => ['key' => $k] + $g)->values()]);
    }

    /** Send a gift on a post or reel. Coins go from the sender to the creator. */
    public function sendGift(Request $request, string $postId): JsonResponse
    {
        $data = $request->validate(['gift' => ['required', 'string', 'max:16']]);
        $post = \App\Models\Post::where('public_id', $postId)->firstOrFail();
        $me = $request->user();
        try {
            $gift = Wallet::gift($me, $post->user, $data['gift'], $post->id);
        } catch (InvalidArgumentException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }
        $total = (int) DB::table('gifts')->where('post_id', $post->id)->sum('coins');

        return response()->json(['gift' => $gift, 'balance' => (int) $me->fresh()->coin_balance, 'post_gift_coins' => $total], 201);
    }

    public function registerDevice(Request $request): JsonResponse
    {
        $data = $request->validate(['token' => ['required', 'string', 'max:512'], 'platform' => ['nullable', 'in:android,ios']]);
        DB::table('device_tokens')->updateOrInsert(
            ['token' => $data['token']],
            ['user_id' => $request->user()->id, 'platform' => $data['platform'] ?? 'android', 'updated_at' => now(), 'created_at' => now()]
        );

        return response()->json(['ok' => true], 201);
    }

    public function unregisterDevice(Request $request): JsonResponse
    {
        $data = $request->validate(['token' => ['required', 'string', 'max:512']]);
        DB::table('device_tokens')->where('token', $data['token'])->where('user_id', $request->user()->id)->delete();

        return response()->json(['ok' => true]);
    }
}
