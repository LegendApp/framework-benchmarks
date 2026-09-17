import pathlib,json,subprocess
from PIL import Image,ImageDraw
root=pathlib.Path(__file__).resolve().parents[2];out=pathlib.Path(__file__).parent/'visual';out.mkdir(exist_ok=True)
cpath=root/'benchmarks/chat-history/results/2026-09-16T20-35-45.623Z.json';hpath=root/'benchmarks/hello-world/results/2026-09-16T21-25-32.060Z/results.json'
c=json.load(open(cpath));h=json.load(open(hpath))
for phase,key in [('initial','firstContentTimestampMs'),('top','topContentTimestampMs'),('switch','switchContentTimestampMs'),('hello','firstContentTimestampMs')]:
 apps=h['results'] if phase=='hello' else c['apps'];sheet=Image.new('RGB',(1920,390*((len(apps)+2)//3)),'#333333');draw=ImageDraw.Draw(sheet)
 for n,a in enumerate(apps):
  v=a['iterations'][0]['videoEvidence'];base=hpath.parent if phase=='hello' else cpath.parent
  start=v['recordingStartedTimestampMs'] if phase=='hello' else v['sourceFrameTimestampsMs'][0]
  offset=(v[key]-start)/1000+.5;p=out/f'{phase}-{a["app"]}.png'
  subprocess.run(['ffmpeg','-v','error','-y','-ss',str(offset),'-i',str(base/v['video']),'-frames:v','1',str(p)],check=True)
  im=Image.open(p);im.thumbnail((640,360));x=(n%3)*640;y=(n//3)*390;sheet.paste(im,(x,y+30));draw.text((x+8,y+8),a['app'],fill='white')
 sheet.save(out/f'{phase}-contact.png')
print(out)
