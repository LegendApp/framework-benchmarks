import { grammarEngines, grammarEngineForApp, type GrammarPackRecord } from "../../ChatHistory/benchmark/grammar-packs";
import type { BuildEnvironment } from "../build-environment";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { closeSync, lstatSync, openSync, readFileSync, readdirSync, readlinkSync, readSync } from "node:fs";
import { join, resolve } from "node:path";
import { allApps, labels, type AppName } from "../../HelloWorld/benchmark/config";
import type { Suite } from "../cli";
import type { RenderingInputs } from "../../ChatHistory/benchmark/fairness";

export const manifestName = "benchmark-release.json";
export type BuildRecord = { grammarPack?: GrammarPackRecord; environment?: BuildEnvironment; builtAt: string; gitCommit: string; gitDirty: boolean; repositoryPath?: string; bundle?: string; renderingInputs?: RenderingInputs; release?: ReleaseIdentity };
export type ReleaseIdentity = { repository: string; tag: string; manifestSha256: string; comparisonCommit: string; bundles: Record<string, { archiveSha256: string; bundleSha256: string }> };
export type Asset = { suite: Suite; app: AppName; name: string; bytes: number; sha256: string; bundleSha256: string; build: BuildRecord };
export type GrammarAsset = { name: string; bytes: number; sha256: string; treeSha256: string; pack: GrammarPackRecord };
export type Manifest = {
  grammarAssets?: GrammarAsset[];
  version: 1; tag: string; createdAt: string; platform: "darwin"; arch: string;
  // Conservative support floor: release build host, not a claim about older OS versions.
  minimumMacOS: string; comparisonCommit: string; legendAppsCommit: string;
  tools: Record<string, string>; signing: "ad-hoc-or-developer-signed-not-notarization-verified"; assets: Asset[];
};
export function command(command: string, args: string[], cwd?: string) {
  return execFileSync(command, args, { cwd, encoding: "utf8", maxBuffer: 8 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] }).trim();
}
export function hashFile(path: string) {
  const hash = createHash("sha256");
  const handle = openSync(path, "r");
  try {
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    let count: number;
    while ((count = readSync(handle, buffer, 0, buffer.length, null))) hash.update(buffer.subarray(0, count));
  } finally { closeSync(handle); }
  return hash.digest("hex");
}
export function bundleHash(root: string) {
  const hash = createHash("sha256");
  function visit(relative: string) {
    const path = join(root, relative);
    const stat = lstatSync(path);
    const type = stat.isSymbolicLink() ? "link" : stat.isDirectory() ? "directory" : stat.isFile() ? "file" : "unsupported";
    if (type === "unsupported") throw new Error(`Unsupported bundle entry: ${path}`);
    hash.update(JSON.stringify([relative, type, stat.mode & 0o777, type === "file" ? hashFile(path) : type === "link" ? readlinkSync(path) : null]) + "\n");
    if (type === "directory") for (const name of readdirSync(path).sort()) visit(relative ? `${relative}/${name}` : name);
  }
  visit("");
  return hash.digest("hex");
}
export const bundleName = (suite: Suite, app: AppName) => `${suite === "chat-history" ? "Chat History" : "Hello World"} — ${labels[app]}.app`;
export const buildKey = (suite: Suite, app: AppName) => suite === "chat-history" && app.startsWith("deno-") ? "deno" : app;
export function cleanCommit(root: string) {
  if (command("git", ["status", "--porcelain", "--untracked-files=all"], root)) throw new Error(`Release source must be committed and clean: ${root}`);
  return command("git", ["rev-parse", "HEAD"], root);
}
export function validateManifest(value: unknown): Manifest {
  const data = value as Manifest;
  const sha = (value: unknown) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
  const commit = (value: unknown) => typeof value === "string" && /^[a-f0-9]{40}$/.test(value);
  if (!data || data.version !== 1 || data.platform !== "darwin" || !["arm64", "x64"].includes(data.arch) || !/^[\w.-]+$/.test(data.tag) || !/^\d+(\.\d+){1,2}$/.test(data.minimumMacOS) || !commit(data.comparisonCommit) || !commit(data.legendAppsCommit) || !Array.isArray(data.assets)) throw new Error("Invalid release manifest header");
  const keys = new Set<string>();
  const names = new Set<string>();
  for (const asset of data.assets) {
    if (!["chat-history", "hello-world"].includes(asset.suite) || !Object.hasOwn(labels, asset.app) || (asset.suite === "chat-history" && asset.app === "legend-shell")) throw new Error("Invalid release app");
    const key = `${asset.suite}/${asset.app}`;
    if (keys.has(key) || names.has(asset.name) || asset.name !== `${asset.suite}-${asset.app}-macos-${data.arch}.tar.gz` || !sha(asset.sha256) || !sha(asset.bundleSha256) || !Number.isSafeInteger(asset.bytes) || asset.bytes <= 0) throw new Error(`Invalid release asset: ${key}`);
    const expected = (asset.suite === "chat-history" && asset.app === "react-native") || asset.app === "legend-shell" ? data.legendAppsCommit : data.comparisonCommit;
    if (!asset.build || asset.build.gitDirty !== false || asset.build.gitCommit !== expected || asset.build.environment?.architecture !== data.arch || !asset.build.environment.tools || typeof asset.build.environment.macOS !== "string") throw new Error(`Unpinned source provenance: ${key}`);
    keys.add(key); names.add(asset.name);
  }
  const packs = new Map<string, GrammarAsset>();
  for (const asset of data.grammarAssets ?? []) {
    const pack = asset.pack;
    if (!pack || !grammarEngines.includes(pack.engine) || pack.version !== "v1" || packs.has(pack.engine) || names.has(asset.name) || asset.name !== `grammars-${pack.engine}-v1-macos-${data.arch}.tar.gz` || !sha(asset.sha256) || !sha(asset.treeSha256) || !sha(pack.manifestSha256) || !Number.isSafeInteger(asset.bytes) || asset.bytes <= 0 || !Number.isSafeInteger(pack.bytes) || pack.bytes <= 0) throw new Error("Invalid grammar release asset");
    packs.set(pack.engine, asset); names.add(asset.name);
  }
  for (const asset of data.assets) {
    if (data.grammarAssets && asset.suite === "chat-history") {
      const pack = packs.get(grammarEngineForApp(asset.app));
      if (!pack || JSON.stringify(pack.pack) !== JSON.stringify(asset.build.grammarPack)) throw new Error(`Missing or mismatched grammar asset for ${asset.app}`);
    } else if (asset.build.grammarPack) throw new Error("Grammar provenance without release assets");
  }
  const expectedKeys = ["chat-history", "hello-world"].flatMap(suite => allApps.map(app => `${suite}/${app}`));
  if (keys.size !== expectedKeys.length || expectedKeys.some(key => !keys.has(key))) throw new Error(`A release must contain all ${expectedKeys.length} current apps`);
  return data;
}
export function assertReleaseSet(records: { app: string; bundle: string; build: BuildRecord }[], root?: string) {
  const releases = records.filter(record => record.build.release);
  if (!releases.length) return;
  if (releases.length !== records.length) throw new Error("Selected apps mix local builds and prebuilt releases. Download one matched release or rebuild all selected apps.");
  const identities = new Set(releases.map(({ build }) => JSON.stringify([build.release!.repository, build.release!.tag, build.release!.manifestSha256])));
  if (identities.size !== 1) throw new Error("Selected apps come from different prebuilt releases.");
  if (root && cleanCommit(root) !== releases[0].build.release!.comparisonCommit) throw new Error("Prebuilt benchmarks require the clean harness checkout from their release.");
  for (const { app, bundle, build } of releases) {
    const expected = build.release!.bundles[app];
    if (!expected || bundleHash(bundle) !== expected.bundleSha256) throw new Error(`Prebuilt bundle changed: ${app}. Download it again before benchmarking.`);
  }
}
export function readManifest(path: string) { return validateManifest(JSON.parse(readFileSync(resolve(path), "utf8"))); }
