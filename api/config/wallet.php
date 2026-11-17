<?php

return [
    // Deliberate owner hold. Enable only after current server/payment-path and
    // device acceptance; replay support alone is not permission to move coins.
    'member_transfers_enabled' => filter_var(env('MEMBER_TRANSFERS_ENABLED', false), FILTER_VALIDATE_BOOLEAN),
];
