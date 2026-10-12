import { cpSync, existsSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../../..");
const sourceApp = resolve(
  appRoot,
  "build/macos/Build/Products/Release/Chat History - Flutter.app",
);
const outputApp = resolve(
  repositoryRoot,
  ".build/chat-history-benchmarks/Chat History — Flutter.app",
);

if (!existsSync(sourceApp)) {
  throw new Error(`Missing Flutter release app at ${sourceApp}`);
}

rmSync(outputApp, { force: true, recursive: true });
cpSync(sourceApp, outputApp, { recursive: true });

const plist = resolve(outputApp, "Contents/Info.plist");
execFileSync("plutil", ["-replace", "CFBundleDisplayName", "-string", "Chat History — Flutter", plist]);
execFileSync("plutil", ["-replace", "CFBundleName", "-string", "Chat History — Flutter", plist]);
execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);

console.log(outputApp);
