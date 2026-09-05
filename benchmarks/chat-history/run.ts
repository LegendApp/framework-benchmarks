import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  createReadStream,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import type {
  BenchmarkConfig,
  BenchmarkContentReadyEvent,
  BenchmarkFixtureManifest,
} from "../../apps/chat-history-electron/src/model";
import {
  analyzeRecording,
  startRecording,
  stopRecording,
  targetRecording,
  type VideoEvidence,
  type WindowInfo,
} from "./video";

type AppName =
  | "appkit"
  | "deno-cef"
  | "deno-webview"
  | "electron"
  | "flutter"
  | "gpui"
  | "react-native"
  | "swiftui"
  | "tauri";
type WindowShownEvent = { name: "windowShown"; timestampMs: number };
type DiagnosticEvent = {
  elapsedMs: number;
  event: string;
  payload?: Record<string, unknown>;
  sequence: number;
};
type LoggedContentReadyEvent = Omit<BenchmarkContentReadyEvent, "contentDigest"> & {
  contentDigest?: string;
  diagnostics?: DiagnosticEvent[];
  timestampMs: number;
};
type LoggedContentDigestEvent = {
  contentDigest: string;
  name: "contentDigest";
  path: string;
  phase: "initial" | "switch";
  timestampMs: number;
};
type LoggedEvent = LoggedContentDigestEvent | LoggedContentReadyEvent | WindowShownEvent;
type MemorySample = {
  physicalFootprintBytes: number;
  processCount: number;
  residentSetBytes: number;
};
type ProcessRow = { command: string; pid: number; ppid: number; rssKb: number };
type IterationResult = {
  diagnostics?: {
    initial?: DiagnosticEvent[];
    switch?: DiagnosticEvent[];
  };
  discoveryMs: number;
  firstContentMs: number;
  internalFirstContentMs: number;
  internalSwitchContentMs: number;
  internalWindowOpenMs: number;
  initialContentDurationMs: number;
  initialContentDigest: string;
  initialMemory: MemorySample;
  initialStages: BenchmarkContentReadyEvent["timing"];
  switchContentMs: number;
  switchContentDigest: string;
  switchStages: BenchmarkContentReadyEvent["timing"];
  switchedMemory: MemorySample;
  videoEvidence?: VideoEvidence;
  windowOpenMs: number;
};
type AppResult = {
  app: AppName;
  buildSizeBytes: number;
  executable: string;
  iterations: IterationResult[];
  median: IterationResult;
  p90: IterationResult;
};

const repositoryRoot = resolve(import.meta.dir, "../..");
const buildRoot = resolve(repositoryRoot, ".build/chat-history-benchmarks");
const manifestPath = resolve(import.meta.dir, "fixtures.local.json");
const resultsRoot = resolve(import.meta.dir, "results");
const windowInfoExecutable = resolve(buildRoot, "chat-history-window-info");
const windowInfoSource = resolve(import.meta.dir, "window-info.swift");
const launchAppExecutable = resolve(buildRoot, "chat-history-launch-app");
const launchAppSource = resolve(import.meta.dir, "launch-app.swift");
const captureApp = resolve(buildRoot, "Chat History Benchmark Capture.app");
const captureExecutable = resolve(captureApp, "Contents/MacOS/ChatHistoryCapture");
const captureInfo = resolve(import.meta.dir, "CaptureInfo.plist");
const captureSource = resolve(import.meta.dir, "capture-screen.swift");
const recordVideo = !process.argv.includes("--no-video");
const apps: Record<AppName, { bundle: string; executable: string }> = {
  appkit: {
    bundle: resolve(buildRoot, "Chat History — AppKit.app"),
    executable: resolve(buildRoot, "Chat History — AppKit.app/Contents/MacOS/ChatHistoryAppKit"),
  },
  "deno-cef": {
    bundle: resolve(buildRoot, "Chat History — Deno CEF.app"),
    executable: resolve(buildRoot, "Chat History — Deno CEF.app/Contents/MacOS/laufey"),
  },
  "deno-webview": {
    bundle: resolve(buildRoot, "Chat History — Deno WebView.app"),
    executable: resolve(buildRoot, "Chat History — Deno WebView.app/Contents/MacOS/laufey_webview"),
  },
  electron: {
    bundle: resolve(buildRoot, "Chat History — Electron.app"),
    executable: resolve(buildRoot, "Chat History — Electron.app/Contents/MacOS/Electron"),
  },
  flutter: {
    bundle: resolve(buildRoot, "Chat History — Flutter.app"),
    executable: resolve(
      buildRoot,
      "Chat History — Flutter.app/Contents/MacOS/Chat History - Flutter",
    ),
  },
  gpui: {
    bundle: resolve(buildRoot, "Chat History — GPUI.app"),
    executable: resolve(
      buildRoot,
      "Chat History — GPUI.app/Contents/MacOS/legend-chat-history-gpui",
    ),
  },
  "react-native": {
    bundle: resolve(buildRoot, "Chat History — React Native.app"),
    executable: resolve(buildRoot, "Chat History — React Native.app/Contents/MacOS/Legend Chat History"),
  },
  swiftui: {
    bundle: resolve(buildRoot, "Chat History — SwiftUI.app"),
    executable: resolve(buildRoot, "Chat History — SwiftUI.app/Contents/MacOS/ChatHistorySwiftUI"),
  },
  tauri: {
    bundle: resolve(buildRoot, "Chat History — Tauri.app"),
    executable: resolve(buildRoot, "Chat History — Tauri.app/Contents/MacOS/legend-chat-history-tauri"),
  },
};

function option(name: string) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function selectedApps(): AppName[] {
  const value = option("--app") ?? "all";
  if (value === "deno") {
    return ["deno-webview", "deno-cef"];
  }
  if (value === "all") {
    return [
      "react-native",
      "electron",
      "tauri",
      "deno-webview",
      "deno-cef",
      "flutter",
      "gpui",
      "swiftui",
      "appkit",
    ];
  }
  if (value in apps) {
    return [value as AppName];
  }
  throw new Error(`Unknown app ${value}`);
}

async function sha256(path: string) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

async function verifyFixtures(config: BenchmarkFixtureManifest) {
  for (const fixture of config.fixtures) {
    if (statSync(fixture.path).size !== fixture.sourceBytes) {
      throw new Error(`Fixture size changed: ${fixture.path}`);
    }
    if (await sha256(fixture.path) !== fixture.sha256) {
      throw new Error(`Fixture hash changed: ${fixture.path}`);
    }
  }
}

function bundleSize(path: string): number {
  const stats = lstatSync(path);
  if (stats.isSymbolicLink()) {
    return 0;
  }
  if (!stats.isDirectory()) {
    return stats.size;
  }
  return readdirSync(path).reduce((total, entry) => total + bundleSize(join(path, entry)), 0);
}

function processTable() {
  const output = execFileSync("ps", ["-axo", "pid=,ppid=,rss=,command="], { encoding: "utf8" });
  return output.trim().split("\n").flatMap((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.+)$/);
    return match ? [{ command: match[4], pid: Number(match[1]), ppid: Number(match[2]), rssKb: Number(match[3]) }] : [];
  });
}

function isWebKitHelper(row: ProcessRow) {
  return /\/com\.apple\.WebKit\.(?:GPU|Networking|WebContent)(?:\.xpc)?\//.test(row.command);
}

function processTree(rootPid: number, webKitBaseline?: Set<number>) {
  const rows = processTable();
  const pids = new Set([rootPid]);
  if (webKitBaseline) {
    for (const row of rows) {
      if (isWebKitHelper(row) && !webKitBaseline.has(row.pid)) {
        pids.add(row.pid);
      }
    }
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const row of rows) {
      if (pids.has(row.ppid) && !pids.has(row.pid)) {
        pids.add(row.pid);
        changed = true;
      }
    }
  }
  return { pids, rows };
}

function physicalFootprint(pids: Set<number>) {
  try {
    const output = execFileSync(
      "/usr/bin/footprint",
      [...pids].flatMap((pid) => ["-p", String(pid)]).concat(["-f", "bytes", "--noCategories"]),
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    );
    const summary = output.match(/Summary Footprint:\s+(\d+) B/);
    if (summary) {
      return Number(summary[1]);
    }
    return [...output.matchAll(/phys_footprint:\s+(\d+) B/g)]
      .reduce((total, match) => total + Number(match[1]), 0);
  } catch {
    return 0;
  }
}

function memoryForProcessTree(rootPid: number, webKitBaseline?: Set<number>): MemorySample {
  const { pids, rows } = processTree(rootPid, webKitBaseline);
  return {
    physicalFootprintBytes: physicalFootprint(pids),
    processCount: pids.size,
    residentSetBytes: rows
      .filter((row) => pids.has(row.pid))
      .reduce((total, row) => total + row.rssKb * 1_024, 0),
  };
}

async function stabilizedMemory(rootPid: number, webKitBaseline?: Set<number>) {
  await Bun.sleep(300);
  const samples: MemorySample[] = [];
  for (let index = 0; index < 3; index += 1) {
    samples.push(memoryForProcessTree(rootPid, webKitBaseline));
    if (index < 2) {
      await Bun.sleep(100);
    }
  }
  return {
    physicalFootprintBytes: median(samples.map((sample) => sample.physicalFootprintBytes)),
    processCount: median(samples.map((sample) => sample.processCount)),
    residentSetBytes: median(samples.map((sample) => sample.residentSetBytes)),
  };
}

function loggedEvents(path: string): LoggedEvent[] {
  if (!existsSync(path)) {
    return [];
  }
  const source = readFileSync(path, "utf8").trim();
  if (source.startsWith("[")) {
    try {
      return JSON.parse(source) as LoggedEvent[];
    } catch {
      return [];
    }
  }
  return source.split("\n").flatMap((line) => {
    if (!line) {
      return [];
    }
    try {
      return [JSON.parse(line) as LoggedEvent];
    } catch {
      return [];
    }
  });
}

async function waitForEvent(
  path: string,
  predicate: (event: LoggedEvent) => boolean,
  timeoutMs = 120_000,
) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const event = loggedEvents(path).find(predicate);
    if (event) {
      return event;
    }
    await Bun.sleep(20);
  }
  throw new Error(`Timed out waiting for benchmark event in ${path}`);
}

function processExists(pid: number) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function stopProcess(pid: number) {
  if (!processExists(pid)) {
    return;
  }
  process.kill(pid, "SIGTERM");
  for (let waitedMs = 0; waitedMs < 5_000 && processExists(pid); waitedMs += 25) {
    await Bun.sleep(25);
  }
  if (processExists(pid)) {
    process.kill(pid, "SIGKILL");
  }
}

async function waitForWindowInfo(rootPid: number, timeoutMs = 5_000): Promise<WindowInfo> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const pids = [...processTree(rootPid).pids].map(String);
    try {
      const output = execFileSync(windowInfoExecutable, pids, {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      return JSON.parse(output) as WindowInfo;
    } catch {
      await Bun.sleep(20);
    }
  }
  throw new Error(`Timed out waiting for an on-screen window owned by process ${rootPid}`);
}

async function runIteration(
  app: AppName,
  config: BenchmarkConfig,
  videoArtifactPath?: string,
): Promise<IterationResult> {
  const definition = apps[app];
  const temporaryDirectory = mkdtempSync(join(tmpdir(), `chat-history-${app}-`));
  const recordingPath = join(temporaryDirectory, "screen.mp4");
  const runtimeManifestPath = join(temporaryDirectory, "manifest.json");
  const eventFileName = `${basename(temporaryDirectory)}.json`;
  const eventsPath = app === "react-native"
    ? join(homedir(), "Library/Application Support/Legend Chat History/chat-history-benchmark", eventFileName)
    : join(temporaryDirectory, "events.jsonl");
  const launchArguments = [
    "-ApplePersistenceIgnoreState",
    "YES",
    ...(app === "react-native"
      ? [`--chat-history-benchmark=${encodeURIComponent(JSON.stringify({ ...config, eventFileName }))}`]
      : []),
  ];
  rmSync(eventsPath, { force: true });
  writeFileSync(runtimeManifestPath, `${JSON.stringify(config)}\n`);
  const webKitBaseline = app === "tauri" || app === "deno-webview"
    ? new Set(processTable().filter(isWebKitHelper).map((row) => row.pid))
    : undefined;
  let recording: Awaited<ReturnType<typeof startRecording>> | undefined;
  let appPid: number | undefined;
  let recordingStopped = false;
  try {
    recording = recordVideo ? await startRecording(recordingPath, captureExecutable) : undefined;
    if (recording) {
      await Bun.sleep(150);
    }
    const launch = JSON.parse(execFileSync(
      launchAppExecutable,
      [definition.bundle, ...launchArguments],
      {
        cwd: repositoryRoot,
        encoding: "utf8",
        env: {
          ...process.env,
          CHAT_HISTORY_BENCHMARK_CONFIG: runtimeManifestPath,
          CHAT_HISTORY_BENCHMARK_EVENTS: eventsPath,
        },
      },
    )) as { launchStartedTimestampMs: number; pid: number };
    appPid = launch.pid;
    const launchedAt = launch.launchStartedTimestampMs;
    if (recording) {
      await targetRecording(recording, appPid);
    }
    const windowEvent = await waitForEvent(
      eventsPath, (event) => event.name === "windowShown") as WindowShownEvent;
    const capturedWindow = recording ? await waitForWindowInfo(appPid) : undefined;
    const initialEvent = await waitForEvent(
      eventsPath,
      (event) => event.name === "contentReady" && event.phase === "initial",
    ) as LoggedContentReadyEvent;
    if (!initialEvent.timing) {
      throw new Error(`${app} did not report benchmark stage timings; rebuild production apps`);
    }
    if (typeof initialEvent.discoveryMs !== "number" || !Number.isFinite(initialEvent.discoveryMs)) {
      throw new Error(`${app} did not report measured chat discovery time; rebuild production apps`);
    }
    const initialContentDigest = initialEvent.contentDigest ?? (
      await waitForEvent(
        eventsPath,
        (event) => event.name === "contentDigest" && event.phase === "initial",
      ) as LoggedContentDigestEvent
    ).contentDigest;
    const initialMemory = await stabilizedMemory(appPid, webKitBaseline);
    const switchEvent = await waitForEvent(
      eventsPath,
      (event) => event.name === "contentReady" && event.phase === "switch",
    ) as LoggedContentReadyEvent;
    if (!switchEvent.timing) {
      throw new Error(`${app} did not report switched benchmark stage timings; rebuild production apps`);
    }
    const switchContentDigest = switchEvent.contentDigest ?? (
      await waitForEvent(
        eventsPath,
        (event) => event.name === "contentDigest" && event.phase === "switch",
      ) as LoggedContentDigestEvent
    ).contentDigest;
    const switchedMemory = await stabilizedMemory(appPid, webKitBaseline);
    if (recording) {
      // Keep recording after app readiness so self-sizing native lists can reach their final frame.
      await Bun.sleep(750);
      await stopRecording(recording);
      recordingStopped = true;
    }
    const internalFirstContentMs = initialEvent.timestampMs - launchedAt;
    const internalSwitchContentMs = switchEvent.durationMs;
    const internalWindowOpenMs = windowEvent.timestampMs - launchedAt;
    const switchStartedTimestampMs = switchEvent.timestampMs - switchEvent.durationMs;
    const videoEvidence = recording && videoArtifactPath && capturedWindow
      ? await analyzeRecording({
        artifactPath: videoArtifactPath,
        firstContentTimestampMs: initialEvent.timestampMs,
        launchTimestampMs: launchedAt,
        recordingPath,
        recordingTimestampPath: recording.timestampPath,
        resultsRoot,
        switchContentTimestampMs: switchEvent.timestampMs,
        switchStartedTimestampMs,
        windowInfo: capturedWindow,
        windowShownTimestampMs: windowEvent.timestampMs,
      })
      : undefined;
    return {
      diagnostics: {
        initial: initialEvent.diagnostics,
        switch: switchEvent.diagnostics,
      },
      discoveryMs: initialEvent.discoveryMs,
      firstContentMs: videoEvidence
        ? videoEvidence.firstContentTimestampMs - launchedAt
        : internalFirstContentMs,
      internalFirstContentMs,
      internalSwitchContentMs,
      internalWindowOpenMs,
      initialContentDurationMs: initialEvent.durationMs,
      initialContentDigest,
      initialMemory,
      initialStages: initialEvent.timing,
      switchContentMs: videoEvidence
        ? videoEvidence.switchContentTimestampMs - switchStartedTimestampMs
        : internalSwitchContentMs,
      switchContentDigest,
      switchStages: switchEvent.timing,
      switchedMemory,
      videoEvidence,
      windowOpenMs: videoEvidence
        ? videoEvidence.windowOpenTimestampMs - launchedAt
        : internalWindowOpenMs,
    };
  } finally {
    if (recording && !recordingStopped) {
      await stopRecording(recording).catch(() => undefined);
    }
    if (appPid) {
      await stopProcess(appPid);
    }
    rmSync(eventsPath, { force: true });
    rmSync(temporaryDirectory, { force: true, recursive: true });
  }
}

function median(values: number[]) {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

function percentile(values: number[], quantile: number) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * quantile) - 1)];
}

function aggregateResult(
  iterations: IterationResult[],
  aggregate: (values: number[]) => number,
): IterationResult {
  const stage = (key: "initialStages" | "switchStages") => ({
    documentMs: aggregate(iterations.map((result) => result[key].documentMs ?? 0)),
    loadMs: aggregate(iterations.map((result) => result[key].loadMs)),
    nativeTotalMs: aggregate(iterations.map((result) => result[key].nativeTotalMs)),
    parseMs: aggregate(iterations.map((result) => result[key].parseMs)),
    scanMs: aggregate(iterations.map((result) => result[key].scanMs)),
  });
  const memory = (key: "initialMemory" | "switchedMemory") => ({
    physicalFootprintBytes: aggregate(
      iterations.map((result) => result[key].physicalFootprintBytes)),
    processCount: aggregate(iterations.map((result) => result[key].processCount)),
    residentSetBytes: aggregate(iterations.map((result) => result[key].residentSetBytes)),
  });
  return {
    discoveryMs: aggregate(iterations.map((result) => result.discoveryMs)),
    firstContentMs: aggregate(iterations.map((result) => result.firstContentMs)),
    internalFirstContentMs: aggregate(
      iterations.map((result) => result.internalFirstContentMs)),
    internalSwitchContentMs: aggregate(
      iterations.map((result) => result.internalSwitchContentMs)),
    internalWindowOpenMs: aggregate(
      iterations.map((result) => result.internalWindowOpenMs)),
    initialContentDurationMs: aggregate(
      iterations.map((result) => result.initialContentDurationMs)),
    initialContentDigest: iterations[0].initialContentDigest,
    initialMemory: memory("initialMemory"),
    initialStages: stage("initialStages"),
    switchContentMs: aggregate(iterations.map((result) => result.switchContentMs)),
    switchContentDigest: iterations[0].switchContentDigest,
    switchStages: stage("switchStages"),
    switchedMemory: memory("switchedMemory"),
    windowOpenMs: aggregate(iterations.map((result) => result.windowOpenMs)),
  };
}

function command(command: string, args: string[] = []) {
  try {
    return execFileSync(command, args, { encoding: "utf8" }).trim();
  } catch {
    return "unknown";
  }
}

function needsBuild(output: string, inputs: string[]) {
  if (!existsSync(output)) {
    return true;
  }
  const outputTime = statSync(output).mtimeMs;
  return inputs.some((input) => statSync(input).mtimeMs > outputTime);
}

function buildBenchmarkHelpers() {
  mkdirSync(buildRoot, { recursive: true });
  if (needsBuild(windowInfoExecutable, [windowInfoSource])) {
    execFileSync("swiftc", ["-O", windowInfoSource, "-o", windowInfoExecutable]);
  }
  if (needsBuild(launchAppExecutable, [launchAppSource])) {
    execFileSync("swiftc", [
      "-O", "-framework", "AppKit", launchAppSource, "-o", launchAppExecutable,
    ]);
  }
  if (recordVideo && needsBuild(captureExecutable, [captureSource, captureInfo])) {
    mkdirSync(resolve(captureApp, "Contents/MacOS"), { recursive: true });
    copyFileSync(captureInfo, resolve(captureApp, "Contents/Info.plist"));
    execFileSync("swiftc", [
      "-O",
      "-framework", "ScreenCaptureKit",
      "-framework", "AVFoundation",
      "-framework", "CoreMedia",
      "-framework", "CoreGraphics",
      captureSource,
      "-o", captureExecutable,
    ]);
    execFileSync("codesign", [
      "--force", "--sign", "-", "--identifier",
      "so.legend.chat-history-benchmark-capture", captureApp,
    ]);
  }
}

function formatMegabytes(bytes: number) {
  return `${(bytes / 1_048_576).toFixed(1)} MB`;
}

function formatMillisecondsPair(p50: number | null, p90: number | null) {
  return p50 === null || p90 === null
    ? "n/a"
    : `${p50.toFixed(1)} / ${p90.toFixed(1)} ms`;
}

function markdown(results: AppResult[]) {
  const lines = [
    recordVideo
      ? "Video-derived p50 / p90 for time columns; memory columns are p50 RSS / physical footprint."
      : "Internal-event p50 / p90 for time columns; memory columns are p50 RSS / physical footprint.",
    "",
    "| App | Window open | Discovery | First content total | Switch content | Initial memory | Switched memory | Build size |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ];
  for (const result of results) {
    lines.push(`| ${result.app} | ${formatMillisecondsPair(result.median.windowOpenMs, result.p90.windowOpenMs)} | ${formatMillisecondsPair(result.median.discoveryMs, result.p90.discoveryMs)} | ${formatMillisecondsPair(result.median.firstContentMs, result.p90.firstContentMs)} | ${formatMillisecondsPair(result.median.switchContentMs, result.p90.switchContentMs)} | ${formatMegabytes(result.median.initialMemory.residentSetBytes)} / ${formatMegabytes(result.median.initialMemory.physicalFootprintBytes)} | ${formatMegabytes(result.median.switchedMemory.residentSetBytes)} / ${formatMegabytes(result.median.switchedMemory.physicalFootprintBytes)} | ${formatMegabytes(result.buildSizeBytes)} |`);
  }
  if (results.length > 0) {
    lines.push(
      "",
      `Normalized parser parity: verified (${results[0].median.initialContentDigest} initial, ${results[0].median.switchContentDigest} switched).`,
    );
  }
  lines.push(
    "",
    "p50 content-stage diagnostics; post-native includes bridge transfer and viewport layout.",
    "",
    "| App | Initial native | Initial post-native | Switch native | Switch post-native |",
    "| --- | ---: | ---: | ---: | ---: |",
  );
  for (const result of results) {
    lines.push(`| ${result.app} | ${result.median.initialStages.nativeTotalMs.toFixed(1)} ms | ${Math.max(0, result.median.initialContentDurationMs - result.median.initialStages.nativeTotalMs).toFixed(1)} ms | ${result.median.switchStages.nativeTotalMs.toFixed(1)} ms | ${Math.max(0, result.median.internalSwitchContentMs - result.median.switchStages.nativeTotalMs).toFixed(1)} ms |`);
  }
  if (recordVideo) {
    lines.push(
      "",
      "p50 external video timing versus app-declared readiness. Differences expose premature or conservative internal boundaries.",
      "",
      "| App | First content video | First content internal | Switch video | Switch internal |",
      "| --- | ---: | ---: | ---: | ---: |",
    );
    for (const result of results) {
      lines.push(`| ${result.app} | ${result.median.firstContentMs.toFixed(1)} ms | ${result.median.internalFirstContentMs.toFixed(1)} ms | ${result.median.switchContentMs.toFixed(1)} ms | ${result.median.internalSwitchContentMs.toFixed(1)} ms |`);
    }
  }
  if (results.some((result) => result.iterations.some((iteration) => iteration.videoEvidence))) {
    lines.push("", "Recorded evidence:", "");
    for (const result of results) {
      const links = result.iterations.flatMap((iteration, index) => iteration.videoEvidence
        ? [`[${String(index + 1).padStart(2, "0")}](./${iteration.videoEvidence.video})`]
        : []);
      if (links.length > 0) {
        lines.push(`- ${result.app}: ${links.join(" · ")}`);
      }
    }
  }
  return `${lines.join("\n")}\n`;
}

async function main() {
  buildBenchmarkHelpers();
  if (recordVideo) {
    for (const executable of ["ffmpeg", "ffprobe"]) {
      if (command("which", [executable]) === "unknown") {
        throw new Error(`${executable} is required for visual benchmark recording`);
      }
    }
  }
  const fixtureManifest = JSON.parse(readFileSync(manifestPath, "utf8")) as BenchmarkFixtureManifest;
  if (fixtureManifest.version !== 2 || fixtureManifest.fixtures.length !== 2) {
    throw new Error("Unsupported fixture manifest; rerun bun run benchmark:fixtures");
  }
  await verifyFixtures(fixtureManifest);
  const config: BenchmarkConfig = {
    loadImages: fixtureManifest.loadImages,
    switchDelayMs: fixtureManifest.switchDelayMs,
    targets: fixtureManifest.fixtures.map(({ id, provider }) => ({ id, provider })) as BenchmarkConfig["targets"],
    version: 2,
  };
  const iterations = Math.max(1, Number(option("--iterations") ?? 10));
  const warmups = Math.max(0, Number(option("--warmups") ?? 2));
  const requestedApps = selectedApps();
  const timestamp = new Date().toISOString().replaceAll(":", "-");
  const videoDirectory = join(resultsRoot, `${timestamp}-videos`);
  for (const app of requestedApps) {
    const definition = apps[app];
    if (!existsSync(definition.executable)) {
      throw new Error(`Missing production build for ${app}; run bun run benchmark:build`);
    }
  }
  const rotatedApps = (round: number) => requestedApps.map(
    (_, index) => requestedApps[(index + round) % requestedApps.length],
  );
  for (let round = 0; round < warmups; round += 1) {
    for (const app of rotatedApps(round)) {
      console.log(`${app}: warm-up ${round + 1}/${warmups}`);
      await runIteration(app, config);
    }
  }
  const measuredByApp = new Map<AppName, IterationResult[]>(
    requestedApps.map((app) => [app, []]),
  );
  for (let round = 0; round < iterations; round += 1) {
    for (const app of rotatedApps(warmups + round)) {
      console.log(`${app}: measured ${round + 1}/${iterations}`);
      const artifactPath = recordVideo
        ? join(videoDirectory, `${app}-${String(round + 1).padStart(2, "0")}.mp4`)
        : undefined;
      measuredByApp.get(app)?.push(await runIteration(app, config, artifactPath));
    }
  }
  for (const phase of ["initialContentDigest", "switchContentDigest"] as const) {
    const digests = new Map<string, string[]>();
    for (const [app, appIterations] of measuredByApp) {
      for (const iteration of appIterations) {
        const owners = digests.get(iteration[phase]) ?? [];
        owners.push(app);
        digests.set(iteration[phase], owners);
      }
    }
    if (digests.size !== 1) {
      const detail = [...digests].map(([digest, owners]) => `${digest}: ${owners.join(", ")}`).join("; ");
      throw new Error(`Normalized parser parity failed for ${phase}: ${detail}`);
    }
  }
  const results = requestedApps.map<AppResult>((app) => {
    const measured = measuredByApp.get(app) ?? [];
    return {
      app,
      buildSizeBytes: bundleSize(apps[app].bundle),
      executable: apps[app].executable,
      iterations: measured,
      median: aggregateResult(measured, median),
      p90: aggregateResult(measured, (values) => percentile(values, 0.9)),
    };
  });
  mkdirSync(resultsRoot, { recursive: true });
  const result = {
    apps: results,
    buildManifest: existsSync(resolve(buildRoot, "build-manifest.json"))
      ? JSON.parse(readFileSync(resolve(buildRoot, "build-manifest.json"), "utf8"))
      : undefined,
    fixtures: fixtureManifest.fixtures,
    gitCommit: command("git", ["rev-parse", "HEAD"]),
    machine: {
      architecture: process.arch,
      cpu: command("sysctl", ["-n", "machdep.cpu.brand_string"]),
      macOS: command("sw_vers", ["-productVersion"]),
    },
    measuredAt: new Date().toISOString(),
    metrics: {
      buildSizeBytes: "Logical bytes of every file in the production .app bundle.",
      discoveryMs: "App-side wall time from starting native Codex and Claude history traversal until the discovered catalog is available to the app. This interval is contained within firstContentMs.",
      firstContentMs: recordVideo
        ? "Process launch to the first of three recorded frames matching the settled initial viewport."
        : "Process launch to app-declared completed initial layout (--no-video diagnostic mode).",
      internalReadiness: "App-declared window and content readiness retained for stage diagnosis; not used as visual timing authority when video is enabled.",
      memory: "Median of three stabilized aggregate RSS and physical-footprint samples for the app process tree and Tauri WebKit XPC helpers.",
      stages: "Native file/parser time and remaining bridge plus viewport-layout time within each content-open cycle.",
      switchContentMs: recordVideo
        ? "Selection start to the first of three recorded frames matching the settled switched viewport."
        : "Selection start to app-declared completed switched layout (--no-video diagnostic mode).",
      windowOpenMs: recordVideo
        ? "Process launch to the first of three recorded frames in which the app window replaces the pre-launch pixels."
        : "Process launch to the app's visible-window lifecycle callback (--no-video diagnostic mode).",
    },
    iterations,
    protocol: {
      cache: "Fixture verification reads and hashes every byte before measurements, producing a controlled warm filesystem cache.",
      discovery: "Every app receives only the two stable provider/id pairs, scans the native Codex and Claude history stores itself, and resolves both transcript paths inside the measured startup path.",
      memorySamples: 3,
      memorySettleMs: 300,
      order: "Deterministic round-robin rotation across apps for every warm-up and measured round.",
      visualAuthority: recordVideo
        ? "Timestamped target-60-fps ScreenCaptureKit application-surface capture with a cropped audit video and frame-evidence sidecar for every measured iteration."
        : "Disabled with --no-video; results use internal lifecycle events.",
    },
    warmups,
  };
  const jsonPath = join(resultsRoot, `${timestamp}.json`);
  const markdownPath = join(resultsRoot, `${timestamp}.md`);
  writeFileSync(jsonPath, `${JSON.stringify(result, null, 2)}\n`);
  writeFileSync(markdownPath, markdown(results));
  console.log(markdown(results));
  console.log(jsonPath);
  console.log(markdownPath);
}

await main();
