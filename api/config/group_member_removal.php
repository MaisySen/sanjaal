<?php

return [
    // Matching client/migration and membership-revocation review are required.
    'enabled' => filter_var(env('GROUP_MEMBER_REMOVAL_ENABLED', false), FILTER_VALIDATE_BOOL),
];
