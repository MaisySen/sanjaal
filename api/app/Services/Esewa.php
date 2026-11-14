<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

/**
 * eSewa ePay v2. Runs against the eSewa test (RC) environment unless ESEWA_ENV=live.
 * The merchant code and secret come from the environment, never from source.
 */
class Esewa
{
    public static function configured(): bool
    {
        return filled(config('services.esewa.product_code')) && filled(config('services.esewa.secret'));
    }

    public static function formUrl(): string
    {
        return config('services.esewa.env') === 'live'
            ? 'https://epay.esewa.com.np/api/epay/main/v2/form'
            : 'https://rc-epay.esewa.com.np/api/epay/main/v2/form';
    }

    public static function statusUrl(): string
    {
        return config('services.esewa.env') === 'live'
            ? 'https://epay.esewa.com.np/api/epay/transaction/status/'
            : 'https://rc.esewa.com.np/api/epay/transaction/status/';
    }

    public static function sign(array $fields, string $names): string
    {
        $parts = [];
        foreach (explode(',', $names) as $n) {
            $parts[] = $n.'='.($fields[$n] ?? '');
        }

        return base64_encode(hash_hmac('sha256', implode(',', $parts), (string) config('services.esewa.secret'), true));
    }

    /** Form fields to post to eSewa for a top up. */
    public static function form(string $uuid, int $amount, string $returnBase): array
    {
        $f = [
            'amount' => (string) $amount,
            'tax_amount' => '0',
            'total_amount' => (string) $amount,
            'transaction_uuid' => $uuid,
            'product_code' => config('services.esewa.product_code'),
            'product_service_charge' => '0',
            'product_delivery_charge' => '0',
            'success_url' => $returnBase.'/success',
            'failure_url' => $returnBase.'/failure',
            'signed_field_names' => 'total_amount,transaction_uuid,product_code',
        ];
        $f['signature'] = self::sign($f, $f['signed_field_names']);

        return $f;
    }

    /**
     * Check the redirect payload from eSewa and confirm it with the status API.
     * Returns the decoded payload when the payment is verified and complete, else null.
     */
    public static function verify(string $data, string $expectedUuid, int $expectedAmount): ?array
    {
        $json = json_decode((string) base64_decode($data, true), true);
        if (! is_array($json) || empty($json['signature']) || empty($json['signed_field_names'])) {
            return null;
        }
        if (! hash_equals(self::sign($json, $json['signed_field_names']), (string) $json['signature'])) {
            return null;
        }
        if (($json['transaction_uuid'] ?? null) !== $expectedUuid
            || ($json['status'] ?? null) !== 'COMPLETE'
            || (int) round((float) str_replace(',', '', (string) ($json['total_amount'] ?? 0))) !== $expectedAmount) {
            return null;
        }
        $r = Http::timeout(15)->get(self::statusUrl(), [
            'product_code' => config('services.esewa.product_code'),
            'total_amount' => $expectedAmount,
            'transaction_uuid' => $expectedUuid,
        ]);
        if (! $r->ok() || $r->json('status') !== 'COMPLETE') {
            return null;
        }

        return $json;
    }
}
