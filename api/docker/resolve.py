import tarfile,re,json,sys
V='v3.24'
pk={};prov={}
for r in ('main','community'):
    d=tarfile.open(f'/tmp/apk_{V}_{r}.tgz').extractfile('APKINDEX').read().decode()
    for blk in d.split('\n\n'):
        f={}
        for l in blk.split('\n'):
            if ':' in l: k,v=l.split(':',1); f[k]=v
        if 'P' not in f: continue
        f['repo']=r; pk[f['P']]=f
        prov.setdefault(f['P'],f['P'])
        for p in f.get('p','').split():
            n=re.split(r'[=<>~]',p)[0]; prov.setdefault(n,f['P'])
want=sys.argv[1:]
seen=[];q=list(want)
while q:
    n=q.pop(0)
    if n.startswith('!'): continue
    n=re.split(r'[=<>~]',n)[0]
    p=prov.get(n)
    if not p: print('MISSING',n,file=sys.stderr); continue
    if p in seen: continue
    seen.append(p); q+=pk[p].get('D','').split()
json.dump([{ 'P':p,'V':pk[p]['V'],'repo':pk[p]['repo'],'C':pk[p]['C'],'S':pk[p]['S'],'D':pk[p].get('D','')} for p in seen],open('pkgs.json','w'))
print(len(seen)); print(' '.join(f"{p}-{pk[p]['V']}" for p in seen))
