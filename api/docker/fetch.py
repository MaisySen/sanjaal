import json,urllib.request,zlib,hashlib,base64,io,tarfile,os,sys
pk=json.load(open('pkgs.json')); root='/tmp/nb/root'; os.makedirs(root,exist_ok=True)
def streams(b):
    out=[];
    while b:
        d=zlib.decompressobj(31); raw=d.decompress(b); used=len(b)-len(d.unused_data); out.append((b[:used],raw)); b=d.unused_data
    return out
bad=0;db=[]
for p in pk:
    u=f"https://dl-cdn.alpinelinux.org/alpine/v3.24/{p['repo']}/x86_64/{p['P']}-{p['V']}.apk"
    b=urllib.request.urlopen(u,timeout=120).read()
    st=streams(b)
    # signature stream (optional) then control then data
    names=[]
    ctl=None
    for i,(g,raw) in enumerate(st):
        if raw[:1]==b'\x00' or True:
            t=tarfile.open(fileobj=io.BytesIO(raw)); nm=t.getnames()
            if any(n.startswith('.SIGN') for n in nm): continue
            if '.PKGINFO' in nm: ctl=(i,g,t); continue
            data=t
    c='Q1'+base64.b64encode(hashlib.sha1(ctl[1]).digest()).decode()
    if c!=p['C']: print('CHECKSUM MISMATCH',p['P']); bad+=1
    for m in data.getmembers():
        if m.name.startswith('.'): continue
        if m.islnk() or m.issym() or m.isreg() or m.isdir():
            try: data.extract(m,root,filter='fully_trusted')
            except Exception as e: print('x',m.name,e)
    db.append(p['P']+'-'+p['V'])
open(root+'/etc/.sanjaal-packages','w').write('\n'.join(db)+'\n') if os.path.isdir(root+'/etc') else None
print('done bad=',bad)
