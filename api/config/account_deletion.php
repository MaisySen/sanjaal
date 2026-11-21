<?php

// Not a rollout switch. No environment activation until an approved completion
// mechanism, processing notice and retention notice are verified together.
return [
    'enabled' => false,
    'policy_version' => null,
    'completion_notice' => null,
    'retention_notice' => null,
    'completion_mechanism_verified' => false,
];
