import json,hashlib,gzip,io,tarfile,os,sys,urllib.request,urllib.parse,base64
from security_floor import check_prepared_root, check_app_layer, REVIEWED_IMAGE
root=os.environ.get('SANJAAL_PREPARED_ROOT', '/tmp/nb/final')
# Enforce before reading any credential or making a network request.
check_prepared_root(root)
USER='sanjaalapp'; REPO='sanjaalapp/sanjaal-api'; TAG=sys.argv[1]; BASE_TAG=REVIEWED_IMAGE
PAT=open('/tmp/pat.keep').read().strip()
def req(url, method='GET', data=None, headers=None, tok=None):
    h=dict(headers or {})
    if tok: h['Authorization']='Bearer '+tok
    r=urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        resp=urllib.request.urlopen(r, timeout=600); return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e: return e.code, dict(e.headers), e.read()
q='service=registry.docker.io&scope='+urllib.parse.quote(f'repository:{REPO}:push,pull',safe=':,/')
r=urllib.request.Request('https://auth.docker.io/token?'+q, headers={'Authorization':'Basic '+base64.b64encode(f'{USER}:{PAT}'.encode()).decode()})
tok=json.load(urllib.request.urlopen(r,timeout=60))['token']
REG='https://registry-1.docker.io/v2/'
ACC='application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
s,h,b=req(REG+f'{REPO}/manifests/{BASE_TAG}',headers={'Accept':ACC},tok=tok); assert s==200
base=json.loads(b); s,h,cb=req(REG+f'{REPO}/blobs/'+base['config']['digest'],tok=tok); cfg=json.loads(cb)
def mk(filt):
    buf=io.BytesIO()
    with tarfile.open(fileobj=buf,mode='w') as t:
        for dp,dn,fn in os.walk(root):
            dn.sort(); rel=os.path.relpath(dp,root)
            ents=[(rel,dp)] if rel!='.' else []
            ents+= [(os.path.join(rel,f) if rel!='.' else f, os.path.join(dp,f)) for f in sorted(fn)]
            for a,p in ents:
                if not filt(a): continue
                ti=t.gettarinfo(p,a); ti.uid=ti.gid=0; ti.uname=ti.gname=''; ti.mtime=0
                if ti.isreg():
                    with open(p,'rb') as fh: t.addfile(ti,fh)
                else: t.addfile(ti)
    raw=buf.getvalue(); gz=gzip.compress(raw,6,mtime=0)
    return 'sha256:'+hashlib.sha256(raw).hexdigest(),'sha256:'+hashlib.sha256(gz).hexdigest(),gz
def push_blob(data,dig):
    s,h,_=req(REG+f'{REPO}/blobs/uploads/','POST',b'',tok=tok); assert s==202,s
    h={k.lower():v for k,v in h.items()}; loc=h['location']; loc=loc if loc.startswith('http') else 'https://registry-1.docker.io'+loc
    s,h,b=req(loc+('&' if '?' in loc else '?')+'digest='+dig,'PUT',data,{'Content-Type':'application/octet-stream','Content-Length':str(len(data))},tok=tok)
    print('blob',dig[:19],len(data),s); assert s==201,(s,b[:200])
isapp=lambda a: a=='app' or a.startswith('app/')
L1=mk(lambda a: not isapp(a)); L2=mk(isapp)
# Check the exact serialized bytes, not just the earlier source read.
check_app_layer(L2[2])
push_blob(L1[2],L1[1]); push_blob(L2[2],L2[1])
cfg['rootfs']['diff_ids']=[L1[0],L2[0]]
cfg['history']=[{'created_by':'sanjaal alpine 3.24.4 + php 8.4.27 (alpine packages) + caddy + php-fpm'},{'created_by':'sanjaal app'}]
cfg['config']['Cmd']=['/app/start.sh']; cfg['config'].pop('Entrypoint',None)
cb=json.dumps(cfg,separators=(',',':')).encode(); cdig='sha256:'+hashlib.sha256(cb).hexdigest(); push_blob(cb,cdig)
mt=base['layers'][0]['mediaType']
man={'schemaVersion':2,'mediaType':base['mediaType'],'config':{'mediaType':base['config']['mediaType'],'digest':cdig,'size':len(cb)},
 'layers':[{'mediaType':mt,'digest':L1[1],'size':len(L1[2])},{'mediaType':mt,'digest':L2[1],'size':len(L2[2])}]}
mb=json.dumps(man,separators=(',',':')).encode()
s,h,b=req(REG+f'{REPO}/manifests/{TAG}','PUT',mb,{'Content-Type':base['mediaType']},tok=tok); print('manifest',s,b[:200]); assert s==201
print('PUSHED',TAG)
