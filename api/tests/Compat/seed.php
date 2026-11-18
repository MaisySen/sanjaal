<?php
// CI-only fixture for the rollback-image compatibility job. Synthetic identities, throwaway database, throwaway key.
use App\Models\Conversation;
use App\Models\User;
use Firebase\JWT\JWT;

$res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($res, $pem);
$d = openssl_pkey_get_details($res);
$b64 = fn ($v) => rtrim(strtr(base64_encode($v), '+/', '-_'), '=');
$jwks = ['keys' => [['kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => 'compat-key', 'n' => $b64($d['rsa']['n']), 'e' => $b64($d['rsa']['e'])]]];
@mkdir('/tmp/compat');
file_put_contents('/tmp/compat/jwks.json', json_encode($jwks));
$tok = fn ($sub) => JWT::encode(['iss' => 'https://tenant.example.auth0.com/', 'aud' => 'https://api.test', 'sub' => $sub, 'iat' => time() - 10, 'exp' => time() + 1800], $pem, 'RS256', 'compat-key');
$u = [];
foreach (['cowner', 'cmember', 'ctarget1', 'ctarget2'] as $n) {
    $u[$n] = User::factory()->create(['username' => $n, 'auth0_sub' => "auth0|$n"]);
}
file_put_contents('/tmp/compat/owner.jwt', $tok('auth0|cowner'));
file_put_contents('/tmp/compat/member.jwt', $tok('auth0|cmember'));
$c = Conversation::create(['type' => 'group', 'title' => 'Compat', 'created_by' => $u['cowner']->id, 'add_policy' => 'owner']);
$c->members()->attach($u['cowner']->id, ['role' => 'owner', 'history_from_id' => 0, 'last_read_message_id' => 0]);
$c->members()->attach($u['cmember']->id, ['role' => 'member', 'history_from_id' => 0, 'last_read_message_id' => 0]);
file_put_contents('/tmp/compat/conversation_id', $c->public_id);
