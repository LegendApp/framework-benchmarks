import os,json,pathlib,subprocess,tempfile,time,signal,statistics,sys
root=pathlib.Path('/Users/jay/Documents/code/legendapp/chat-history-comparison');launch=root/'.build/chat-history-benchmarks/chat-history-launch-app'
labels={'react-native':'React Native','legend-shell':'Legend Shell','electron':'Electron','tauri':'Tauri','deno-webview':'Deno WebView','deno-cef':'Deno CEF','flutter':'Flutter','gpui':'GPUI','swiftui':'SwiftUI','appkit':'AppKit'}
fixtures=json.load(open(root/'benchmarks/chat-history/fixtures.local.json'))
def processes():
 rows={}
 for l in subprocess.check_output(['ps','-axo','pid=,ppid=,time=,comm='],text=True).splitlines():
  parts=l.strip().split(None,3)
  if len(parts)!=4:continue
  pid,ppid,cpu,command=parts; val=0
  for n in cpu.split(':'):val=val*60+float(n)
  rows[int(pid)]={'ppid':int(ppid),'cpuSeconds':val,'command':command}
 return rows
def webkit(row):return '/com.apple.WebKit.' in row['command']
def tree(pid,baseline,rows,usewebkit):
 ids={pid}|{p for p,r in rows.items() if usewebkit and webkit(r) and p not in baseline}
 while True:
  new=ids|{p for p,r in rows.items() if r['ppid'] in ids}
  if ids==new:break
  ids=new
 return {p:rows[p] for p in ids if p in rows}
for suite in ['chat-history','hello-world']:
 for app,label in labels.items():
  if suite=='chat-history' and app=='legend-shell':continue
  print(suite,app,flush=True)
  bundle=root/'.build'/f'{suite}-benchmarks'/f'{"Chat History" if suite=="chat-history" else "Hello World"} — {label}.app'
  with tempfile.TemporaryDirectory(prefix='final-idle-') as tmp:
   env=os.environ.copy();env['CHAT_HISTORY_BENCHMARK_ALLOW_LOCKED']='0';events=pathlib.Path(tmp)/'events.jsonl';args=[]
   if suite=='chat-history':
    config={'version':2,'loadImages':False,'switchDelayMs':600000,'topDelayMs':600000,'targets':[{k:f[k] for k in ['id','provider']} for f in fixtures['fixtures']]}
    if app=='react-native':
     from urllib.parse import quote
     eventname=pathlib.Path(tmp).name+'.json';config['eventFileName']=eventname;events=pathlib.Path.home()/'Library/Application Support/Legend Chat History/chat-history-benchmark'/eventname
     args=['--chat-history-benchmark='+quote(json.dumps(config),safe='')]
    configpath=pathlib.Path(tmp)/'config.json';configpath.write_text(json.dumps(config));env['CHAT_HISTORY_BENCHMARK_CONFIG']=str(configpath);env['CHAT_HISTORY_BENCHMARK_EVENTS']=str(events)
   else:
    env.pop('CHAT_HISTORY_BENCHMARK_CONFIG',None);env.pop('CHAT_HISTORY_BENCHMARK_EVENTS',None)
   baseline=set(processes());p=None
   try:
    launched=json.loads(subprocess.check_output([str(launch),str(bundle),'-ApplePersistenceIgnoreState','YES',*args],env=env));p=launched['pid']
    if suite=='chat-history':
     deadline=time.monotonic()+90
     while time.monotonic()<deadline:
      try:
       s=events.read_text().strip();ev=json.loads(s) if s.startswith('[') else [json.loads(l) for l in s.splitlines()]
       if any(e.get('name')=='contentReady' and e.get('phase')=='initial' for e in ev):break
      except (FileNotFoundError,json.JSONDecodeError):pass
      time.sleep(.1)
     else:raise Exception('initial readiness timeout')
    time.sleep(10)
    samples=[];previous=tree(p,baseline,processes(),app in ['tauri','deno-webview']);t=time.monotonic();allids=set(previous)
    for _ in range(4):
     time.sleep(5);rows=processes();now=time.monotonic();current=tree(p,baseline,rows,app in ['tauri','deno-webview']);allids.update(current)
     delta=sum(max(0,r['cpuSeconds']-previous.get(pid,{'cpuSeconds':r['cpuSeconds']})['cpuSeconds']) for pid,r in current.items());samples.append({'cpuPercentOneCore':100*delta/(now-t),'intervalSeconds':now-t,'processes':current});previous=current;t=now
    session=json.loads(subprocess.check_output([str(launch),'--check-session']));assert not session['locked'] and session['onConsole']
    out={'suite':suite,'app':app,'label':label,'timestamp':time.time(),'settleSeconds':10,'sampleSeconds':20,'meanCpuPercentOneCore':sum(s['cpuPercentOneCore']*s['intervalSeconds'] for s in samples)/sum(s['intervalSeconds'] for s in samples),'samples':samples,'session':session,'webKitAttribution':'New helpers relative to prelaunch baseline' if app in ['tauri','deno-webview'] else None}
    with open(sys.argv[1],'a') as f:f.write(json.dumps(out)+'\n')
    print('CPU',round(out['meanCpuPercentOneCore'],3),flush=True)
   finally:
    if p:
     try:os.kill(p,signal.SIGTERM)
     except ProcessLookupError:pass
     time.sleep(.5)
     try:os.kill(p,signal.SIGKILL)
     except ProcessLookupError:pass
    if events.exists():events.unlink()
