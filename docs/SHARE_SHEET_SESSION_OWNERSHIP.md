# Share recipients belong to their opening login

The share-to-chat sheet retires permanently on its opening Session object/member/generation change. It clears private recipients, errors and pending-send indicator, rejects new sends, suppresses late recipient replies and old success/error notices, and never closes a replacement route after an earlier send completes. A request sent before retirement is not undone or automatically replayed.

Seven synthetic cases cover loaded/pending recipients across same/other member login, late send success/error and unchanged-account send. Existing sharing/discovery journeys remain required. Historical same-member loaded-recipient code must fail an actual retirement assertion; restored focused/full suite/debug build must then pass. No real messages or physical acceptance are implied.
