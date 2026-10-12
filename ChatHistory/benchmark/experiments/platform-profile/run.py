import os
from pathlib import Path
import subprocess,json,os,time,urllib.parse,shutil,signal,argparse
repo=Path(__file__).resolve().parents[4]; root=Path(os.environ.get("CHAT_PLATFORM_PROFILE_ROOT", "/tmp/chat-platform-profile"))
build=repo/'.build/chat-history-benchmarks'; out=root/'results';out.mkdir(exist_ok=True)
manifest=json.loads((repo/'ChatHistory/benchmark/fixtures.local.json').read_text())
config={'version':2,'loadImages':False,'topDelayMs':3000,'switchDelayMs':3000,'targets':[{k:f[k] for k in ['id','provider']} for f in manifest['fixtures']]}
(root/'config.json').write_text(json.dumps(config))
names={'appkit':('Chat History — AppKit.app','ChatHistoryAppKit'),'swiftui':('Chat History — SwiftUI.app','ChatHistorySwiftUI'),'react-native':('Chat History — React Native.app','Legend Chat History')}
parser=argparse.ArgumentParser();parser.add_argument('--apps',default='appkit,swiftui,react-native');parser.add_argument('--rounds',type=int,default=3);parser.add_argument('--sample',action='store_true');parser.add_argument('--variant',default='baseline');parser.add_argument('--native-trace',action='store_true');parser.add_argument('--baseline-binary',action='store_true');args=parser.parse_args()
for n in range(args.rounds):
 for app in args.apps.split(','):
  bundle,exe=names[app]; dst=root/bundle
  if app=='react-native': dst=build/bundle
  else:
   if not dst.exists():shutil.copytree(build/bundle,dst)
   shutil.copy2(root/'SwiftUI-baseline' if app=='swiftui' and args.baseline_binary else root/f'source/apps/chat-history-{app}/.build/release'/exe,dst/'Contents/MacOS'/exe)
   subprocess.run(['codesign','--force','--deep','--sign','-',str(dst)],check=True,capture_output=True)
  tag=f'{app}-{args.variant}-'+('native-' if args.native_trace else '')+('sample-' if args.sample else '')+str(n+1)
  events=out/(tag+'.events.jsonl'); trace=out/(tag+'.trace.json');events.unlink(missing_ok=True);trace.unlink(missing_ok=True)
  command=[str(build/'chat-history-launch-app'),str(dst),'-ApplePersistenceIgnoreState','YES']
  if app=='react-native':
   filename='platform-profile-'+tag+'.json';events=Path.home()/'Library/Application Support/Legend Chat History/chat-history-benchmark'/filename;events.unlink(missing_ok=True)
   command+=['--chat-history-benchmark='+urllib.parse.quote(json.dumps(dict(config,eventFileName=filename)),safe='')]
  env=dict(os.environ,CHAT_HISTORY_BENCHMARK_ALLOW_LOCKED='1',CHAT_HISTORY_BENCHMARK_CONFIG=str(root/'config.json'),CHAT_HISTORY_BENCHMARK_EVENTS=str(events),CHAT_PLATFORM_TRACE=str(trace),CHAT_PLATFORM_VARIANT=args.variant)
  
  if args.native_trace:env.update(DYLD_INSERT_LIBRARIES=str(root/'NativeTrace.dylib'),CHAT_NATIVE_TRACE=str(trace))
  launch=json.loads(subprocess.check_output(command,env=env));pid=launch['pid'];samples=[]
  if args.sample:samples.append(subprocess.Popen(['/usr/bin/sample',str(pid),'1','1','-file',str(out/(tag+'-startup.sample.txt'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
  started=time.monotonic(); topSample=False; switchSample=False
  try:
   while time.monotonic()-started<25:
    try:
     raw=events.read_text(); ev=json.loads(raw) if app=='react-native' else [json.loads(l) for l in raw.splitlines() if l]
    except (FileNotFoundError,json.JSONDecodeError):ev=[]
    initial=next((e for e in ev if e.get('name')=='contentReady' and e.get('phase')=='initial'),None)
    top=next((e for e in ev if e.get('name')=='viewportReady'),None)
    if args.sample:
     if initial and not topSample and time.time()*1000 > initial['timestampMs']+2750:
      topSample=True;samples.append(subprocess.Popen(['/usr/bin/sample',str(pid),'1','1','-file',str(out/(tag+'-top.sample.txt'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
     if top and not switchSample and time.time()*1000 > top['timestampMs']+2750:
      switchSample=True;samples.append(subprocess.Popen(['/usr/bin/sample',str(pid),'1','1','-file',str(out/(tag+'-switch.sample.txt'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL))
    if any(e.get('phase')=='switch' and e.get('name')=='contentDigest' for e in ev):
     time.sleep(1.5);break
    time.sleep(.025)
   else:raise RuntimeError('timeout '+tag)
   (out/(tag+'.launch.json')).write_text(json.dumps(launch))
   (out/(tag+'.events.json')).write_text(json.dumps(ev,indent=2))
   for e in ev:
    if e.get('name') in ['windowShown','contentReady','viewportReady']:print(tag,e.get('name'),e.get('phase'),round(e.get('durationMs',0),2),round(e.get('timestampMs',0)-launch['launchStartedTimestampMs'],2),flush=True)
  finally:
   os.kill(pid,signal.SIGTERM)
   for p in samples:p.wait(timeout=15)
  time.sleep(.5)
