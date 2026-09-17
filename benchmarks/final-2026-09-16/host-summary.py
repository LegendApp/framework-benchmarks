import json,pathlib,datetime,statistics
p=pathlib.Path(__file__).parent;rows=[json.loads(l) for l in (p/'host-monitor.jsonl').read_text().splitlines()];out={}
for suite,path,key in [('chat-history',p/'../chat-history/results/2026-09-16T20-35-45.623Z.json','apps'),('hello-world',p/'../hello-world/results/2026-09-16T21-25-32.060Z/results.json','results')]:
 r=json.load(open(path));start=min(i['videoEvidence']['launchTimestampMs'] for a in r[key] for i in a['iterations']);end=datetime.datetime.fromisoformat(r['measuredAt'].replace('Z','+00:00')).timestamp()*1000
 samples=[s for s in rows if start<=s['timestampMs']<=end];cpu=sorted(s['cpuBusyPercent'] for s in samples)
 out[suite]={'startMs':start,'endMs':end,'samples':len(samples),'hostCpuMedianPercent':statistics.median(cpu),'hostCpuP90Percent':cpu[int((len(cpu)-1)*.9)],'hostCpuMaxPercent':max(cpu),'thermalStates':sorted(set(s['thermalState'] for s in samples))}
json.dump(out,open(p/'host-summary.json','w'),indent=2);print(json.dumps(out,indent=2))
