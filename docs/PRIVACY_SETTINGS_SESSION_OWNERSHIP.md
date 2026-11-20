# Privacy settings session ownership

Comments and sharing now binds to the Session object, member ID and login generation that opened it. A mismatch permanently retires that routed view. Returning to the original member cannot revive its old revision or pending choices. Retirement clears loaded settings and choices, invalidates reads, hides controls and disables save/reload. The existing account warning stays visible.

Synthetic tests cover same-member and other-member login during loaded choices, a pending read and a pending save, returning to the original member, direct member replacement, and a new Session object with matching member/epoch. Already-sent original-account requests are not recalled. Their late results cannot claim success in the retired view.

The isolated workflow runs the new session suite, existing settings suite, a historical same-member failure control, restored suites, the full Flutter suite and Android debug compilation. Four existing warning captures are retained for actual pixel inspection. No production privacy preferences are changed by these checks. Physical acceptance and release remain separate.
