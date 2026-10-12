import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../../..");

for (const backend of ["WebView", "CEF"] as const) {
  const sourceApp = join(appRoot, "build", `Chat History - Deno ${backend}.app`);
  const outputApp = join(repositoryRoot, ".build", "chat-history-benchmarks", `Chat History — Deno ${backend}.app`);
  const infoPlist = join(outputApp, "Contents", "Info.plist");

  rmSync(outputApp, { force: true, recursive: true });
  mkdirSync(dirname(outputApp), { recursive: true });
  cpSync(sourceApp, outputApp, { recursive: true });
  for (const [key, value] of [
    ["CFBundleDisplayName", `Chat History — Deno ${backend}`],
    ["CFBundleIdentifier", `so.legend.chathistory.deno.${backend.toLowerCase()}`],
    ["CFBundleName", `Chat History — Deno ${backend}`],
  ] as const) {
    execFileSync("plutil", ["-replace", key, "-string", value, infoPlist]);
  }
  execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
  console.log(outputApp);
}
