#!/usr/bin/env python3
"""Offline technical preflight for an exact iOS release candidate.

Inputs marked provider/live must be freshly retrieved by the executor from their
owning authenticated services, not accepted from arbitrary files or messages.
This module cannot grant permission, answer legal questions, upload or distribute.
"""
from pathlib import Path
import datetime,hashlib,json,re,subprocess,zipfile,plistlib,tempfile
PACKAGE='au.fintex.sanjaal';TEAM='B85KQRQZW7';APP='6837257828'
ENDPOINT=b'https://sanjaal-api.onrender.com/api/v1'
FORBIDDEN=(b'E2E_TOKEN',b'trycloudflare',b'local-e2e',b'10.0.2.2')
def require(v,m):
 if not v:raise ValueError(m)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def version(v):
 require(isinstance(v,str) and bool(re.fullmatch(r'\d+(?:\.\d+){1,2}',v)),'Invalid version')
 return tuple((list(map(int,v.split('.')))+[0,0,0])[:3])
def fresh(s,now):
 require(s['app_id']==APP,'Wrong Apple app')
 t=datetime.datetime.fromisoformat(s['fetched_at_utc'].replace('Z','+00:00'))
 require(t.utcoffset()==datetime.timedelta(0),'UTC timestamp required')
 require(0<=(now-t).total_seconds()<=300,'Snapshot stale or from future')
def check_toolchain(e,as_of):
 date=datetime.date.fromisoformat(as_of)
 minimum=(27,0,0) if date>=datetime.date(2027,4,1) else (26,0,0)
 # April1 is a conservative INTERNAL policy. Apple announced April2027 only.
 require(version(e['xcode'])>=minimum,'Xcode below applicable internal SDK policy')
 require(version(e['ios_sdk'])>=minimum,'SDK below applicable internal upload policy')
 require(version(e['deployment_target'])>=(15,0,0),'Deployment target below15')
 require(e['flutter_revision']=='ab2912035e160d9cad6306df307576da6128ebdb','Unreviewed Flutter revision')
 require(e['engine_revision']=='371f77202a73e8dff57a8b3bff75bca55c090aee','Unreviewed engine revision')
 require(e['candidate_plugins_compile_success'] is True,'Exact plugin compile unproven')
 return {'accepted_minimum':minimum[0],'future_27_ready':version(e['ios_sdk'])>=(27,0,0)}
def check_audience_snapshot(s,now):
 fresh(s,now)
 require(s['complete_groups_and_testers'] is True,'Incomplete live audience enumeration')
 for g in s['groups']:
  require(g.get('isInternalGroup') is True,'External audience needs separate review')
  require(g.get('hasAccessToAllBuilds') is False,'Automatic/all-build audience blocks upload')
  require(g.get('publicLinkEnabled',False) is False,'Public link blocks private workflow')
 require(s['unverified_tester_identifiers']==[],'Tester identity unresolved')
 return True
def check_build_number(s,build,now):
 fresh(s,now);require(s['all_versions_enumerated'] is True,'Build enumeration incomplete')
 require(isinstance(build,int) and build>0,'Invalid build')
 require(build not in s['build_numbers'] and build>max(s['build_numbers'],default=0),'Build number reused or not monotonic')
def check_provenance(p,archive,ipa,policy,log,repo):
 """Policy is reviewed local configuration. Provider records come from GitHub."""
 run,job,artifact,m=p['run'],p['job'],p['artifact'],p['manifest']
 require(run['repository']['full_name']=='MaisySen/sanjaal','Wrong repository')
 require(run['head_sha']==policy['orchestration_sha'],'Wrong orchestration')
 require(bool(re.fullmatch('[0-9a-f]{40}',policy['source_sha'])),'Full source SHA required')
 workflow_path=policy['workflow_path']
 require(workflow_path.startswith('.github/workflows/') and '..' not in Path(workflow_path).parts,'Unsafe workflow path')
 blob=subprocess.check_output(['git','-C',str(repo),'rev-parse',run['head_sha']+':'+workflow_path],text=True).strip()
 content=subprocess.check_output(['git','-C',str(repo),'show',blob])
 require(blob==policy['workflow_blob'] and hashlib.sha256(content).hexdigest()==policy['workflow_sha256'],'Actual workflow differs from reviewed policy')
 require(run['status']=='completed' and job['status']=='completed' and job['conclusion']=='success','Archive job not successful')
 require(job['run_id']==run['id'] and job['head_sha']==run['head_sha'] and job['run_attempt']==run['run_attempt'],'Wrong job/run/attempt')
 require(artifact['workflow_run']['id']==run['id'] and artifact['workflow_run']['head_sha']==run['head_sha'] and not artifact['expired'],'Wrong or expired provider artifact')
 require(artifact['digest']=='sha256:'+sha(archive),'Provider envelope digest mismatch')
 with zipfile.ZipFile(archive) as envelope:
  require(envelope.namelist().count('compile-manifest.json')==1,'Provider-bound manifest absent/ambiguous')
  require(json.loads(envelope.read('compile-manifest.json'))==m,'Manifest not from provider envelope')
 require(m['source_sha']==policy['source_sha'] and m['orchestration_sha']==run['head_sha'],'Source/orchestration mismatch')
 require(m['workflow_blob']==policy['workflow_blob'] and m['workflow_sha256']==policy['workflow_sha256'],'Workflow not reviewed')
 require(m['run_id']==run['id'] and m['job_id']==job['id'] and m['attempt']==run['run_attempt'],'Manifest execution mismatch')
 require(m['ipa_sha256']==sha(ipa),'IPA digest mismatch')
 require(re.search(r'git log -1 --format=%H\r?\n[^\n]*'+re.escape(policy['source_sha']),log) is not None,'Actual checkout unproven')
 return m

def check_archive(path,build,app_version):
 with zipfile.ZipFile(path) as z:
  require(z.testzip() is None,'IPA CRC failure');names=z.namelist()
  require(len(names)<=10000 and sum(x.file_size for x in z.infolist())<=500*1024*1024,'IPA exceeds audit limits')
  require(all((x.external_attr>>16)&0o170000!=0o120000 for x in z.infolist()),'Symlinks require separate archive review')
  require(len(names)==len(set(names)),'Duplicate IPA members')
  require(all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in names),'Unsafe IPA path')
  root='Payload/Runner.app/';pl=plistlib.loads(z.read(root+'Info.plist'))
  require(pl['CFBundleIdentifier']==PACKAGE and pl['CFBundleVersion']==str(build) and pl['CFBundleShortVersionString']==app_version,'Wrong app/version')
  require(version(pl['MinimumOSVersion'])>=(15,0,0),'Wrong deployment minimum')
  require(root+'embedded.mobileprovision' in names and root+'_CodeSignature/CodeResources' in names,'Missing profile/signature resources')
  require('ITSAppUsesNonExemptEncryption' not in pl and 'ITSEncryptionExportComplianceCode' not in pl,'Unresolved legal answer was silently encoded')
  require(root+'PrivacyInfo.xcprivacy' in names,'App privacy manifest missing')
  manifest=plistlib.loads(z.read(root+'PrivacyInfo.xcprivacy'))
  require(isinstance(manifest.get('NSPrivacyAccessedAPITypes'),list),'Malformed privacy manifest')
  require(ENDPOINT in z.read(root+'Frameworks/App.framework/App'),'Production endpoint missing')
  for name in names:
   if not name.endswith('/'):require(not any(v in z.read(name) for v in FORBIDDEN),'Test marker in IPA')
 return {'ipa_sha256':sha(path),'build':build,'version':app_version,'privacy_completeness_reviewed':False}

def verify_signatures(app,expected_cert_sha256):
 """Real macOS read-only codesign/profile checks, no signing credential needed."""
 app=Path(app)
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
 for framework in app.rglob('*.framework'):
  subprocess.run(['codesign','--verify','--strict',str(framework)],check=True,capture_output=True)
 profile=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app/'embedded.mobileprovision')]))
 require(profile['TeamIdentifier']==[TEAM] and not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'),'Wrong team or not app-store profile')
 require(profile['ExpirationDate']>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Expired provisioning profile')
 require(profile['Entitlements']['application-identifier']==TEAM+'.'+PACKAGE and profile['Entitlements']['get-task-allow'] is False,'Wrong profile entitlements')
 require(len(profile['DeveloperCertificates'])==1 and hashlib.sha256(profile['DeveloperCertificates'][0]).hexdigest()==expected_cert_sha256.lower(),'Wrong profile certificate')
 ent=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
 require(ent['application-identifier']==TEAM+'.'+PACKAGE and ent.get('get-task-allow',False) is False,'Wrong signed app entitlements')
 with tempfile.TemporaryDirectory() as td:
  prefix=str(Path(td)/'cert')
  subprocess.run(['codesign','-d','--extract-certificates',prefix,str(app)],check=True,capture_output=True)
  require(sha(prefix+'0')==expected_cert_sha256.lower(),'Actual signature certificate mismatch')
 return {'deep_strict':True,'nested_frameworks_verified':True,'profile_certificate_match':True,'team':TEAM,'bundle':PACKAGE}

def technical_preflight(*,provenance,provider_archive,ipa,policy,executed_log,audience,builds,now,expected_cert_sha256,repo):
 m=check_provenance(provenance,provider_archive,ipa,policy,executed_log,repo)
 check_toolchain(m['toolchain'],now.date().isoformat())
 check_build_number(builds,m['build'],now);check_audience_snapshot(audience,now)
 audit=check_archive(ipa,m['build'],m['version'])
 with tempfile.TemporaryDirectory() as td:
  # check_archive already rejected paths/symlinks/bombs before extraction.
  with zipfile.ZipFile(ipa) as z:
   z.extractall(td)
   for member in z.infolist():
    path=Path(td)/member.filename
    if path.is_file():path.chmod((member.external_attr>>16)&0o777 or 0o644)
  signature=verify_signatures(Path(td)/'Payload/Runner.app',expected_cert_sha256)
 return {'technical_preflight':True,'audit':audit,'signature':signature,'permission_verified':False,'legal_verified':False,'upload_allowed':False,'distribution_allowed':False}

# There is intentionally no upload action. The assigned executor must inspect
# original owner decisions, owning-provider freshness, and privacy completeness before any separately authorized archive/upload operation.
