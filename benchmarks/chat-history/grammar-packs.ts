import { createHash } from "node:crypto";
import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, renameSync, rmSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

export const grammarPackVersion = "v1";
export const grammarEngines = ["tree-sitter", "highlight-js", "highlighter-swift", "syntect", "dart-highlighting"] as const;
export type GrammarEngine = typeof grammarEngines[number];
export type GrammarPack = { version: 1; engine: GrammarEngine; bytes: number; files: Record<string, { bytes: number; sha256: string }> };
export function grammarPackRoot(root: string) {
  return resolve(root, ".build/chat-history-benchmarks/grammar-packs", grammarPackVersion);
}
export function inspectGrammarPack(directory: string, engine: GrammarEngine): GrammarPack {
  const files: GrammarPack["files"] = {};
  function visit(relative: string) {
    for (const name of readdirSync(join(directory, relative)).sort()) {
      const path = relative ? `${relative}/${name}` : name;
      if (path === "manifest.json") continue;
      const stat = lstatSync(join(directory, path));
      if (stat.isSymbolicLink()) throw new Error(`Grammar pack cannot contain symlinks: ${path}`);
      if (stat.isDirectory()) visit(path);
      else if (stat.isFile()) files[path] = { bytes: stat.size, sha256: createHash("sha256").update(readFileSync(join(directory, path))).digest("hex") };
      else throw new Error(`Unsupported grammar pack entry: ${path}`);
    }
  }
  visit("");
  if (!Object.keys(files).length) throw new Error(`Empty grammar pack: ${engine}`);
  return { version: 1, engine, bytes: Object.values(files).reduce((n, file) => n + file.bytes, 0), files };
}
export function sealGrammarPack(directory: string, engine: GrammarEngine) {
  const manifest = inspectGrammarPack(directory, engine);
  writeFileSync(join(directory, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  return manifest;
}
export function verifyGrammarPack(directory: string, engine: GrammarEngine) {
  if (!existsSync(join(directory, "manifest.json"))) throw new Error(`Missing ${engine} grammar pack. Rebuild or download the matching benchmark assets.`);
  const expected = JSON.parse(readFileSync(join(directory, "manifest.json"), "utf8"));
  const actual = inspectGrammarPack(directory, engine);
  if (JSON.stringify(expected) !== JSON.stringify(actual)) throw new Error(`Modified ${engine} grammar pack: ${directory}`);
  return actual;
}
export function prepareGrammarPack(root: string, engine: GrammarEngine) {
  const directory = join(grammarPackRoot(root), engine);
  rmSync(directory, { recursive: true, force: true });
  mkdirSync(directory, { recursive: true });
  return directory;
}

export function grammarEngineForApp(app: string): GrammarEngine {
  if (app === "react-native") return "tree-sitter";
  if (app === "appkit" || app === "swiftui") return "highlighter-swift";
  if (app === "gpui") return "syntect";
  if (app === "flutter") return "dart-highlighting";
  if (["electron", "tauri", "deno", "deno-webview", "deno-cef"].includes(app)) return "highlight-js";
  throw new Error(`No grammar engine for ${app}`);
}
export type GrammarPackRecord = { engine: GrammarEngine; version: "v1"; bytes: number; manifestSha256: string };
export function grammarPackRecord(root: string, app: string): GrammarPackRecord {
  const engine = grammarEngineForApp(app);
  const directory = join(grammarPackRoot(root), engine);
  const pack = verifyGrammarPack(directory, engine);
  const manifest = readFileSync(join(directory, "manifest.json"));
  return { engine, version: grammarPackVersion, bytes: pack.bytes + manifest.length, manifestSha256: createHash("sha256").update(manifest).digest("hex") };
}
export function verifyAppGrammarPack(root: string, app: string, expected: GrammarPackRecord | undefined) {
  const actual = grammarPackRecord(root, app);
  if (!expected || JSON.stringify(expected) !== JSON.stringify(actual)) throw new Error(`Grammar provenance differs for ${app}; rebuild or download a matched app and grammar pack.`);
  return actual;
}

// Runtime resources belong in an application cache, not a protected Documents
// checkout. This is installation only: parsing/compilation still happens in-app.
export function installRuntimeGrammarPacks(root: string, apps: string[], cacheBase = join(homedir(), "Library/Caches/so.legend.desktop-benchmarks/grammars")) {
  const records = [...new Map(apps.map(app => {
    const record = grammarPackRecord(root, app); return [record.engine, record] as const;
  })).values()].sort((a, b) => a.engine.localeCompare(b.engine));
  const identity = createHash("sha256").update(JSON.stringify(records)).digest("hex");
  const destination = join(cacheBase, identity);
  mkdirSync(destination, { recursive: true });
  for (const record of records) {
    const target = join(destination, record.engine);
    if (!existsSync(target)) {
      const staging = mkdtempSync(join(destination, ".install-"));
      try {
        const stagedPack = join(staging, record.engine);
        cpSync(join(grammarPackRoot(root), record.engine), stagedPack, { recursive: true });
        verifyGrammarPack(stagedPack, record.engine);
        renameSync(stagedPack, target);
      } finally { rmSync(staging, { recursive: true, force: true }); }
    }
    verifyGrammarPack(target, record.engine);
    const actualHash = createHash("sha256").update(readFileSync(join(target, "manifest.json"))).digest("hex");
    if (actualHash !== record.manifestSha256) throw new Error(`Runtime grammar cache changed: ${target}`);
  }
  return destination;
}
