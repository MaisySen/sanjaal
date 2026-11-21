#!/usr/bin/env python3
"""Sanjaal artifact gate. Validates evidence, does not grant authority or upload.

Provider snapshots must come from authenticated owning surfaces. An arbitrary JSON
file or an unverified source cannot establish these facts or user authority.
"""
import datetime,hashlib,json,re,subprocess,zipfile,plistlib
from pathlib import Path
PACKAGE='au.fintex.sanjaal'
TEAM='B85KQRQZW7'
ENDPOINT=b'https://sanjaal-api.onrender.com/api/v1'
FORBIDDEN=(b'E2E_TOKEN',b'trycloudflare',b'local-e2e',b'10.0.2.2')

def require(value,message):
 if not value:raise ValueError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def version(value):
 require(bool(re.fullmatch(r'\d+(?:\.\d+){1,2}',value)),'Invalid version')
 return tuple(int(x) for x in value.split('.'))

def check_toolchain(evidence,as_of):
 """Checks current accepted minimum separately from preferred future-ready SDK."""
 date=datetime.date.fromisoformat(as_of)
 minimum=(27,0) if date>=datetime.date(2027,4,1) else (26,0)
 # Apple says April2027 without a day. Conservatively use April1, review on change.
 require(version(evidence['xcode'])>=minimum,'Xcode below applicable SDK policy')
 require(version(evidence['ios_sdk'])>=minimum,'iOS SDK below applicable upload policy')
 require(version(evidence['deployment_target'])>=(15,0),'Project/Flutter deployment target must remain15+')
 require(evidence['flutter_revision']=='ab2912035e160d9cad6306df307576da6128ebdb','Unreviewed Flutter revision')
 require(evidence['engine_revision']=='371f77202a73e8dff57a8b3bff75bca55c090aee','Unreviewed engine revision')
 require(evidence['candidate_plugins_compile_success'] is True,'Exact plugins/toolchain not compile-proven')
 return {'accepted_minimum':minimum[0],'sdk_major':version(evidence['ios_sdk'])[0],'future_27_ready':version(evidence['ios_sdk'])>=(27,0)}

def check_audience_snapshot(snapshot):
 require(snapshot['app_id']=='6837257828','Wrong app audience')
 require(snapshot['fetched_at_utc'].endswith('Z'),'Snapshot timestamp required')
 # This is necessary, not sufficient. Caller independently checks freshness at action time.
 for group in snapshot['groups']:
  require(group.get('isInternalGroup') is True,'External group must be reviewed separately')
  require(group.get('hasAccessToAllBuilds') is False,'Automatic/all-build audience blocks upload')
  require(group.get('publicLinkEnabled',False) is False,'Public tester link blocks private workflow')
 require(snapshot['unverified_tester_identifiers']==[],'Tester identity/audience unresolved')
 return True

def check_archive(path,source,build,app_version):
 require(re.fullmatch('[0-9a-f]{40}',source) is not None,'Full source SHA required')
 require(isinstance(build,int) and build>2013,'Build number must exceed known previous uploads')
 with zipfile.ZipFile(path) as z:
  require(z.testzip() is None,'IPA CRC failure');names=z.namelist()
  require(len(names)==len(set(names)),'Duplicate IPA members')
  require(all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names),'Unsafe IPA path')
  root='Payload/Runner.app/';pl=plistlib.loads(z.read(root+'Info.plist'))
  require(pl['CFBundleIdentifier']==PACKAGE and pl['CFBundleVersion']==str(build) and pl['CFBundleShortVersionString']==app_version,'Wrong app/version')
  require(version(pl['MinimumOSVersion'])>=(15,0),'Wrong deployment minimum')
  require(root+'embedded.mobileprovision' in names,'Missing distribution profile')
  require(root+'_CodeSignature/CodeResources' in names,'Missing signature resources')
  require('ITSAppUsesNonExemptEncryption' not in pl and 'ITSEncryptionExportComplianceCode' not in pl,'Unresolved export answer was silently encoded')
  require(root+'PrivacyInfo.xcprivacy' in names,'App privacy manifest not packaged')
  app_binary=z.read(root+'Frameworks/App.framework/App')
  require(ENDPOINT in app_binary,'Production API missing')
  for name in names:
   if name.endswith('/'):continue
   require(not any(term in z.read(name) for term in FORBIDDEN),'Test marker in IPA payload')
 return {'source':source,'build':build,'version':app_version,'ipa_sha256':sha(path),'signed_verified':False,'uploaded':False}

def require_signature_report(report,ipa):
 require(report['ipa_sha256']==sha(ipa),'Signature report APK hash mismatch')
 require(report['codesign_deep_strict'] is True and report['profile_certificate_match'] is True,'Signature/profile verification incomplete')
 require(report['team']==TEAM and report['bundle']==PACKAGE,'Wrong team/bundle')
 require(report['get_task_allow'] is False and report['profile_distribution']=='app-store','Wrong distribution profile')
 require(report['all_nested_frameworks_verified'] is True,'Nested framework signatures unverified')

def upload_gate(*,audience,signature_report,ipa,authority_evidence,legal_evidence):
 check_audience_snapshot(audience);require_signature_report(signature_report,ipa)
 require(authority_evidence is not None,'Original owner upload authority not recovered')
 require(legal_evidence is not None,'Owner export/legal decisions unresolved')
 # Genuine original authority and live snapshot freshness must be checked by executor.
 # No UI/API is called, no false promise of end-to-end readiness.
 return {'technical_preflight_only':True,'legal_review_still_external':True,'distribute':False}
