from pathlib import Path
import subprocess,os,shutil,json,hashlib
root=Path(os.environ.get("CHAT_PLATFORM_PROFILE_ROOT", "/tmp/chat-platform-profile"))
static=root/'swiftui-clean/.build/release/ChatHistorySwiftUI';shutil.copy2(static,root/'SwiftUI-clean-static-row')
plan=[('swiftui',v) for v in ['baseline','static-row','static-row','baseline','baseline','static-row']]
results=[]
for i,(app,variant) in enumerate(plan):
 if app=='swiftui':
  exe=root/'Chat History — SwiftUI.app/Contents/MacOS/ChatHistorySwiftUI';shutil.copy2(root/('SwiftUI-clean-baseline' if variant=='baseline' else 'SwiftUI-clean-static-row'),exe)
  subprocess.run(['codesign','--force','--deep','--sign','-',str(exe.parents[2])],check=True,capture_output=True)
 log=root/f'video-verified-pair-{i+1:02d}-{app}-{variant}.log';env=dict(os.environ,CHAT_PLATFORM_VARIANT=variant);env.pop('CHAT_PLATFORM_TRACE',None)
 print(f'{i+1}/{len(plan)} {app} {variant}',flush=True)
 with log.open('w') as f:subprocess.run(['bun','--cwd','/tmp/chat-native-benchmark-runner','platform-ablation.ts','--app',app,'--warmups','0','--iterations','1','--launch-attempts','1'],env=env,stdout=f,stderr=subprocess.STDOUT,check=True)
 jsonpath=next(line for line in log.read_text().splitlines() if line.startswith('/Users/') and line.endswith('.json'))
 data=json.load(open(jsonpath));it=data['apps'][0]['iterations'][0]
 exe=data['apps'][0]['executable'];digest=hashlib.sha256(Path(exe).read_bytes()).hexdigest()
 results.append(dict(app=app,variant=variant,json=jsonpath,executableSHA256=digest,firstContentMs=it['firstContentMs'],readyToVideoMs=it['firstContentMs']-it['internalFirstContentMs'],switchContentMs=it['switchContentMs'],topJumpMs=it['topJumpMs']))
 (root/'results/video-verified-pairs.json').write_text(json.dumps(results,indent=2))
 print(results[-1],flush=True)
