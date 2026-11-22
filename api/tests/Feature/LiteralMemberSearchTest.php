<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Real search endpoint, including the underscore handles used by native E2E. */
class LiteralMemberSearchTest extends TestCase
{
    use RefreshDatabase;

    private function search(string $query, array $headers)
    {
        return $this->getJson('/api/v1/users/search?'.http_build_query(['q' => $query], '', '&', PHP_QUERY_RFC3986), $headers)->assertOk();
    }

    private function person(string $username, string $name): array
    {
        [$user, $headers] = $this->member($username);
        $user->forceFill(['name' => $name])->save();

        return [$user, $headers];
    }

    public function test_native_group_handles_match_without_wildcard_decoys(): void
    {
        [, $headers] = $this->person('synthetic_member', 'Synthetic Member');
        $this->person('asha_e2e', 'Asha Gurung');
        $this->person('ashaxe2e', 'Different Person');
        $this->person('bikram_e2e', 'Bikram Test');
        $this->person('bikramxe2e', 'Other Person');

        foreach (['asha_e2e', 'bikram_e2e'] as $handle) {
            $this->search($handle, $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', $handle);
        }
        $this->search('  @ASHA_E2E  ', $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'asha_e2e');
        $this->search('synthetic_member', $headers)->assertJsonCount(0, 'users');
    }

    public function test_display_name_percent_is_literal_not_any_suffix(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        $this->person('percent', '100% Nepali');
        $this->person('decoy', '1000 Nepali');

        $this->search('100%', $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'percent');
    }

    public function test_display_name_underscore_is_literal_not_any_character(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        $this->person('underscore', 'Team_One');
        $this->person('decoy', 'TeamXOne');

        $this->search('Team_', $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'underscore');
    }

    public function test_escape_marker_cannot_turn_percent_into_a_wildcard(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        $this->person('literal', 'Wow!% Room');
        $this->person('decoy', 'Wow! Extra Room');

        $this->search('Wow!%', $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'literal');
        $this->search('!', $headers)->assertJsonCount(2, 'users');
    }

    public function test_backslashes_and_quotes_remain_literal_bound_data(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        $this->person('slash', 'Team\\_One');
        $this->person('decoy', 'Team_One');
        $this->person('slashdecoy', 'Team\\XOne');
        $this->person('quoted', "O'Neil");

        $this->search('Team\\_', $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'slash');
        $this->search("O'Neil", $headers)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'quoted');
        $this->search("' OR 1=1 --", $headers)->assertJsonCount(0, 'users');
    }

    public function test_hashtags_use_the_same_literal_rules(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        foreach (['native_group', 'nativexgroup', '100%', '1000', 'wow!%', 'wow!extra', 'path\\_one', 'path_one'] as $tag) {
            DB::table('hashtags')->insert(['tag' => $tag]);
        }
        foreach (['native_', '100%', 'wow!%', 'path\\_'] as $query) {
            $tag = match ($query) {
                'native_' => 'native_group',
                'path\\_' => 'path\\_one',
                default => $query,
            };
            $this->search($query, $headers)->assertJsonCount(1, 'hashtags')->assertJsonPath('hashtags.0', $tag);
        }
    }

    public function test_literal_matches_keep_self_and_bidirectional_block_exclusions(): void
    {
        [, $viewer] = $this->person('viewer_e2e', 'Viewer');
        [, $asha] = $this->person('asha_e2e', 'Asha');
        [, $bikram] = $this->person('bikram_e2e', 'Bikram');
        $this->person('visible_e2e', 'Visible');
        $this->postJson('/api/v1/users/asha_e2e/block', [], $viewer)->assertOk();
        $this->postJson('/api/v1/users/viewer_e2e/block', [], $bikram)->assertOk();

        $this->search('_e2e', $viewer)->assertJsonCount(1, 'users')->assertJsonPath('users.0.username', 'visible_e2e');
        $this->search('viewer_e2e', $asha)->assertJsonCount(0, 'users');
    }

    public function test_results_remain_sorted_and_bounded_and_empty_query_is_empty(): void
    {
        [, $headers] = $this->person('viewer', 'Viewer');
        for ($i = 24; $i >= 0; $i--) {
            $this->person(sprintf('literal_%02d', $i), 'Local Person');
        }
        $response = $this->search('literal_', $headers)->assertJsonCount(20, 'users');
        $this->assertSame(array_map(fn ($i) => sprintf('literal_%02d', $i), range(0, 19)), array_column($response->json('users'), 'username'));
        $this->search('  @  ', $headers)->assertJsonCount(0, 'users')->assertJsonCount(0, 'hashtags');
    }
}
