import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { parseArgs, plan, preflightBuilds } from "./cli";

const jobs = (mode: "build" | "run", args: string[] = []) => plan(mode, parseArgs(mode, args));

describe("benchmark CLI", () => {
  test("defaults select 9 product and 10 baseline apps with separate build/run scripts", () => {
    for (const mode of ["build", "run"] as const) {
      const selected = jobs(mode);
      expect(selected.map(job => job.apps.length)).toEqual([9, 10]);
      expect(selected.every(job => job.args[0].endsWith(`/${mode}.ts`))).toBe(true);
    }
    const options = parseArgs("run", []);
    expect([options.warmups, options.iterations, options.settleMs]).toEqual([2, 10, 5000]);
  });
  test("app and suite filters, Deno grouping, and shell-only baseline", () => {
    expect(jobs("run", ["--app=gpui"]).map(job => job.apps)).toEqual([["gpui"], ["gpui"]]);
    expect(jobs("build", ["--app", "legend-shell"]).map(job => job.suite)).toEqual(["hello-world"]);
    expect(jobs("build", ["--suite", "chat-history", "--app", "electron,deno-cef"])[0].args[2]).toBe("electron,deno");
    expect(jobs("build", ["--suite", "chat-history", "--app", "deno-cef"])[0].apps).toEqual(["deno-cef", "deno-webview"]);
    expect(jobs("run", ["--suite", "chat-history", "--app", "deno-cef"])[0].apps).toEqual(["deno-cef"]);
    expect(jobs("run", ["--app", "deno,appkit,deno-cef"])[0].apps).toEqual(["deno-webview", "deno-cef", "appkit"]);
  });
  test("rejects typos and invalid values instead of silently running all apps", () => {
    for (const args of [["--app"], ["--app", "electron,"], ["--suite", "bad"], ["--warmups", "-1"], ["--iterations=0"], ["--iterations=1.5"], ["--iterations=NaN"], ["--app=appkit", "--app=gpui"], ["--suite=chat-history", "--app=legend-shell"], ["--suite=chat-history", "--settle-ms=5000"], ["--yes"], ["--no-video"]]) {
      expect(() => parseArgs("run", args)).toThrow();
    }
    expect(() => parseArgs("build", ["--iterations=1"])).toThrow();
  });
  test("preflights every suite before measurement", () => {
    const root = mkdtempSync(resolve(tmpdir(), "benchmark-cli-test-"));
    try {
      const selected = jobs("run", ["--suite=hello-world", "--app=appkit,gpui"]);
      const directory = resolve(root, ".build/hello-world-benchmarks");
      mkdirSync(resolve(directory, "Hello World — AppKit.app/Contents"), { recursive: true });
      writeFileSync(resolve(directory, "Hello World — AppKit.app/Contents/Info.plist"), "fixture");
      writeFileSync(resolve(directory, "build-manifest.json"), JSON.stringify({ builds: { appkit: {} } }));
      expect(() => preflightBuilds(selected, root)).toThrow("hello-world/gpui");
      expect(() => preflightBuilds(jobs("run", ["--suite=hello-world", "--app=appkit"]), root)).not.toThrow();
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  test("public entry points support help/dry-run and reject unconfirmed noninteractive builds", () => {
    for (const mode of ["build", "run"]) {
      for (const arg of ["--help", "--dry-run"]) {
        const result = Bun.spawnSync([process.execPath, resolve(import.meta.dir, `${mode}.ts`), arg], { stdin: "pipe" });
        expect(result.exitCode).toBe(0);
        expect(result.stdout.toString()).toContain(arg === "--help" ? "Usage:" : "plan (19 apps)");
      }
    }
    if (process.platform === "darwin") {
      const result = Bun.spawnSync([process.execPath, resolve(import.meta.dir, "build.ts"), "--app=appkit"], { stdin: "pipe" });
      expect(result.exitCode).toBe(1);
      expect(result.stderr.toString()).toContain("Confirmation requires an interactive terminal");
    }
  });
});
