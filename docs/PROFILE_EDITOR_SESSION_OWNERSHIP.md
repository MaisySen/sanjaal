# Profile editor session ownership

The editor belongs to the Session object, member ID and login generation that opened it. Logout, same-member re-login, another member login or replacing the Session object retires the old editor. Its text controllers are cleared and its form/actions are replaced by the existing session-retired screen.

Gallery selection and file reading may finish after retirement. Ownership is checked before opening the picker, after selection, after reading bytes, and before allowing any save. Late profile responses cannot navigate away from the retired screen or show an old success notice. Existing Session request epoch guards remain in place.

The isolated workflow runs nine account-boundary regressions together with existing profile and upload session suites, an expected historical unbound-editor failure, restored suites, the full Flutter suite and Android debug compilation. All HTTP responses and selected media in these tests are synthetic. A request already sent as the original member is not recalled or described as cancelled at the server. No production profile or avatar is changed by these checks.

This is source/test work, not physical-device acceptance or release authority.
