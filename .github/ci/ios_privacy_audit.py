#!/usr/bin/env python3
"""Structural inventory only. Never infers privacy completeness or legal approval."""
import hashlib, plistlib

def require(value, message):
 if not value: raise ValueError(message)

def string(value): return isinstance(value,str) and bool(value.strip())
def strings(value): return isinstance(value,list) and all(string(x) for x in value)

def audit_manifest(data, path):
 try: manifest=plistlib.loads(data)
 except Exception: raise ValueError('Unreadable privacy plist: '+path) from None
 require(isinstance(manifest,dict),'Privacy root must be dictionary: '+path)
 for key in ('NSPrivacyTracking',):
  if key in manifest: require(type(manifest[key]) is bool,'Privacy flag must be Boolean: '+path)
 domains=manifest.get('NSPrivacyTrackingDomains',[])
 require(strings(domains),'Tracking domains must be strings: '+path)
 if manifest.get('NSPrivacyTracking') is True: require(bool(domains),'Tracking enabled without domains: '+path)
 if domains: require(manifest.get('NSPrivacyTracking') is True,'Tracking domains without tracking declaration: '+path)
 apis=manifest.get('NSPrivacyAccessedAPITypes',[]); collected=manifest.get('NSPrivacyCollectedDataTypes',[])
 require(isinstance(apis,list) and isinstance(collected,list),'Privacy categories must be arrays: '+path)
 categories=[]
 for api in apis:
  require(isinstance(api,dict),'API entry must be dictionary: '+path)
  category=api.get('NSPrivacyAccessedAPIType'); reasons=api.get('NSPrivacyAccessedAPITypeReasons')
  require(string(category) and strings(reasons) and bool(reasons),'API category/reasons missing: '+path)
  require(category not in categories,'Duplicate API category: '+path);categories.append(category)
 for entry in collected:
  require(isinstance(entry,dict),'Collected data entry must be dictionary: '+path)
  require(string(entry.get('NSPrivacyCollectedDataType')),'Collected data type missing: '+path)
  require(type(entry.get('NSPrivacyCollectedDataTypeLinked')) is bool and type(entry.get('NSPrivacyCollectedDataTypeTracking')) is bool,'Collected data flags must be Boolean: '+path)
  purposes=entry.get('NSPrivacyCollectedDataTypePurposes')
  require(strings(purposes) and bool(purposes),'Collected data purposes missing: '+path)
 return {'path':path,'sha256':hashlib.sha256(data).hexdigest(),'tracking_declared':manifest.get('NSPrivacyTracking'),'tracking_domain_count':len(domains),'collected_data_entry_count':len(collected),'required_api_categories':categories,'schema_values_approved':False,'behavior_coverage_reviewed':False}

def audit_packaged_manifests(archive):
 names=[x for x in archive.namelist() if x.endswith('/PrivacyInfo.xcprivacy')]
 require(bool(names),'No packaged privacy manifests')
 records=[audit_manifest(archive.read(name),name) for name in sorted(names)]
 return {'manifests':records,'packaged_manifest_count':len(records),'absence_of_collection_not_inferred':True,'sdk_coverage_verified':False,'privacy_completeness_reviewed':False}
