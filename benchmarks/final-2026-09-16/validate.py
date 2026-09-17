import json,pathlib,subprocess,sys,math
root=pathlib.Path(__file__).resolve().parents[2]
chatpath=pathlib.Path(sys.argv[1]).resolve();hellopath=pathlib.Path(sys.argv[2]).resolve()
chat=json.load(open(chatpath));hello=json.load(open(hellopath));out={'chat':str(chatpath),'hello':str(hellopath),'videos':[]}
assert len(chat['apps'])==9 and len(hello['results'])==10
for suite,report,apps,base in [('chat',chat,chat['apps'],chatpath.parent),('hello',hello,hello['results'],hellopath.parent)]:
 assert report['iterations']==10 and report['warmups']==2
 for a in apps:
  assert len(a['iterations'])==10 and a['buildSizeBytes']>0
  for i in a['iterations']:
   for k in ['desktopSession','memoryDesktopSession']:assert i[k]['onConsole'] and not i[k]['locked']
   for k in ['windowOpenMs','firstContentMs']+(['topJumpMs','switchContentMs'] if suite=='chat' else []):assert math.isfinite(i[k]) and i[k]>0
   for k in (['initialMemory','topMemory','switchedMemory'] if suite=='chat' else ['memory']):assert i[k]['physicalFootprintBytes']>0
   v=i['videoEvidence'];p=base/v['video'];assert p.is_file()
   if suite=='chat':
    assert i['initialContentDigest']=='3a290b9eb53fa834' and i['switchContentDigest']=='c27e9dc5a848d7f6'
    ts=v['sourceFrameTimestampsMs'];assert v['analysisVersion']==4
   else:
    assert v['recognizedText'].lower().replace(',','').replace('!','').replace(' ','')=='helloworld'
    capture=json.load(open(base/v['captureTimestamps']))
    ts=capture.get('frameTimestampsMs',capture.get('sourceFrameTimestampsMs'))
    if ts is None:raise ValueError(capture.keys())
   assert all(b>a for a,b in zip(ts,ts[1:]))
   assert len(ts)==v['frameCount'] or (suite=='hello' and len(ts)==v['frameCount']+1)
   frames=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','frame=best_effort_timestamp_time','-of','json',str(p)]))['frames']
   pts=[float(z['best_effort_timestamp_time'])*1000 for z in frames]
   assert len(pts)>=v['frameCount'],(p,len(pts),v['frameCount'])
   aligned=min(len(ts),len(pts))
   for key in ['windowOpenFrame','firstContentFrame']+(['topContentFrame','switchContentFrame'] if suite=='chat' else ['referenceFrame']):assert v[key]<aligned
   error=max(abs(pts[n]-(ts[n]-ts[0])) for n in range(aligned));assert error<.1,(p,error)
   out['videos'].append({'suite':suite,'app':a['app'],'video':str(p),'frames':len(ts),'extraTrailingFrames':max(0,len(pts)-len(ts)),'unencodedTrailingCaptureFrames':max(0,len(ts)-len(pts)),'maxTimestampAlignmentErrorMs':error})
   print(suite,a['app'],p.name,'PASS',flush=True)
before=json.load(open(pathlib.Path(__file__).parent/'builds-before.json'));after=json.load(open(pathlib.Path(__file__).parent/'builds-after.json'))
assert before['bundles']==after['bundles'];out.update(observations=190,allSessionsUnlocked=True,bundlesUnchanged=True)
json.dump(out,open(pathlib.Path(__file__).parent/'validation.json','w'),indent=2)
