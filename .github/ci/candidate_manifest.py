#!/usr/bin/env python3
"""Bind verified private candidate bytes to actual downloaded CI artifacts.

Does not sign, upload, deploy, publish, or grant release authority. Inputs must
come from authenticated owning surfaces, not an emailed manifest. Finalizer
reports complement, not replace, independent binary signature verification.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

PACKAGE = 'au.fintex.sanjaal'
CERTIFICATE = 'e6d401f11358c43e232921a088401b9c2aa25eabe4ecd972e17954220d9783a7'
API = 'https://sanjaal-api.onrender.com/api/v1'
GATES = ('api', 'app', 'ios', 'emulator', 'bundle')
CAPABILITIES = ('interaction_controls', 'protected_stories', 'polls', 'upload_intents')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def app_tree(repo, commit):
    require(re.fullmatch('[0-9a-f]{40}', commit) is not None, 'Full source SHA required')
    return subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--verify', commit + ':app'], text=True).strip()


def api_tree(repo, commit):
    require(re.fullmatch('[0-9a-f]{40}', commit) is not None, 'Full API source SHA required')
    return subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--verify', commit + ':api'], text=True).strip()


def check_run(run, jobs):
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success', 'CI not successful')
    require(run.get('repository', {}).get('full_name') == 'MaisySen/sanjaal', 'Wrong repository')
    require(isinstance(run.get('id'), int) and run['id'] > 0, 'Missing run identity')
    require(re.fullmatch('[0-9a-f]{40}', run.get('head_sha', '')) is not None, 'Full source SHA required')
    require(run.get('html_url') == f"https://github.com/MaisySen/sanjaal/actions/runs/{run['id']}", 'Wrong run URL')
    require(run.get('event') in ('push', 'workflow_dispatch'), 'Untrusted release event')
    for name in GATES:
        matches = [j for j in jobs.get('jobs', []) if j.get('name') == name]
        require(len(matches) == 1, 'Missing or ambiguous CI gate: ' + name)
        job = matches[0]
        require(job.get('run_id') == run['id'] and job.get('head_sha') == run['head_sha'], 'Job source/run mismatch')
        require(job.get('status') == 'completed' and job.get('conclusion') == 'success', 'Failed CI gate: ' + name)


def check_artifact(kind, run, artifact, archive, member, signed, verification):
    expected_name = {'apk': 'sanjaal-apk', 'aab': 'sanjaal-unsigned-aab-engineering-only'}[kind]
    require(artifact.get('name') == expected_name and not artifact.get('expired'), 'Wrong or expired artifact')
    require(isinstance(artifact.get('id'), int) and artifact['id'] > 0, 'Missing artifact identity')
    origin = artifact.get('workflow_run', {})
    require(origin.get('id') == run['id'] and origin.get('head_sha') == run['head_sha'], 'Artifact source/run mismatch')
    archive_sha = digest(archive)
    require(artifact.get('digest') == 'sha256:' + archive_sha, 'Archive provider digest mismatch')
    require(isinstance(member, str) and member.endswith('.' + kind) and not member.startswith('/') and '..' not in Path(member).parts, 'Invalid member path')
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        require(len(names) == len(set(names)), 'Duplicate archive members')
        require(all(not n.startswith('/') and '..' not in Path(n).parts for n in names), 'Unsafe archive member')
        require(member in names, 'Input artifact member missing')
        info = z.getinfo(member)
        require(0 < info.file_size <= 150 * 1024 * 1024, 'Artifact member size outside bound')
        input_sha = hashlib.sha256(z.read(member)).hexdigest()
    v = verification
    require(v.get('input_sha256') == input_sha, 'Finalizer input differs from CI archive member')
    require(v.get('package') == PACKAGE and v.get('certificate_sha256') == CERTIFICATE, 'Package/certificate mismatch')
    require(v.get('source_commit') == run['head_sha'] and v.get('ci_run_id') == run['id'] and v.get('ci_url') == run['html_url'], 'Finalizer origin mismatch')
    require(v.get('abi') == 'arm64-v8a', 'Wrong ABI')
    require(isinstance(v.get('version_code'), int) and v['version_code'] >= 2008, 'Unsupported version code')
    require(re.fullmatch(r'\d+\.\d+\.\d+', v.get('version_name', '')) is not None, 'Invalid version name')
    require(v.get('bytes') == Path(signed).stat().st_size and v.get('sha256') == digest(signed), 'Signed output differs from verified bytes')
    if kind == 'apk':
        require(v.get('production_api') == API, 'Wrong API')
        required = {'v2_v3_signature', 'stable_certificate', '16kb_zip_and_native_segments', 'no_fixture_or_tunnel_markers', 'backup_disabled', 'not_debuggable'}
    else:
        required = {'bundletool_validate_before_and_after_signing', 'package_version_backup_not_debuggable', 'no_test_markers', 'production_api', 'arm64_elf_16kb', 'jar_signature_all_entries', 'pinned_upload_certificate'}
    require(required.issubset(set(v.get('checks', []))), 'Missing binary verification checks')
    return {'artifact_id': artifact['id'], 'artifact_name': expected_name, 'archive_sha256': archive_sha,
            'input_member': member, 'input_member_sha256': input_sha,
            'signed_filename': Path(signed).name, 'signed_sha256': v['sha256'], 'signed_bytes': v['bytes']}


def build(run, jobs, artifacts, repo, api_source, api_image, evidence):
    check_run(run, jobs)
    require(re.fullmatch('sha256:[0-9a-f]{64}', api_image) is not None, 'Immutable API image digest required')
    client_tree = app_tree(repo, run['head_sha'])
    same_app = client_tree == app_tree(repo, api_source)
    client_api_tree = api_tree(repo, run['head_sha'])
    image_api_tree = api_tree(repo, api_source)
    require(same_app or client_api_tree == image_api_tree, 'Neither app tree nor API tree matches image source')
    source_relation = 'identical_app_tree' if same_app else 'identical_api_tree'

    outputs = {}
    versions = set()
    for kind in ('apk', 'aab'):
        entry = evidence[kind]
        candidates = [a for a in artifacts.get('artifacts', []) if a.get('id') == entry['artifact_id']]
        require(len(candidates) == 1, 'Unknown or ambiguous artifact')
        v = load(entry['verification'])
        outputs[kind] = check_artifact(kind, run, candidates[0], entry['archive'], entry['member'], entry['signed'], v)
        versions.add((v['version_name'], v['version_code']))
    require(len(versions) == 1, 'APK/AAB versions differ')
    version_name, version_code = next(iter(versions))
    return {'schema': 1, 'purpose': 'PRIVATE_CANDIDATE_NOT_RELEASE_AUTHORIZATION',
            'repository': 'https://github.com/MaisySen/sanjaal', 'source_commit': run['head_sha'],
            'app_tree': client_tree, 'ci_run_id': run['id'], 'ci_url': run['html_url'], 'ci_gates': list(GATES),
            'package': PACKAGE, 'version_name': version_name, 'version_code': version_code,
            'certificate_sha256': CERTIFICATE, 'abi': 'arm64-v8a', 'artifacts': outputs,
            'api': {'source_commit': api_source, 'image_digest': api_image, 'base_url': API,
                    'source_relation': source_relation, 'client_api_tree': client_api_tree, 'image_api_tree': image_api_tree,
                    'required_capabilities': list(CAPABILITIES), 'wallet_transfer_replay_required': True,
                    'funding_and_payouts_must_be_disabled': True},
            'remaining_gates': ['independent final binary signature verification', 'current Play code and certificate acceptance',
                                'backup/restore and migration compatibility', 'live capability and private lifecycle verification',
                                'authorized internal audience and actual delivery', 'physical-device update/install verification']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('run', 'jobs', 'artifacts', 'repo', 'api-source', 'api-image', 'evidence', 'output'):
        p.add_argument('--' + name, required=True)
    a = p.parse_args()
    result = build(load(a.run), load(a.jobs), load(a.artifacts), a.repo, a.api_source, a.api_image, load(a.evidence))
    # Exclusive create avoids silently replacing a previously reviewed manifest.
    with Path(a.output).open('x') as f:
        f.write(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('Candidate manifest created. No signing, upload, release or deployment performed.')


if __name__ == '__main__':
    main()
