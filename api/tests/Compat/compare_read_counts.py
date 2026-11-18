import sys

def read(path):
    result={}
    for line in open(path):
        key, count, word=line.strip().rsplit(' ',2)
        assert word=='queries',line
        result[key]=int(count)
    return result
base,cand=map(read,sys.argv[1:])
assert base.keys()==cand.keys()
reduced=[]
for path in base:
    assert cand[path]<=base[path],(path,base[path],cand[path])
    if cand[path]<base[path]: reduced.append(path)
for fragment in ['/posts auth=1','/conversations auth=1','/comments auth=1','/messages auth=1']:
    assert any(fragment in p for p in reduced),(fragment,reduced)
print('query-count reductions:',[(p,base[p],cand[p]) for p in reduced])
