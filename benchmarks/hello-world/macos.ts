import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { buildRoot, repositoryRoot } from "./config";
import type { WindowInfo } from "../chat-history/video";

const productHelpers = resolve(repositoryRoot, "benchmarks/chat-history");
export const launchExecutable = join(buildRoot, "launch-app");
const windowExecutable = join(buildRoot, "window-info");
// Use the existing capture identity so the OS permission is shared by both suites.
const captureApp = resolve(repositoryRoot, ".build/chat-history-benchmarks/Chat History Benchmark Capture.app");
export const captureExecutable = join(captureApp, "Contents/MacOS/ChatHistoryCapture");
export const detectContentExecutable = join(buildRoot, "detect-content");
export const verifyTextExecutable = join(buildRoot, "verify-text");

export function buildHelpers() {
  mkdirSync(buildRoot, { recursive: true });
  const compile = (output: string, source: string, frameworks: string[] = []) => {
    if (!existsSync(output) || statSync(source).mtimeMs > statSync(output).mtimeMs) {
      execFileSync("swiftc", ["-O", ...frameworks.flatMap((name) => ["-framework", name]), source, "-o", output]);
    }
  };
  compile(launchExecutable, join(productHelpers, "launch-app.swift"), ["AppKit"]);
  compile(windowExecutable, join(productHelpers, "window-info.swift"));
  compile(detectContentExecutable, resolve(import.meta.dir, "detect-content.swift"), ["Vision", "AVFoundation"]);
  compile(verifyTextExecutable, resolve(import.meta.dir, "verify-text.swift"), ["Vision", "AppKit"]);
  mkdirSync(join(captureApp, "Contents/MacOS"), { recursive: true });
  copyFileSync(join(productHelpers, "CaptureInfo.plist"), join(captureApp, "Contents/Info.plist"));
  compile(captureExecutable, join(productHelpers, "capture-screen.swift"), ["ScreenCaptureKit", "AVFoundation", "CoreMedia", "CoreGraphics"]);
  execFileSync("codesign", ["--force", "--sign", "-", "--identifier", "so.legend.chat-history-benchmark-capture", captureApp], { stdio: "pipe" });
}

export function bundleSize(path: string): number {
  const info = lstatSync(path);
  if (info.isSymbolicLink()) return 0;
  if (!info.isDirectory()) return info.size;
  return readdirSync(path).reduce((sum, name) => sum + bundleSize(join(path, name)), 0);
}

type ProcessRow = { pid: number; ppid: number; rssKb: number; command: string };
function processTable(): ProcessRow[] {
  return execFileSync("ps", ["-axo", "pid=,ppid=,rss=,command="], { encoding: "utf8" }).trim().split("\n").flatMap((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.+)$/);
    return match ? [{ pid: Number(match[1]), ppid: Number(match[2]), rssKb: Number(match[3]), command: match[4] }] : [];
  });
}
const isWebKit = (row: ProcessRow) => /\/com\.apple\.WebKit\.(?:GPU|Networking|WebContent)(?:\.xpc)?\//.test(row.command);
export const webKitPids = () => new Set(processTable().filter(isWebKit).map((row) => row.pid));

function processTree(pid: number, baseline?: Set<number>) {
  const rows = processTable();
  const pids = new Set([pid]);
  for (const row of rows) if (baseline && isWebKit(row) && !baseline.has(row.pid)) pids.add(row.pid);
  let changed = true;
  while (changed) {
    changed = false;
    for (const row of rows) {
      if (pids.has(row.ppid) && !pids.has(row.pid)) { pids.add(row.pid); changed = true; }
    }
  }
  return { pids, rows };
}

export function percentile(values: number[], quantile: number) {
  if (!values.length || values.some((v) => !Number.isFinite(v))) throw new Error("Expected finite observations");
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * quantile) - 1)];
}
export const median = (values: number[]) => {
  const sorted = [...values].sort((a, b) => a - b);
  if (!sorted.length || sorted.some((v) => !Number.isFinite(v))) throw new Error("Expected finite observations");
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

export type Memory = { physicalFootprintBytes: number; residentSetBytes: number; processCount: number };
export async function settledMemory(pid: number, baseline?: Set<number>): Promise<Memory> {
  await Bun.sleep(2500);
  const samples: Memory[] = [];
  for (let index = 0; index < 3; index++) {
    process.kill(pid, 0);
    const { pids, rows } = processTree(pid, baseline);
    const output = execFileSync("/usr/bin/footprint", [...pids].flatMap((p) => ["-p", String(p)]).concat(["-f", "bytes", "--noCategories"]), { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const summary = output.match(/Summary Footprint:\s+(\d+) B/);
    const bytes = summary ? Number(summary[1]) : [...output.matchAll(/phys_footprint:\s+(\d+) B/g)].reduce((sum, match) => sum + Number(match[1]), 0);
    if (bytes <= 0) throw new Error(`No valid physical footprint for process ${pid}`);
    samples.push({ physicalFootprintBytes: bytes, residentSetBytes: rows.filter((r) => pids.has(r.pid)).reduce((sum, r) => sum + r.rssKb * 1024, 0), processCount: pids.size });
    if (index < 2) await Bun.sleep(200);
  }
  return {
    physicalFootprintBytes: median(samples.map((s) => s.physicalFootprintBytes)),
    residentSetBytes: median(samples.map((s) => s.residentSetBytes)),
    processCount: median(samples.map((s) => s.processCount)),
  };
}

export async function waitForWindow(pid: number): Promise<WindowInfo> {
  const start = Date.now();
  while (Date.now() - start < 30_000) {
    process.kill(pid, 0);
    try {
      return JSON.parse(execFileSync(windowExecutable, [...processTree(pid).pids].map(String), { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }));
    } catch { await Bun.sleep(20); }
  }
  throw new Error(`No on-screen window for process ${pid}`);
}

export async function stopApp(pid: number) {
  // Only descendants of our freshly launched process; WebKit XPC services exit with their client.
  const pids = [...processTree(pid).pids];
  for (const child of pids) {
    try { process.kill(child, "SIGTERM"); } catch { /* Already exited. */ }
  }
  for (let index = 0; index < 40; index++) {
    if (pids.every((child) => { try { process.kill(child, 0); return false; } catch { return true; } })) return;
    await Bun.sleep(25);
  }
  for (const child of pids) {
    try { process.kill(child, "SIGKILL"); } catch { /* Already exited. */ }
  }
}
