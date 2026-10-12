#!/usr/bin/env python3
"""Visual correctness probe using synthetic histories, never performance scores.
Run under the macOS capture preparation helper after exporting both apps.
"""
import pathlib,json,os,subprocess,time,signal
root=pathlib.Path(__file__).resolve().parents[3];out=root/'ChatHistory/benchmark/results/layout-alignment-2026-09-16';out.mkdir(exist_ok=True);home=pathlib.Path('/tmp/chat-layout-rich-home');sessions=home/'.codex/sessions/2026/09/16';sessions.mkdir(parents=True,exist_ok=True)
texts=['# Markdown rendering\n\n**Bold**, *italic*, ~~strike~~ and [a link](https://example.com).\n\n- first\n- second\n  - nested\n\n> A quote with **formatting**.\n\n| Name | Value |\n| --- | --- |\n| answer | `42` |\n\n```javascript\n// Full code is retained\nfunction greet(name) {\n  return "Hello " + name;\n}\n```', '## Syntax highlighting\n\n```swift\nlet message = "Hello"\nfunc greet() -> String { return message }\n```\n\n```cpp\n// C++ grammar\nint main() { return 42; }\n```\n\n```ruby\ndef greet(name)\n  puts "Hello #{name}"\nend\n```']
ids=['11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222']
for ident,body in zip(ids,texts):
 records=[{'type':'session_meta','payload':{'id':ident,'cwd':'/visual-proof','timestamp':'2026-09-16T00:00:00Z'}},{'type':'response_item','payload':{'type':'message','role':'assistant','content':[{'type':'output_text','text':body}]}}]
 (sessions/f'rollout-{ident}.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in records))
config=pathlib.Path('/tmp/chat-layout-rich-config.json');config.write_text(json.dumps({'version':2,'appearance':'dark','loadImages':False,'topDelayMs':1500,'switchDelayMs':1500,'targets':[{'provider':'codex','id':'codex:'+i} for i in ids]}))
base=root/'.build/chat-history-benchmarks';capture=base/'Chat History Benchmark Capture.app/Contents/MacOS/chat-history-screen-record';print('capture exists',capture.exists(),flush=True)
if not capture.exists():
 capture=next((base/'Chat History Benchmark Capture.app/Contents/MacOS').iterdir())
for app,label in [('flutter','Flutter'),('gpui','GPUI')]:
 events=out/f'{app}.events.jsonl';events.unlink(missing_ok=True)
 video=out/f'{app}-rich.mp4';rec=subprocess.Popen([str(capture),str(video),str(out/f'{app}-rich.capture.json')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 line=rec.stdout.readline();print(line,flush=True)
 env={**os.environ,'CHAT_HISTORY_BENCHMARK_CONFIG':str(config),'CHAT_HISTORY_BENCHMARK_EVENTS':str(events),'CHAT_HISTORY_BENCHMARK_HOME':str(home)}
 launched=json.loads(subprocess.check_output([str(base/'chat-history-launch-app'),str(base/f'Chat History — {label}.app')],env=env));pid=launched['pid'];rec.stdin.write(f'pid {pid}\n');rec.stdin.flush()
 try:
  deadline=time.time()+45
  while time.time()<deadline:
   rows=[json.loads(l) for l in events.read_text().splitlines()] if events.exists() else []
   if any(r.get('name')=='contentReady' and r.get('phase')=='switch' for r in rows):break
   time.sleep(.2)
  else:raise RuntimeError(f'{app} never rendered rich fixture: {rows}')
  time.sleep(1)
  win=json.loads(subprocess.check_output([str(base/'chat-history-window-info'),str(pid)]));(out/f'{app}-window.json').write_text(json.dumps(win))
 finally:
  rec.stdin.write('q\n');rec.stdin.flush();rec.communicate(timeout=20)
  os.kill(pid,signal.SIGTERM)
 print(app,'recorded',flush=True)
