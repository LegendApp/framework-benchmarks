import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { labels, option, type AppName } from "./config";

type GalleryReport = {
  measuredAt: string;
  warmups: number;
  iterations: number;
  results: Array<{
    app: AppName;
    median: { firstContentMs: number; physicalFootprintBytes: number };
    iterations: Array<{
      firstContentMs: number;
      videoEvidence: { video: string; videoLaunchOffsetMs: number };
    }>;
  }>;
};

export function writeGallery(reportPath: string, outputDirectory = dirname(reportPath)) {
  const report = JSON.parse(readFileSync(reportPath, "utf8")) as GalleryReport;
  const apps = report.results.map((result) => {
    const samples = result.iterations.map((iteration, index) => {
      if (!Number.isFinite(iteration.videoEvidence.videoLaunchOffsetMs)) {
        throw new Error("This run predates saved launch offsets; use a new benchmark run for aligned playback.");
      }
      return {
        number: index + 1,
        video: relative(outputDirectory, resolve(dirname(reportPath), iteration.videoEvidence.video)),
        offset: Math.max(0, iteration.videoEvidence.videoLaunchOffsetMs / 1000),
        contentMs: iteration.firstContentMs,
      };
    });
    const selected = samples.reduce((best, sample, index) =>
      Math.abs(sample.contentMs - result.median.firstContentMs) < Math.abs(samples[best].contentMs - result.median.firstContentMs) ? index : best, 0);
    return {
      name: labels[result.app], samples, selected,
      contentMs: result.median.firstContentMs,
      memoryMiB: result.median.physicalFootprintBytes / 1048576,
    };
  });
  const data = JSON.stringify(apps).replaceAll("<", "\\u003c");
  const output = join(outputDirectory, "videos.html");
  writeFileSync(output, `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hello World startup videos</title>
<style>
:root{font-family:system-ui,sans-serif;color:#18212b;background:#f4f6f8;color-scheme:light}
body{max-width:1500px;margin:36px auto;padding:0 24px}h1{font-size:30px;margin-bottom:10px}
p{line-height:1.5;color:#475569}button,select{font:inherit;border:1px solid #cbd5e1;background:white;border-radius:7px;padding:9px 12px;cursor:pointer}
button:first-child{background:#155eef;color:white;border-color:#155eef}nav{display:flex;gap:10px;flex-wrap:wrap;margin:24px 0}
#grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:20px}
article{background:white;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}article header,article footer{padding:16px}h2{font-size:18px;margin:0 0 8px}.metrics{font-variant-numeric:tabular-nums;font-size:14px;color:#475569}
video{width:100%;display:block;background:#111;aspect-ratio:16/9}footer{display:flex;gap:12px;align-items:center;flex-wrap:wrap}a{color:#155eef}small{display:block;color:#64748b;margin-top:6px}@media(max-width:420px){#grid{grid-template-columns:1fr}}
</style></head><body>
<h1>Hello World startup videos</h1>
<p>${report.iterations} measured recordings per app, after ${report.warmups} discarded warmups. Run completed ${report.measuredAt}.</p>
<p>Each app initially selects the recording closest to its median first-content time. Playback starts at the launch request using the saved capture timestamps. Choose any measured iteration below. The numeric report is authoritative; browser playback synchronization is approximate.</p>
<nav><button id="play">Play all from launch</button><button id="pause">Pause all</button><button id="reset">Reset to launch</button><a href="${relative(outputDirectory, join(dirname(reportPath), "results.md"))}">Summary</a><a href="${relative(outputDirectory, reportPath)}">Raw results</a><a href="videos.md">All recording links</a></nav>
<div id="grid"></div>
<script>
const apps=${data};
const players=[];
for(const app of apps){
 const card=document.createElement('article');
 const header=document.createElement('header');
 const title=document.createElement('h2');title.textContent=app.name;
 const metrics=document.createElement('div');metrics.className='metrics';metrics.textContent='Median: '+app.contentMs.toFixed(1)+' ms to content · '+app.memoryMiB.toFixed(1)+' MiB footprint';
 header.append(title,metrics);
 const video=document.createElement('video');video.controls=true;video.preload='metadata';video.muted=true;video.playsInline=true;
 const footer=document.createElement('footer');const select=document.createElement('select');select.setAttribute('aria-label',app.name+' recording');
 app.samples.forEach((sample,index)=>{const option=document.createElement('option');option.value=index;option.textContent='Run '+sample.number+' · '+sample.contentMs.toFixed(1)+' ms';select.append(option)});
 select.value=app.selected;
 const link=document.createElement('a');link.textContent='Open MP4';
 const player={video,app,select};players.push(player);
 const load=()=>{video.pause();const sample=app.samples[Number(select.value)];video.src=sample.video;link.href=sample.video;video.addEventListener('loadedmetadata',()=>{video.currentTime=sample.offset},{once:true})};
 select.addEventListener('change',load);load();footer.append(select,link);card.append(header,video,footer);document.getElementById('grid').append(card);
}
function reset(player){player.video.pause();player.video.currentTime=player.app.samples[Number(player.select.value)].offset}
document.getElementById('play').onclick=()=>{for(const player of players){reset(player);player.video.play().catch(()=>{})}};
document.getElementById('pause').onclick=()=>players.forEach(player=>player.video.pause());
document.getElementById('reset').onclick=()=>players.forEach(reset);
</script></body></html>`);
  const lines = ["# Hello World recordings", "", `Run: ${report.measuredAt}. ${report.iterations} measured recordings per app.`, "", "Open [the video gallery](videos.html) for launch-aligned playback and iteration selection.", ""];
  for (const app of apps) {
    lines.push(`## ${app.name}`, "");
    for (const sample of app.samples) {
      lines.push(`- [Run ${sample.number}](${sample.video}) — ${sample.contentMs.toFixed(1)} ms to content${sample === app.samples[app.selected] ? " (closest to median)" : ""}`);
    }
    lines.push("");
  }
  writeFileSync(join(outputDirectory, "videos.md"), lines.join("\n"));
  return output;
}

if (import.meta.main) {
  const path = option("--results");
  if (!path) throw new Error("Usage: bun HelloWorld/benchmark/gallery.ts --results <results.json>");
  console.log(writeGallery(resolve(path)));
}
