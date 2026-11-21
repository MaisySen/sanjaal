#!/usr/bin/env python3
"""Read-only App Store Connect snapshot transport for Sanjaal release gates.

Caller supplies a short-lived JWT from the authorized selected identity through a
private process channel, never a CLI argument/log. This client never mutates Apple
state, never answers compliance and never decides owner authority. Its token may
have wider grants than this local client; keep credential exposure separately scoped.
"""
import json,urllib.request,urllib.parse,datetime
APP='6837257828';ORIGIN='https://api.appstoreconnect.apple.com'
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):raise ValueError('Refuse authenticated redirect')
class AppleReadOnly:
 def __init__(self,jwt,opener=None):
  if not jwt:raise ValueError('Missing private JWT')
  self._jwt=jwt;self._open=opener or urllib.request.build_opener(NoRedirect()).open
 def _get(self,url):
  p=urllib.parse.urlsplit(url)
  if p.scheme!='https' or p.netloc!='api.appstoreconnect.apple.com' or p.username or p.fragment:raise ValueError('Untrusted Apple pagination URL')
  # Path is created only by this client or returned by Apple for same collection.
  req=urllib.request.Request(url,headers={'Authorization':'Bearer '+self._jwt,'Accept':'application/json'},method='GET')
  try:
   with self._open(req,timeout=30) as response:return json.load(response)
  except urllib.error.HTTPError as e:raise RuntimeError('Apple read failed, HTTP'+str(e.code)) from None
 def collection(self,path,query=None):
  allowed={f'/v1/apps/{APP}/betaGroups',f'/v1/apps/{APP}/builds',f'/v1/apps/{APP}/preReleaseVersions'}
  if path not in allowed:raise ValueError('Read outside assigned app collections')
  url=ORIGIN+path+('?' + urllib.parse.urlencode(query) if query else '');rows=[];seen=set()
  for _ in range(100):
   if url in seen:raise ValueError('Pagination loop')
   seen.add(url);p=urllib.parse.urlsplit(url)
   if p.path!=path:raise ValueError('Pagination changed collection')
   d=self._get(url)
   if not isinstance(d.get('data'),list):raise ValueError('Malformed Apple collection')
   rows.extend(d['data']);url=d.get('links',{}).get('next')
   if not url:return {'data':rows,'complete':True,'pages':len(seen)}
  raise ValueError('Pagination limit, incomplete snapshot')
 def audience_groups(self):
  # Relationships/tester enumeration is not yet implemented. Never emit a complete
  # audience snapshot until those are independently enumerated and identity-reviewed.
  result=self.collection(f'/v1/apps/{APP}/betaGroups',{'limit':200})
  return {'app_id':APP,'fetched_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'),'groups':result['data'],'complete_groups_and_testers':False,'unverified_tester_identifiers':['REQUIRES_TESTER_ENUMERATION_AND_OWNER_REVIEW']}
 def builds(self):return self.collection(f'/v1/apps/{APP}/builds',{'limit':200})
