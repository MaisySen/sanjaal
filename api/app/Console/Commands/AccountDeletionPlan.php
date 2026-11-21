<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Read-only, one existing request only. No erase, provider calls or apply mode. */
class AccountDeletionPlan extends Command
{
    protected $signature = 'accounts:deletion-plan {request_id : Existing deletion request public UUID}';
    protected $description = 'Inspect scoped deletion dependencies without deleting or changing any record';

    public function handle(): int
    {
        $reference = $this->argument('request_id');
        if (! is_string($reference) || ! Str::isUuid($reference)) {
            $this->error('A valid existing request UUID is required.');
            return self::FAILURE;
        }
        $request = DB::table('account_deletion_requests')->where('public_id', $reference)->first();
        if (! $request || $request->status !== 'requested') {
            $this->error('No pending request matches that reference.');
            return self::FAILURE;
        }
        $user = DB::table('users')->where('id', $request->user_id)->first(['id', 'public_id', 'coin_balance']);
        if (! $user) {
            $this->error('Request member could not be verified. No completion is inferred.');
            return self::FAILURE;
        }
        $id = $user->id;
        $counts = [];
        foreach (['posts', 'comments', 'messages', 'stories', 'device_tokens', 'upload_receipts', 'wallet_entries', 'wallet_topups', 'wallet_withdrawals', 'wallet_transfers'] as $table) {
            $counts[$table] = DB::table($table)->where('user_id', $id)->count();
        }
        $counts['conversations_created'] = DB::table('conversations')->where('created_by', $id)->count();
        $counts['conversation_memberships'] = DB::table('conversation_members')->where('user_id', $id)->count();
        $counts['other_member_ledger_references'] = DB::table('wallet_entries')->where('counterparty_id', $id)->where('user_id', '!=', $id)->count();
        $counts['incoming_transfer_receipts'] = DB::table('wallet_transfers')->where('recipient_id', $user->public_id)->count();
        $counts['gifts_sent_or_received'] = DB::table('gifts')->where(fn ($q) => $q->where('sender_id', $id)->orWhere('receiver_id', $id))->count();
        $holds = [
            'nonzero_coin_balance' => (int) $user->coin_balance !== 0,
            'unsettled_topups' => DB::table('wallet_topups')->where('user_id', $id)->whereNotIn('status', ['completed', 'failed'])->exists(),
            'unsettled_withdrawals' => DB::table('wallet_withdrawals')->where('user_id', $id)->whereNotIn('status', ['paid', 'failed', 'canceled'])->exists(),
            'shared_conversation_ownership' => $counts['conversations_created'] > 0,
        ];
        $this->line(json_encode([
            'request_reference' => $request->public_id, 'request_status' => $request->status,
            'scope' => 'One member request; counts only, not a consistent snapshot or complete media inventory',
            'counts' => $counts, 'operational_holds' => $holds,
            'media_sample' => \App\Support\AccountDeletionMediaInventory::inspect($id),
            'unresolved' => ['identity revocation and anti-recreation', 'financial retention and reconciliation', 'associated media and shared references',
                'in-flight work and replay barriers', 'backup lifecycle and completion confirmation'],
            'inventory_complete' => false, 'deletion_allowed' => false, 'account_deleted' => false,
        ], JSON_THROW_ON_ERROR));

        return self::SUCCESS;
    }
}
