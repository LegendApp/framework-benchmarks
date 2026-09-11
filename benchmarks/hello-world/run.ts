import { execFileSync, spawn } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { startRecording, stopRecording, targetRecording } from "../chat-history/video";
import { buildRoot, bundlePath, integerOption, labels, repositoryRoot, selectedApps, type AppName } from "./config";
import { buildHelpers, bundleSize, captureExecutable, launchExecutable, median, percentile, settledMemory, stopApp, waitForWindow, webKitPids, type Memory } from "./macos";
import { analyzeHelloWorld } from "./video";
import { writeGallery } from "./gallery";

const apps = selectedApps();
const iterations = integerOption("--iterations", 10, 1);
const warmups = integerOption("--warmups", 2, 0);
const settleMs = integerOption("--settle-ms", 5000, 1000);
if (process.argv.includes("--no-video")) throw new Error("Hello World requires video and OCR to validate visible content; --no-video is not supported.");
const manifestPath = join(buildRoot, "build-manifest.json");
if (!existsSync(manifestPath)) throw new Error("Build the Hello World apps first: bun run benchmark:hello-world:build");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
for (const app of apps) {
  if (!existsSync(bundlePath(app)) || !manifest.builds[app]) throw new Error(`Missing ${app} production build; run bun run benchmark:hello-world:build --app ${app}`);
}

// Scoped to this runner: wake the display and keep it awake through all recordings.
const displayAssertion = spawn("/usr/bin/caffeinate", ["-du", "-w", String(process.pid)], { stdio: "ignore" });
displayAssertion.unref();
process.once("exit", () => displayAssertion.kill());
buildHelpers();
await Bun.sleep(1000);
const stamp = new Date().toISOString().replaceAll(":", "-");
const resultsRoot = resolve(import.meta.dir, "results", stamp);
mkdirSync(resultsRoot, { recursive: true });

type Observation = {
  windowOpenMs: number;
  firstContentMs: number;
  memory: Memory;
  videoEvidence: Awaited<ReturnType<typeof analyzeHelloWorld>>;
};

function launch(app: AppName) {
  // Never pass transcript configuration or app-specific readiness hooks to a baseline.
  const env = { ...process.env };
  delete env.CHAT_HISTORY_BENCHMARK_CONFIG;
  delete env.CHAT_HISTORY_BENCHMARK_EVENTS;
  return JSON.parse(execFileSync(launchExecutable, [bundlePath(app), "-ApplePersistenceIgnoreState", "YES"], {
    cwd: repositoryRoot, encoding: "utf8", env,
  })) as { pid: number; launchStartedTimestampMs: number };
}

async function observe(app: AppName, name: string): Promise<Observation> {
  const temp = mkdtempSync(join(tmpdir(), `hello-world-${app}-`));
  let pid: number | undefined;
  let recording: Awaited<ReturnType<typeof startRecording>> | undefined;
  try {
    const recordingPath = join(temp, "screen.mp4");
    recording = await startRecording(recordingPath, captureExecutable);
    await Bun.sleep(150);
    const timing = launch(app);
    pid = timing.pid;
    await targetRecording(recording, pid);
    await waitForWindow(pid);
    await Bun.sleep(settleMs);
    process.kill(pid, 0);
    // Opening animations can report an intermediate window size; analyze the final bounds.
    const window = await waitForWindow(pid);
    await stopRecording(recording);
    const timestampPath = recording.timestampPath;
    recording = undefined;
    await stopApp(pid);
    pid = undefined;
    const evidence = await analyzeHelloWorld({
      recordingPath, timestampPath, artifactPath: join(resultsRoot, `${name}.mp4`), resultsRoot,
      launchTimestampMs: timing.launchStartedTimestampMs, window,
    });
    const firstContentMs = evidence.firstContentTimestampMs - timing.launchStartedTimestampMs;
    const baseline = app === "tauri" || app === "deno-webview" ? webKitPids() : undefined;
    const memoryLaunch = launch(app);
    pid = memoryLaunch.pid;
    await waitForWindow(pid);
    // Use the observed visual boundary, then the same 2.5 s / 3 x 200 ms policy as the product suite.
    await Bun.sleep(Math.max(0, memoryLaunch.launchStartedTimestampMs + firstContentMs - Date.now()));
    const memory = await settledMemory(pid, baseline);
    return {
      windowOpenMs: evidence.windowOpenTimestampMs - timing.launchStartedTimestampMs,
      firstContentMs, memory, videoEvidence: evidence,
    };
  } finally {
    if (recording) await stopRecording(recording).catch(() => undefined);
    if (pid !== undefined) await stopApp(pid);
    rmSync(temp, { recursive: true, force: true });
  }
}

async function withRetries(app: AppName, name: string) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try { return await observe(app, `${name}-attempt-${attempt}`); }
    catch (error) {
      console.error(`${app}: discarded attempt ${attempt}: ${error}`);
      if (attempt === 3) throw error;
    }
  }
  throw new Error("Unreachable");
}

const measured = new Map(apps.map((app) => [app, [] as Observation[]]));
for (let round = 0; round < warmups + iterations; round++) {
  const isWarmup = round < warmups;
  const order = apps.map((_, index) => apps[(round + index) % apps.length]);
  for (const app of order) {
    const name = `${app}-${isWarmup ? "warmup" : "measured"}-${isWarmup ? round + 1 : round - warmups + 1}`;
    console.log(name);
    const observation = await withRetries(app, name);
    appendFileSync(join(resultsRoot, "observations.jsonl"), JSON.stringify({ app, name, warmup: isWarmup, round, observation }) + "\n");
    if (!isWarmup) measured.get(app)!.push(observation);
  }
}

const results = apps.map((app) => {
  const observations = measured.get(app)!;
  const aggregate = (reduce: (v: number[]) => number) => ({
    windowOpenMs: reduce(observations.map((o) => o.windowOpenMs)),
    firstContentMs: reduce(observations.map((o) => o.firstContentMs)),
    physicalFootprintBytes: reduce(observations.map((o) => o.memory.physicalFootprintBytes)),
    residentSetBytes: reduce(observations.map((o) => o.memory.residentSetBytes)),
    processCount: reduce(observations.map((o) => o.memory.processCount)),
  });
  return { app, buildSizeBytes: bundleSize(bundlePath(app)), iterations: observations, median: aggregate(median), p90: aggregate((v) => percentile(v, 0.9)) };
});
const report = {
  version: 1, workload: "hello-world", measuredAt: new Date().toISOString(),
  machine: { platform: process.platform, arch: process.arch, os: execFileSync("sw_vers", ["-productVersion"], { encoding: "utf8" }).trim(), hardware: execFileSync("sysctl", ["-n", "machdep.cpu.brand_string"], { encoding: "utf8" }).trim() },
  warmups, iterations, settleMs, builds: manifest,
  methodology: {
    content: 'Centered "Hello, world!", 32-point text, white background, 1280×720 content window. React web hosts include React/ReactDOM; no chat dependencies.',
    startup: "LaunchServices launch to first of three consecutive frames with the greeting recognized by native-resolution Vision OCR. Window opening still uses three stable changed frames.",
    memory: "Separate non-recording launch, wait for timing launch's observed content boundary, then median of 3 physical-footprint samples starting 2500 ms later, 200 ms apart. RSS is diagnostic.",
    webkit: "New WebKit XPC processes relative to each launch baseline are included. Keep other WebKit activity idle during a run.",
    size: "Logical production .app bytes, excluding symlinks. System frameworks are not bundled.",
    order: "Discard warmups, rotate runtime order deterministically each round; incomplete or invalid launches retried at most twice.",
    comparison: "Compare Hello World startup, settled footprint, and bundle size with product initial-content metrics from the same machine/build conditions. Parsing/jump/switch metrics do not apply to Hello World.",
  }, results,
};
writeFileSync(join(resultsRoot, "results.json"), JSON.stringify(report, null, 2) + "\n");
const mb = (v: number) => (v / 1048576).toFixed(1);
const pair = (a: number, b: number) => `${a.toFixed(1)} / ${b.toFixed(1)}`;
const markdown = [
  "# Hello World framework baseline", "",
  `${iterations} measured iterations per runtime; ${warmups} discarded warmups. Timing is p50 / p90 in ms; footprint is from a separate launch without recording.`, "",
  "| Runtime | Window ms | Hello World ms | Footprint MiB | Bundle MiB |",
  "| --- | ---: | ---: | ---: | ---: |",
  ...results.map((r) => `| ${labels[r.app]} | ${pair(r.median.windowOpenMs, r.p90.windowOpenMs)} | ${pair(r.median.firstContentMs, r.p90.firstContentMs)} | ${mb(r.median.physicalFootprintBytes)} | ${mb(r.buildSizeBytes)} |`), "",
  "Hello World and the full chat product are distinct workloads. No transcript fixtures, parsing, chat switching, or list work runs in these apps. These are explicit minimal apps, not untouched generator templates.", "",
  "Raw observations, build provenance, OCR text, cropped videos, text images, and frame timestamps accompany this report. RSS is retained only in JSON as a diagnostic.", "",
];
writeFileSync(join(resultsRoot, "results.md"), markdown.join("\n"));
console.log(markdown.join("\n"));
console.log(`Video gallery: ${writeGallery(join(resultsRoot, "results.json"))}`);
console.log(`Results: ${resultsRoot}`);
