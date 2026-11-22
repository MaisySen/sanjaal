# Other-profile member-list entry, default-off candidate

The optional follower-list capability remains default-off. This correction changes no backend query, policy, release flag or audience rule and is not evidence of live privacy enforcement.

Six old-source negatives showed both Followers and Following retained callbacks could open a route after capability revocation, after a successful profile refresh marked the member blocked, or twice from duplicate invocation. No member-list destination was rendered during those negative checks, and there were zero synthetic relationship requests.

Other-profile entry now checks the current capability, mounted active session, exact current profile object, unblocked state, matching username and a nonempty owner identity. A shared route lock prevents overlapping Followers/Following entry and releases when the route returns. Busy/loading states cannot open a member list. Existing owner/session handling remains in force inside the list itself.

Six new cases and existing follower-list, own-profile ownership, member-session and profile-journey groups passed 107 tests. Focused analysis after adding braces has one existing profile informational lint, no errors/warnings. Current English/light and Nepali/dark member-profile pixels were inspected at narrow large text; labels and actions are readable. No claim of final reference-design acceptance or physical-device behavior.

No source push, native build, provider action, live relationship read/write, install or distribution occurred. Backend policy/query/device integration and default-off privacy hold remain open.
