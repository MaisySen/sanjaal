<?php
// Exercise the exact controller before any DB access, in a networkless image.
require '/app/vendor/autoload.php';
$app = require '/app/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
foreach (['missing-id', '', ['not-a-string'], str_repeat('x', 300)] as $id) {
    $request = Illuminate\Http\Request::create('/synthetic-group-validation', 'POST', [
        'type' => 'group', 'title' => 'Local plan', 'usernames' => ['friend'],
        'member_refs' => [['public_id' => $id, 'username' => 'friend']],
    ]);
    try {
        $app->make(App\Http\Controllers\ChatController::class)->store($request);
        throw new RuntimeException('Malformed ID reached controller work');
    } catch (Illuminate\Validation\ValidationException $error) {
        if (!isset($error->errors()['member_refs.0.public_id'])) {
            throw new RuntimeException('Expected malformed stable identity rejection');
        }
        echo "Malformed stable identity rejected before database access\n";
    }
}
