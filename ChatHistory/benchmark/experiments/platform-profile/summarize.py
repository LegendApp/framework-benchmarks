import os
from pathlib import Path
import json,statistics,collections
root=Path(os.environ.get('CHAT_PLATFORM_PROFILE_ROOT', '/tmp/chat-platform-profile')) / 'results'
def med(xs):return round(statistics.median(xs),3) if xs else None
for pattern in ['appkit-baseline-[23]','swiftui-baseline-[234]','react-native-segmented-hooks-native-[234]','swiftui-no-explicit-id-[234]']:
 runs=collections.defaultdict(list); counts=collections.defaultdict(list)
 for path in sorted(root.glob(pattern+'.trace.json')):
  tag=path.name.replace('.trace.json','')
  if not (root/(tag+'.events.json')).exists(): continue
  ev=json.loads(path.read_text());events=json.loads((root/(tag+'.events.json')).read_text()); phases={}
  for e in events:
   if e['name'] in ['contentReady','viewportReady']:phases[e['phase']]=(e['timestampMs']-e['durationMs'],e['timestampMs'])
  grouped=collections.defaultdict(list)
  for e in ev:
   ts=e['epochEndMs']-e['durationMs'];phase=next((p for p,(start,end) in phases.items() if start<=ts<=end),None)
   if not phase:continue
   grouped[(phase,e['name'],e['main'])].append(e)
  for key,es in grouped.items():runs[key].append(sum(e['durationMs'] for e in es));counts[key].append(len(es))
 print('\n',pattern)
 for k,vs in runs.items():
  if max(vs)>.1 or k[1] in ['row.body','row.metadata','cell.viewFor','markdown.request']:print(k,'calls',med(counts[k]),'ms',med(vs))
