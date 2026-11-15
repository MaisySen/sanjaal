<?php
// CI only. Usage: php tests/E2E/prepare.php OUT_DIR   (needs a migrated sqlite database in the env)
use App\Models\Post;
use App\Models\User;
use Firebase\JWT\JWT;
use Illuminate\Contracts\Console\Kernel;

require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$out = $argv[1] ?? sys_get_temp_dir();
@mkdir($out, 0700, true);
$res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
openssl_pkey_export($res, $pem);
$d = openssl_pkey_get_details($res);
$b64 = fn ($v) => rtrim(strtr(base64_encode($v), '+/', '-_'), '=');
$kid = 'e2e-'.bin2hex(random_bytes(4));
file_put_contents("$out/jwks.json", json_encode(['keys' => [['kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => $kid, 'n' => $b64($d['rsa']['n']), 'e' => $b64($d['rsa']['e'])]]]));

$me = User::create(['name' => 'Synthetic Member', 'username' => 'synthetic_member', 'email' => 'synthetic@example.invalid', 'auth0_sub' => 'auth0|e2e-synthetic', 'password' => bin2hex(random_bytes(16))]);
$asha = User::create(['name' => 'Asha Gurung', 'username' => 'asha_e2e', 'email' => 'asha@example.invalid', 'auth0_sub' => 'auth0|e2e-asha', 'password' => bin2hex(random_bytes(16))]);
Post::create(['user_id' => $asha->id, 'kind' => 'post', 'body' => 'Sunrise over Phewa lake. Test post for the emulator run.']);
Post::create(['user_id' => $me->id, 'kind' => 'post', 'body' => 'My own synthetic post.']);

$tok = JWT::encode(['iss' => 'https://tenant.example.auth0.com/', 'aud' => 'https://api.test', 'sub' => 'auth0|e2e-synthetic', 'iat' => time() - 10, 'exp' => time() + 3000], $pem, 'RS256', $kid);
file_put_contents("$out/token.txt", $tok);
echo "prepared\n";
