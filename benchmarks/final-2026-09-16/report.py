import json,pathlib,sys,statistics,html,os
here=pathlib.Path(__file__).resolve().parent;root=here.parents[1]
cp=pathlib.Path(sys.argv[1]).resolve();hp=pathlib.Path(sys.argv[2]).resolve();c=json.load(open(cp));h=json.load(open(hp))
names={'react-native':'React Native','legend-shell':'Legend Shell (RN)','appkit':'AppKit','swiftui':'SwiftUI','electron':'Electron','tauri':'Tauri','deno-webview':'Deno WebView','deno-cef':'Deno CEF','gpui':'GPUI','flutter':'Flutter'}
idle={(i['suite'],i['app']):i for i in map(json.loads,(here/'idle-cpu.jsonl').read_text().splitlines())}
def rel(p):return os.path.relpath(p,here)
lines=['# Final desktop application benchmarks — September 16, 2026','','Apple M4 (10 cores), arm64, macOS 26.6.1. Two discarded warmup rounds and ten measured rounds per app, rotating launch order. Fresh processes with warm filesystem caches. Timing comes from screen recordings; physical footprint comes from separate unrecorded launches.','','Times below are median milliseconds. Memory and uncompressed built app bundles are MiB (1,048,576 bytes). Bundle sizes exclude symlink duplicates and do not include OS-provided frameworks. These are application-stack comparisons under the [fairness standard](../chat-history/FAIRNESS_STANDARD.md), not isolated framework-overhead measurements.','','## Chat history','','| App | Window ms | First content ms | Jump ms | Switch ms | Initial MiB | Top MiB | Switched MiB | App size MiB |','| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
for a in sorted(c['apps'],key=lambda a:a['median']['firstContentMs']):
 m=a['median'];vals=[m[k] for k in ['windowOpenMs','firstContentMs','topJumpMs','switchContentMs']]+[m[k]['physicalFootprintBytes']/1048576 for k in ['initialMemory','topMemory','switchedMemory']]+[a['buildSizeBytes']/1048576]
 lines.append('| '+names[a['app']]+' | '+' | '.join(f'{v:.1f}' for v in vals)+' |')
lines+=['','## Hello World','','Minimal centered text apps, including standalone React Native and the separate app hosted by the Legend Shell. No transcript parsing, Markdown, or history list.','','| App | Window ms | First content ms | Memory MiB | App size MiB |','| --- | ---: | ---: | ---: | ---: |']
for a in sorted(h['results'],key=lambda a:a['median']['firstContentMs']):
 m=a['median'];vals=[m['windowOpenMs'],m['firstContentMs'],m['physicalFootprintBytes']/1048576,a['buildSizeBytes']/1048576]
 lines.append('| '+names[a['app']]+' | '+' | '.join(f'{v:.1f}' for v in vals)+' |')
lines+=['','## Timing spread','','p90 of ten completed observations; milliseconds.','','| Workload | App | Window p90 | First content p90 | Jump p90 | Switch p90 |','| --- | --- | ---: | ---: | ---: | ---: |']
for suite,apps in [('Chat history',c['apps']),('Hello World',h['results'])]:
 for a in apps:
  p=a['p90'];vals=[f'{p[k]:.1f}' if k in p else '—' for k in ['windowOpenMs','firstContentMs','topJumpMs','switchContentMs']]
  lines.append('| '+suite+' | '+names[a['app']]+' | '+' | '.join(vals)+' |')
lines+=['','## Settled idle CPU','','Separate preflight: ten seconds to settle, then twenty seconds measured using process CPU-time deltas. Percentages are of one CPU core, include attributable helpers, and exclude WindowServer. Rounded zero means below the sampling resolution.','','| App | Chat history CPU % | Hello World CPU % |','| --- | ---: | ---: |']
for key,name in names.items():
 vals=[f"{idle[(s,key)]['meanCpuPercentOneCore']:.2f}" if (s,key) in idle else '—' for s in ['chat-history','hello-world']]
 lines.append('| '+name+' | '+' | '.join(vals)+' |')
lines+=['','## Evidence','',f'- [Chat raw results]({rel(cp)}) and [generated detail]({rel(cp.with_suffix(".md"))}).',f'- [Hello World raw results]({rel(hp)}) and [generated detail]({rel(hp.with_name("results.md"))}).',f'- [Chat video viewer]({rel(cp.parent/(cp.stem+"-videos")/"index.html")}).',f'- [Hello World video viewer]({rel(hp.with_name("videos.html"))}).','- [Validation](validation.json), [builds before](builds-before.json), [builds after](builds-after.json), [host CPU and thermal samples](host-monitor.jsonl), [idle CPU samples](idle-cpu.jsonl).','','## Interpretation and limitations','',(here/'NOTES.md').read_text().strip(),'']
(here/'RESULTS.md').write_text('\n'.join(lines))
cards=[]
for a in c['apps']:
 options=''.join(f'<option value="{a["app"]}-{i:02d}.mp4">Iteration {i}</option>' for i in range(1,11))
 cards.append(f'<article><h2>{html.escape(names[a["app"]])}</h2><select onchange="this.closest(\'article\').querySelector(\'video\').src=this.value">{options}</select><video controls preload="none" src="{a["app"]}-01.mp4"></video></article>')
page='<!doctype html><html lang="en"><meta charset="utf-8"><title>Chat history recordings</title><style>body{background:#141416;color:#eee;font:16px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:20px}article{padding:16px;background:#242428;border-radius:12px}video{width:100%;margin-top:12px}</style><h1>Chat history — September 16, 2026</h1><p>10 measured recordings per app. Memory measured in separate launches.</p><main>'+''.join(cards)+'</main></html>'
(cp.parent/(cp.stem+'-videos')/'index.html').write_text(page)
print(here/'RESULTS.md')
