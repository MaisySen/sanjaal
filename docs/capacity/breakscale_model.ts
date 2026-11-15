import { Engine } from '/tmp/bsr/breakscale/src/sim/engine.ts';
function topo(rps: number, apiMs: number) {
  return { nodes: [
    { id:'client', kind:'client', label:'Client', x:0,y:0, config:{ rps, timeoutMs: 10000 } },
    { id:'api', kind:'service', label:'API (12 php-fpm workers)', x:1,y:0, config:{ capacity:12, serviceMs: apiMs, serviceCv:0.5, queueLimit:48 } },
    { id:'db', kind:'db', label:'Aiven Postgres (20 conn cap)', x:2,y:0, config:{ capacity:12, serviceMs:20, serviceCv:0.7, queueLimit:48 } },
  ], edges:[{id:'e1',from:'client',to:'api',weight:1},{id:'e2',from:'api',to:'db',weight:1}] } as any;
}
for (const [name, ms] of [['feed /posts (about 2200 ms server time, derived)',2200],['rooms list (about 750 ms, derived)',750]] as const) {
  console.log('## '+name);
  for (const rps of [1,2,4,5,6,8,10,15,16,20,30]) {
    const e = new Engine(topo(rps, ms) as any, 7);
    const g:number[]=[],p:number[]=[],er:number[]=[];
    for (let sec = 0; sec < 300; sec++) { for (let i = 0; i < 60; i++) e.advance(1000/60); if (sec>=120){ const s:any=e.snapshot().system; g.push(s.goodputRps); p.push(s.p95); er.push(s.errorRate);} }
    const m=(a:number[])=>a.reduce((x,y)=>x+y,0)/a.length;
    console.log(`offered ${rps}/s -> goodput ${m(g).toFixed(1)}/s, p95 ${Math.round(m(p))} ms, errors ${(m(er)*100).toFixed(0)}% (mean of seconds 120-300)`);
  }
}
