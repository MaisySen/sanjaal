#!/usr/bin/env python3
"""Read-only App Store Connect snapshot transport for Sanjaal release gates.

Caller supplies a short-lived JWT from the authorized selected identity through a
private process channel, never a CLI argument/log. This client never mutates Apple
state, never answers compliance and never decides owner authority. Its token may
have wider grants than this local client; keep credential exposure separately scoped.
"""
import json,urllib.request,urllib.parse,datetime,re
APP='6837257828';ORIGIN='https://api.appstoreconnect.apple.com'
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):raise ValueError('Refuse authenticated redirect')
class AppleReadOnly:
 def __init__(self,jwt,opener=None):
  if not jwt:raise ValueError('Missing private JWT')
  self._known_group_ids=set();self._jwt=jwt;self._open=opener or urllib.request.build_opener(NoRedirect()).open
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
  allowed.update('/v1/betaGroups/'+gid+'/betaTesters' for gid in self._known_group_ids)
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
  result=self.collection(f'/v1/apps/{APP}/betaGroups',{'limit':200})
  groups=[];all_testers={}
  for group in result['data']:
   gid=group['id']
   if group.get('type')!='betaGroups' or not re.fullmatch('[A-Za-z0-9-]{1,100}',gid):raise ValueError('Invalid Apple group ID')
   self._known_group_ids.add(gid)
   testers=self.collection('/v1/betaGroups/'+gid+'/betaTesters',{'limit':200})
   ids=[]
   for tester in testers['data']:
    if tester.get('type')!='betaTesters':raise ValueError('Invalid tester resource')
    tid=tester['id'];attrs=tester.get('attributes',{});ids.append(tid)
    # email is an observed identifier, never proof of owner identity or permission.
    all_testers[tid]={'id':tid,'email_identifier':attrs.get('email'),'state':attrs.get('state')}
   groups.append({'id':gid,'attributes':group.get('attributes',{}),'tester_ids':ids,'testers_enumeration_complete':True})
  return {'app_id':APP,'fetched_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'),'groups':groups,'testers':list(all_testers.values()),'group_membership_enumeration_complete':True,'complete_groups_and_testers':False,'unverified_tester_identifiers':[x['email_identifier'] or x['id'] for x in all_testers.values()],'remaining_checks':['owner identity/audience review','automatic-distribution field must be independently verified','direct build testers and all audience paths','legal authority, not API-derived']}
 def builds(self):return self.collection(f'/v1/apps/{APP}/builds',{'limit':200})
 def build_number_snapshot(self):
  collection=self.builds();numbers=[]
  for resource in collection['data']:
   if resource.get('type')!='builds':raise ValueError('Invalid build resource')
   value=resource.get('attributes',{}).get('version')
   # This app uses monotonically increasing integer build numbers. Other shapes
   # require review, not truncation to an integer that might hide an existing build.
   if not isinstance(value,str) or not re.fullmatch('[0-9]+',value):raise ValueError('Non-integer Apple build number needs review')
   numbers.append(int(value))
  return {'app_id':APP,'fetched_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z'),'all_versions_enumerated':True,'build_numbers':sorted(set(numbers))}

