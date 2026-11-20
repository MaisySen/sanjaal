#!/usr/bin/env python3
"""Disposable synthetic diagnostic, never connects to a remote database or app."""
import concurrent.futures,datetime,json,pathlib,subprocess,threading,time
OUT=pathlib.Path('build/db-1gb');OUT.mkdir(parents=True,exist_ok=True)
NAME='sanjaal-isolated-db-1gb'
IMAGE='postgres:18-alpine@sha256:b6972e1115a4ff8eba5d7f7d19184926d1e16d7d1136ae1e1a7ebf286da0f015'
stop=threading.Event();phase='starting';results=[];samples=[]
def run(args,timeout=90,check=True):
 p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 if check and p.returncode:raise RuntimeError(str(args[:4])+': '+p.stdout[-2000:])
 return p

def sql(q,user='postgres',timeout=420,check=True):
 return run(['docker','exec',NAME,'psql','-X','-At','-v','ON_ERROR_STOP=1','-U',user,'-d','fixture','-c',q],timeout,check)

def sampler():
 while not stop.wait(1):
  try:
   p=run(['docker','exec',NAME,'sh','-c','for f in memory.current memory.peak memory.events memory.stat; do echo FILE:$f; cat /sys/fs/cgroup/$f; done'],10,False)
   samples.append({'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'phase':phase,'cgroup':p.stdout})
  except Exception as e:samples.append({'phase':phase,'error':str(e)})

def snapshot(label):
 d={'label':label,'at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 for k,args in [('inspect',['docker','inspect',NAME]),('processes',['docker','top',NAME,'-eo','pid,ppid,rss,comm'])]:d[k]=run(args,20,False).stdout
 d['database']=sql("SELECT pg_postmaster_start_time(); SELECT datname,numbackends,temp_files,temp_bytes,deadlocks FROM pg_stat_database WHERE datname='fixture'; SELECT state,count(*) FROM pg_stat_activity GROUP BY state;",check=False).stdout
 (OUT/(label+'.json')).write_text(json.dumps(d,indent=2));return d

def parallel(label,count,query,seconds=0):
 global phase
 phase=label;start=time.monotonic()
 with concurrent.futures.ThreadPoolExecutor(max_workers=count)as pool:
  futures=[pool.submit(sql,query,'fixture_user',420,False)for _ in range(count)]
  time.sleep(min(3,seconds)if seconds else 1);snapshot(label+'-during')
  rows=[f.result()for f in futures]
 results.append({'phase':label,'concurrency':count,'elapsed_s':time.monotonic()-start,'returncodes':[r.returncode for r in rows],'output':[r.stdout[-1200:]for r in rows]})
 snapshot(label+'-after')

try:
 run(['docker','pull',IMAGE],180)
 run(['docker','run','--detach','--name',NAME,'--network','none','--memory','1g','--memory-swap','1g','--cpus','1','--pids-limit','256','--shm-size','256m','-e','POSTGRES_HOST_AUTH_METHOD=trust','-e','POSTGRES_DB=fixture',IMAGE,'-c','shared_buffers=193536kB','-c','work_mem=2048kB','-c','maintenance_work_mem=91136kB','-c','max_connections=20','-c','max_parallel_workers_per_gather=2','-c','autovacuum_max_workers=3','-c','idle_in_transaction_session_timeout=86400000','-c','statement_timeout=400000'],90)
 for _ in range(60):
  if run(['docker','exec',NAME,'pg_isready','-U','postgres','-d','fixture'],10,False).returncode==0:break
  time.sleep(1)
 else:raise RuntimeError('Disposable database did not start')
 inspect=json.loads(run(['docker','inspect',NAME]).stdout)[0]
 assert inspect['HostConfig']['Memory']==1073741824 and inspect['HostConfig']['MemorySwap']==1073741824 and inspect['HostConfig']['NetworkMode']=='none'
 (OUT/'scope.json').write_text(json.dumps({'image':IMAGE,'memory_limit_bytes':1073741824,'swap_disabled':True,'network':'none','data':'synthetic only','production_credentials':False,'diagnostic_statement_timeout_ms':400000,'scope_limits':['Not Aiven managed image/extensions/management agents','Not production workload or ORM/latency','A non-reproduction does not clear production OOM','No tuning proposal is accepted by this test']},indent=2))
 print(sql("CREATE ROLE fixture_user LOGIN; GRANT CONNECT ON DATABASE fixture TO fixture_user; SELECT name,setting,unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','max_connections','max_parallel_workers_per_gather','autovacuum_max_workers','idle_in_transaction_session_timeout');").stdout)
 thread=threading.Thread(target=sampler);thread.start();phase='idle-baseline';time.sleep(30);snapshot('baseline')
 parallel('four-idle-connections',4,'SELECT pg_sleep(30);',30)
 parallel('twelve-idle-connections',12,'SELECT pg_sleep(30);',30)
 parallel('twenty-one-connection-rejection',21,'SELECT pg_sleep(15);',15)
 parallel('twelve-bounded-sorts',12,"SELECT count(*) FROM (SELECT md5(i::text),repeat(i::text,32) FROM generate_series(1,100000) i ORDER BY md5(i::text)) s;")
 phase='synthetic-maintenance';sql("CREATE TABLE fixture_rows AS SELECT i,md5(i::text) v FROM generate_series(1,200000)i; CREATE INDEX fixture_rows_v ON fixture_rows(v);")
 sql('VACUUM (ANALYZE) fixture_rows;');snapshot('maintenance-after')
 parallel('twelve-persistent-session-rounds',12,"DO $body$ BEGIN FOR iteration IN 1..60 LOOP PERFORM count(*) FROM (SELECT md5(i::text) FROM generate_series(1,10000)i ORDER BY md5(i::text))s; PERFORM pg_sleep(5); END LOOP; END $body$;",300)
 phase='post-workload-idle';time.sleep(60);snapshot('final')
 state=json.loads(run(['docker','inspect',NAME]).stdout)[0]['State'];assert state['Running'] and not state['OOMKilled']
 assert any(c!=0 for r in results if r['phase']=='twenty-one-connection-rejection'for c in r['returncodes']), 'Connection ceiling negative was not exercised'
 assert all(c==0 for r in results if r['phase']!='twenty-one-connection-rejection'for c in r['returncodes']), 'Unexpected workload failure'
 print('Diagnostic phases completed. No production reliability clearance is implied.')
finally:
 stop.set()
 if 'thread'in globals():thread.join(15)
 (OUT/'samples.json').write_text(json.dumps(samples,indent=2));(OUT/'phases.json').write_text(json.dumps(results,indent=2))
 (OUT/'postgres.log').write_text(run(['docker','logs',NAME],20,False).stdout)
 run(['docker','rm','-f',NAME],20,False)

# A separate, disposable memory-pressure negative verifies Docker/kernel OOM detection.
# No production connection, data, or persistent volume exists in either container.
negative=NAME+'-negative'
try:
 cmd=['docker','run','--name',negative,'--network','none','--memory','1g','--memory-swap','1g','--cpus','1','--pids-limit','32','--entrypoint','awk',IMAGE,'BEGIN { s=sprintf("%1048576s","x"); for(i=0;i<2048;i++) a[i]=s i; print length(a[2047]); }']
 p=run(cmd,90,False);ins=json.loads(run(['docker','inspect',negative]).stdout)[0]
 (OUT/'oom-instrumentation-negative.json').write_text(json.dumps({'returncode':p.returncode,'output':p.stdout,'inspect':ins},indent=2))
 assert ins['HostConfig']['Memory']==1073741824 and ins['State']['OOMKilled'] and p.returncode==137, 'OOM negative failed to prove instrumentation'
 print('Separate disposable pressure negative was OOM-killed as expected. Not a production workload or cause.')
finally:
 run(['docker','rm','-f',negative],20,False)
