<?php

return [
    // Enable only after the matching migration/client/operational review.
    'enabled' => filter_var(env('GROUP_OWNERSHIP_ENABLED', false), FILTER_VALIDATE_BOOL),
];
