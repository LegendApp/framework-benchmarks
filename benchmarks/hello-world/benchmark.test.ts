import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "bun:test";
import { selectedApps, option } from "./config";
import { median, percentile } from "./macos";

describe("baseline benchmark configuration", () => {
  test("selects all ten apps and both Deno backends", () => {
    expect(selectedApps([])).toHaveLength(10);
    expect(selectedApps(["--app=deno"])).toEqual(["deno-webview", "deno-cef"]);
    expect(selectedApps(["--app", "react-native"])).toEqual(["react-native"]);
  });
  test("rejects unknown targets and missing values", () => {
    expect(() => selectedApps(["--app", "__proto__"])).toThrow("Unknown app");
    expect(() => option("--app", ["--app", "--launch"])).toThrow("Missing value");
  });
  test("summarizes even samples and nearest-rank p90 without changing raw order", () => {
    const values = [40, 10, 30, 20];
    expect(median(values)).toBe(25);
    expect(percentile(values, 0.9)).toBe(40);
    expect(values).toEqual([40, 10, 30, 20]);
    expect(() => median([])).toThrow();
  });
});

test("OCR detects readable greeting before the old pixel-match boundary", () => {
  const temp = mkdtempSync(join(tmpdir(), "hello-world-ocr-test-"));
  try {
    const detector = join(temp, "detect-content");
    execFileSync("swiftc", ["-O", "-framework", "AVFoundation", "-framework", "Vision", resolve(import.meta.dir, "detect-content.swift"), "-o", detector], { stdio: "pipe" });
    const frames = JSON.parse(execFileSync(detector, [
      resolve(import.meta.dir, "fixtures/readable-before-pixel-match.mp4"),
      "0", "0", "0", "1", "1",
    ], { encoding: "utf8" }));
    // This captured text was readable around 367 ms into the video, while
    // final-image matching rejected it until roughly 1050 ms.
    expect(frames.at(-3).videoMs).toBeGreaterThan(300);
    expect(frames.at(-3).videoMs).toBeLessThan(500);
    expect(frames.slice(-3).every((frame: {matched: boolean}) => frame.matched)).toBe(true);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("paired report consumes the product apps schema and rejects diagnostic-only timing", () => {
  const temp = mkdtempSync(join(tmpdir(), "hello-world-report-test-"));
  try {
    const productPath = join(temp, "product.json");
    const helloPath = join(temp, "hello.json");
    const product = {
      measuredAt: "2026-09-09", iterations: 10, warmups: 2,
      protocol: { visualAuthority: "Timestamped target-60-fps capture" },
      apps: [{ app: "appkit", buildSizeBytes: 2097152, median: { firstContentMs: 400, initialMemory: { physicalFootprintBytes: 4194304 } } }],
    };
    writeFileSync(productPath, JSON.stringify(product));
    writeFileSync(helloPath, JSON.stringify({
      workload: "hello-world", measuredAt: "2026-09-09", iterations: 1, warmups: 0,
      results: [{ app: "appkit", buildSizeBytes: 1048576, median: { firstContentMs: 100, physicalFootprintBytes: 2097152 } }],
    }));
    const args = [resolve(import.meta.dir, "compare.ts"), "--product", productPath, "--hello-world", helloPath];
    const output = execFileSync("bun", args, { encoding: "utf8" });
    expect(output).toContain("| AppKit | 100.0 / 400.0 | 2.0 / 4.0 | 1.0 / 2.0 |");
    expect(output).toContain("1 iterations, 0 warmups");
    product.protocol.visualAuthority = "Disabled with --no-video";
    writeFileSync(productPath, JSON.stringify(product));
    const invalid = spawnSync("bun", args, { encoding: "utf8" });
    expect(invalid.status).not.toBe(0);
    expect(invalid.stderr).toContain("must use video-derived visual timing");
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
