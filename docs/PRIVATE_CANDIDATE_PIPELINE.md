# Private candidate promotion

This is the candidate evidence stage, not automatic release or deployment.
The public tag-release job stays disabled. No signing or provider credential
is added to GitHub by this change. CI toolchain pins refer to the actual
successful run44011833694, not an assumed latest SDK.

## Bind the same bytes

Run both existing finalizers only after the selected run's five jobs pass:
`api`, `app`, `ios`, `emulator`, `bundle`. They now record `input_sha256` as
well as the final signed file's hash. Keep each verification JSON beside the
actual signed output. Do not edit a report to make it pass.

Fetch current run, jobs and artifacts JSON through authenticated GitHub
access. Download the actual artifacts, following the provider redirect
privately. Never place signed download URLs, credentials or raw job logs in
the repository. Archive hashes must match GitHub's artifact digest.

The local evidence JSON identifies these files (all paths are local):

```json
{
  "apk": {
    "artifact_id": 123,
    "archive": "/private/downloaded-apk.zip",
    "member": "the-exact-member-in-the-archive.apk",
    "signed": "/private/signed.apk",
    "verification": "/private/signed.verification.json"
  },
  "aab": {
    "artifact_id": 456,
    "archive": "/private/downloaded-bundle.zip",
    "member": "the-exact-member-in-the-archive.aab",
    "signed": "/private/signed.aab",
    "verification": "/private/signed-bundle.verification.json"
  }
}
```

Create a new output using `.github/ci/candidate_manifest.py` with `--run`,
`--jobs`, `--artifacts`, `--repo`, `--api-source`, `--api-image`, `--evidence`
and `--output`. The API image must be an immutable `sha256:` digest, not a
mutable tag. `--api-source` is a full commit. If it differs from the client
source, either both commits' entire `app` tree hashes or their entire `api` tree
hashes must match. The manifest records which relation passed and both API
tree hashes. This permits a reviewed API-only fix with the identical client,
or a new client against exactly the API source it passed CI with, without
relabeling the older image's source as the new commit. Neither relation proves
that an arbitrary claimed image digest really contains that source: independently
verify the image/source provenance and its current live capabilities. If both
trees differ, a separate compatibility review and new verified image are needed.

The validator requires each job's run and source, exactly one successful
instance of all five gates, expected artifact name/origin, the provider's
archive digest, a safe unique archive member, original input hash, matching
final signed file hash/size, stable certificate/package/ABI claims, matching
APK/AAB version, and the finalizers' binary check set. An existing output
is not overwritten. This is deterministic local metadata validation;
independent binary signature verification and authenticated source recovery
remain required. A forged report is not a trusted release.

Earlier reports, including the distributed2008 beta, predate the explicit
`input_sha256` field. They fail this new validator. Do not retrofit a claim
or replace delivered artifacts: keep their original evidence, and use the
new finalizers for future candidates. This is a stricter future pipeline,
not a retroactive statement that a new manifest verified build2008.

## Promotion is separate

The generated manifest says `PRIVATE_CANDIDATE_NOT_RELEASE_AUTHORIZATION`.
It records required API capabilities, wallet transfer replay and funding /
payout-off requirements. It cannot prove a current live server or a Play
release. Before internal promotion, verify these from their owning sources:

- Independent package, actual signature, version and payload checks.
- Play's accepted certificate, highest allocated code, active release and
  approved tester audience. Matching signature and increasing code alone
  do not prove an installation succeeded or guarantee local-data retention.
- A fresh encrypted recovery point, successful isolated restore and reviewed
  additive migration compatibility. Preserve upload/transfer receipt
  tombstones and durable media privacy classification.
- Actual deployed immutable image, current capabilities, and authenticated
  private upload/read/replay/delete with cleanup. No money transaction is
  needed for this smoke check.
- A working recipient-accessible download or active internal-test route.
  Provider acceptance is not user installation.

Do not place private screenshots, test accounts, database copies or vault
values in a manifest or build artifact. The automated promotion/signing
workflow, scoped credential setup, Play in-app update prompt, production
OTA baseline, and physical two-version update test remain unfinished.

## Exact-source workflow bundle, November 21

Manifest schema2 also requires `workflow_checks` in the local evidence JSON.
Its value is a path to a private JSON file with a `runs` array. Each entry has
`run` (the complete authenticated GitHub run response) and `jobs` (the complete
latest-attempt jobs response). Fetch up to100jobs and ensure pagination did
not omit any required job. Do not copy a summary or edit a failed result.

The validator requires exactly one record for each of the ten workflows in
`WORKFLOW_GATES` in `candidate_manifest.py`. All must be completed successfully,
on the same repository, commit, branch and event as the selected main run.
Required jobs must belong to that run and its current attempt. The main workflow
record must be the artifact-producing run, including exact-money-hold and the
historical image-parity job. The release job must remain skipped. The duplicate
Android restart in the adapter workflow is deliberately not required: the
separate Android and iOS restart jobs in memory-video-preview are required.

An older head's green native jobs, an earlier attempt, a skipped required job,
a missing workflow or a renamed job fails closed. Update the requirements only
after reviewing the actual workflow change, never to make a failed candidate
look accepted. Rerun the manifest after every selected-source change.

This metadata bundle does not inspect pixels, attest that downloaded JSON is
authentic, verify a signature, prove production compatibility or authorize
signing, delivery or release. Recover records through authenticated GitHub
access. Human visual review and exact-candidate physical acceptance remain
separate. No new credential, signing, upload or production action is performed
by this source change.
