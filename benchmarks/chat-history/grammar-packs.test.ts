import { test, expect } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { grammarPackRoot, sealGrammarPack, grammarPackRecord, verifyAppGrammarPack, verifyGrammarPack, installRuntimeGrammarPacks } from "./grammar-packs";

test("pack verification catches missing, altered and added files and mismatched app provenance", () => {
  const root = mkdtempSync(join(tmpdir(), "benchmark-grammars-"));
  try {
    const directory = join(grammarPackRoot(root), "highlight-js");
    mkdirSync(directory, { recursive: true });
    expect(() => verifyGrammarPack(directory, "highlight-js")).toThrow("Missing");
    writeFileSync(join(directory, "grammars.mjs"), "export function register() {}");
    sealGrammarPack(directory, "highlight-js");
    const record = grammarPackRecord(root, "electron");
    expect(verifyAppGrammarPack(root, "tauri", record)).toEqual(record);
    const runtime = installRuntimeGrammarPacks(root, ["electron", "tauri"], join(root, "cache"));
    expect(verifyGrammarPack(join(runtime, "highlight-js"), "highlight-js").bytes).toBeGreaterThan(0);
    expect(installRuntimeGrammarPacks(root, ["tauri", "electron"], join(root, "cache"))).toBe(runtime);
    writeFileSync(join(runtime, "highlight-js/grammars.mjs"), "corrupt cached data");
    expect(() => installRuntimeGrammarPacks(root, ["electron"], join(root, "cache"))).toThrow("Modified");
    expect(() => verifyAppGrammarPack(root, "electron", { ...record, manifestSha256: "0".repeat(64) })).toThrow("provenance");
    writeFileSync(join(directory, "grammars.mjs"), "modified");
    expect(() => verifyGrammarPack(directory, "highlight-js")).toThrow("Modified");
    sealGrammarPack(directory, "highlight-js");
    writeFileSync(join(directory, "unexpected"), "data");
    expect(() => verifyGrammarPack(directory, "highlight-js")).toThrow("Modified");
    symlinkSync("grammars.mjs", join(directory, "alias"));
    expect(() => sealGrammarPack(directory, "highlight-js")).toThrow("symlinks");
  } finally { rmSync(root, { recursive: true, force: true }); }
});
