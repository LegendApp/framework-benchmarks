import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { labels, option, type AppName } from "./config";
import { detectContentExecutable, median, percentile } from "./macos";
import { writeGallery } from "./gallery";

// Retain the original observations: memory launches used the original timing
// boundary, so their numbers remain historical samples, not fresh measurements.
const reportPath = resolve(option("--results") ?? "");
if (!option("--results")) throw new Error("Pass --results <results.json>");
const root = dirname(reportPath);
const report = JSON.parse(readFileSync(reportPath, "utf8"));
if (report.reanalysis) throw new Error("This report was already reanalyzed");
const backup = reportPath.replace(/\.json$/, ".pixel-match-v1.json");
if (existsSync(backup)) throw new Error(`Backup already exists: ${backup}`);
copyFileSync(reportPath, backup);
copyFileSync(join(root, "results.md"), join(root, "results.pixel-match-v1.md"));
for (const app of report.results) {
  for (const sample of app.iterations) {
    const e = sample.videoEvidence;
    const startMs = e.videoLaunchOffsetMs + sample.windowOpenMs;
    const auditPath = join(root, "ocr-audit", e.video.replace(/\.mp4$/, ".ocr.json"));
    const frames: Array<{videoMs: number; text: string; matched: boolean; confidence: number}> = existsSync(auditPath)
      ? JSON.parse(readFileSync(auditPath, "utf8"))
      : JSON.parse(execFileSync(detectContentExecutable, [join(root, e.video), String(startMs), "0.35", "0.42", "0.3", "0.2"], {encoding: "utf8"}));
    let run = 0;
    let first: typeof frames[number] | undefined;
    for (let index = 0; index < frames.length; index++) {
      const f = frames[index];
      run = f.videoMs >= startMs && f.matched && f.confidence >= 0.8 ? run + 1 : 0;
      if (run === 3) { first = frames[index - 2]; break; }
    }
    if (!first) throw new Error(`No readable greeting: ${e.video}`);
    e.previousPixelMatch = { firstContentMs: sample.firstContentMs, firstContentFrame: e.firstContentFrame, firstContentTimestampMs: e.firstContentTimestampMs, match: e.match };
    sample.firstContentMs = first.videoMs - e.videoLaunchOffsetMs;
    e.firstContentTimestampMs = e.recordingStartedTimestampMs + first.videoMs;
    const timestamps = JSON.parse(readFileSync(join(root, e.captureTimestamps), "utf8")).frameTimestampsMs as number[];
    e.firstContentFrame = timestamps.reduce((best, t, index) => Math.abs(t - e.firstContentTimestampMs) < Math.abs(timestamps[best] - e.firstContentTimestampMs) ? index : best, 0);
    e.firstContentVideoMs = first.videoMs;
    e.analysisVersion = 2;
    e.match = {stableFrames: 3, contentMethod: "native-resolution Vision OCR", minimumConfidence: 0.8};
    e.ocrFrames = frames;
    const sidecar = join(root, e.video.replace(/\.mp4$/, ".frames.json"));
    copyFileSync(sidecar, sidecar.replace(/\.frames.json$/, ".pixel-match-v1.frames.json"));
    writeFileSync(sidecar, JSON.stringify(e, null, 2) + "\n");
  }
  app.median.firstContentMs = median(app.iterations.map((s: {firstContentMs: number}) => s.firstContentMs));
  app.p90.firstContentMs = percentile(app.iterations.map((s: {firstContentMs: number}) => s.firstContentMs), 0.9);
}
report.reanalysis = {at: new Date().toISOString(), source: "results.pixel-match-v1.json", method: "Three consecutive native-resolution OCR matches in saved cropped videos; video PTS mapped to saved recording start. Window timings unchanged. Re-encoding limits boundary precision to about one video frame.", memory: "Unchanged: memory was sampled 2.5 s after the original, overestimated timing boundary. No new memory launches were performed."};
report.methodology.startup = report.reanalysis.method;
report.methodology.memory += " Correction: " + report.reanalysis.memory;
writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
const mb = (n: number) => (n / 1048576).toFixed(1);
const pair = (a: number, b: number) => `${a.toFixed(1)} / ${b.toFixed(1)}`;
const lines = ["# Hello World framework baseline — corrected startup timing", "",
  `Original run: ${report.measuredAt}. ${report.machine.hardware}, macOS ${report.machine.os}. ${report.iterations} measured runs per runtime after ${report.warmups} warmups.`, "",
  "Corrected September 11 after reviewing the saved videos: the original pixel-match detector could reject readable text until later compression/appearance changes. Startup now uses three consecutive OCR-confirmed greeting frames at native resolution. These are fresh-process launches with warmed OS caches, not cold boots. Precision is approximately one 60 Hz video frame.", "",
  "| Runtime | Window p50 / p90 ms | Greeting p50 / p90 ms | Footprint MiB | Bundle MiB |", "| --- | ---: | ---: | ---: | ---: |",
  ...report.results.map((r: any) => `| ${labels[r.app as AppName]} | ${pair(r.median.windowOpenMs,r.p90.windowOpenMs)} | ${pair(r.median.firstContentMs,r.p90.firstContentMs)} | ${mb(r.median.physicalFootprintBytes)} | ${mb(r.buildSizeBytes)} |`), "",
  "Memory is unchanged from the original uncaptured launches. Samples began 2.5 seconds after the original detector’s content boundary, which was sometimes too late; these are settled footprints, not a newly measured fixed delay from the corrected boundary. App descendants and new WebKit helpers are included; WindowServer is excluded. Desktop background activity was present.", "",
  "[Video gallery](videos.html) · [All MP4s](videos.md) · [Corrected raw results](results.json) · [Original report](results.pixel-match-v1.md) · [Original observations](results.pixel-match-v1.json)", "",
  "All 100 measured videos were reanalyzed without rebuilding or relaunching apps. Original recordings and observations are retained. The gallery uses corrected timings. The chat product still uses whole-viewport matching, so its timing criterion is not identical to this greeting OCR criterion.", "",
];
writeFileSync(join(root, "results.md"), lines.join("\n"));
writeGallery(reportPath);
console.log(lines.join("\n"));
