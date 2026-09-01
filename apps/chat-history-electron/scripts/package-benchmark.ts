import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../..");
const electronApp = resolve(appRoot, "node_modules/electron/dist/Electron.app");
const outputApp = resolve(repositoryRoot, ".build/chat-history-benchmarks/Chat History — Electron.app");
const resourcesApp = join(outputApp, "Contents/Resources/app");
const infoPlist = join(outputApp, "Contents/Info.plist");

rmSync(outputApp, { force: true, recursive: true });
mkdirSync(dirname(outputApp), { recursive: true });
cpSync(electronApp, outputApp, { recursive: true });
mkdirSync(resourcesApp, { recursive: true });
cpSync(join(appRoot, "dist"), join(resourcesApp, "dist"), { recursive: true });
writeFileSync(join(resourcesApp, "package.json"), JSON.stringify({
  main: "dist/main.js",
  name: "legend-chat-history-electron-benchmark",
  private: true,
  type: "module",
  version: "0.0.1",
}));

for (const [key, value] of [
  ["CFBundleDisplayName", "Chat History — Electron"],
  ["CFBundleIdentifier", "so.legend.chathistory.electron"],
  ["CFBundleName", "Chat History — Electron"],
] as const) {
  execFileSync("plutil", ["-replace", key, "-string", value, infoPlist]);
}

execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
console.log(outputApp);
