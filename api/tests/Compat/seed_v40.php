<?php
// CI-only fixture for the timing-image check. Synthetic identity, throwaway database, throwaway signing key.
use App\Models\User;
use Firebase\JWT\JWT;

$res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($res, $pem);
$d = openssl_pkey_get_details($res);
$b64 = fn ($v) => rtrim(strtr(base64_encode($v), '+/', '-_'), '=');
@mkdir('/tmp/compat');
file_put_contents('/tmp/compat/jwks.json', json_encode(['keys' => [['kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => 'compat-key', 'n' => $b64($d['rsa']['n']), 'e' => $b64($d['rsa']['e'])]]]));
User::factory()->create(['username' => 'cowner', 'auth0_sub' => 'auth0|cowner']);
file_put_contents('/tmp/compat/owner.jwt', JWT::encode(['iss' => 'https://tenant.example.auth0.com/', 'aud' => 'https://api.test', 'sub' => 'auth0|cowner', 'iat' => time() - 10, 'exp' => time() + 3000], $pem, 'RS256', 'compat-key'));
$owner = User::where('username', 'cowner')->firstOrFail();
$post = \App\Models\Post::create(['user_id' => $owner->id, 'kind' => 'post', 'body' => 'Synthetic exact-image populated feed fixture']);
$post->media()->create(['type' => 'image', 'path' => trim(file_get_contents('/tmp/avatar_id')), 'mime' => 'image/png', 'size' => 68]);
$post->hashtags()->attach(\App\Models\Hashtag::firstOrCreate(['tag' => 'fixture'])->id);
