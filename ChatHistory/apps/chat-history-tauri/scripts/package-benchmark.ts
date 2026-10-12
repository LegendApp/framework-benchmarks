import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../..");
const sourceApp = resolve(appRoot, "src-tauri/target/release/bundle/macos/Chat History — Tauri.app");
const outputApp = resolve(repositoryRoot, ".build/chat-history-benchmarks/Chat History — Tauri.app");

rmSync(outputApp, { force: true, recursive: true });
mkdirSync(dirname(outputApp), { recursive: true });
cpSync(sourceApp, outputApp, { recursive: true });
execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
console.log(outputApp);
