import { expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { plan, parseArgs } from "../cli";
import { assertReleaseSet, bundleHash, validateManifest, type Manifest, type ReleaseIdentity } from "./shared";
import { installTransaction } from "./install";
import { compatibleOS } from "./download";
import { options, tag } from "./options";

const sha = "a".repeat(64), commit = "b".repeat(40);
function manifest(): Manifest {
  return {
    version: 1, tag: "bench-1", createdAt: new Date().toISOString(), arch: "arm64", platform: "darwin", minimumMacOS: "26.0", comparisonCommit: commit, legendAppsCommit: commit,
    tools: {}, signing: "ad-hoc-or-developer-signed-not-notarization-verified",
    assets: plan("run", parseArgs("run", [])).flatMap(job => job.apps.map(app => ({ suite: job.suite, app, name: `${job.suite}-${app}-macos-arm64.tar.gz`, bytes: 1, sha256: sha, bundleSha256: sha, build: { builtAt: "now", gitCommit: commit, gitDirty: false, environment: { architecture: "arm64", macOS: "26.0", tools: { bun: "test" } } } }))),
  };
}

test("release manifest requires a complete, clean, pinned set and safe asset names", () => {
  expect(validateManifest(manifest()).assets).toHaveLength(20);
  for (const mutate of [
    (m: Manifest) => { m.assets.pop(); },
    (m: Manifest) => { m.assets[0].name = "../escape"; },
    (m: Manifest) => { m.assets[0].build.gitDirty = true; },
    (m: Manifest) => { m.assets[0].build.gitCommit = "c".repeat(40); },
    (m: Manifest) => { m.assets[0].sha256 = "bad"; },
    (m: Manifest) => { m.assets[1] = m.assets[0]; },
  ]) {
    const changed = manifest(); mutate(changed);
    expect(() => validateManifest(changed)).toThrow();
  }
});

test("bundle hashes cover bytes, permissions and symlink targets; release comparisons reject drift", () => {
  const root = mkdtempSync(resolve(tmpdir(), "release-hash-"));
  try {
    writeFileSync(resolve(root, "binary"), "original");
    const hash = bundleHash(root);
    chmodSync(resolve(root, "binary"), 0o755);
    expect(bundleHash(root)).not.toBe(hash);
    symlinkSync("binary", resolve(root, "alias"));
    const identity: ReleaseIdentity = { repository: "owner/repo", tag: "bench-1", comparisonCommit: commit, manifestSha256: sha, bundles: { appkit: { bundleSha256: bundleHash(root), archiveSha256: sha } } };
    const build = { builtAt: "now", gitCommit: commit, gitDirty: false, release: identity };
    const record = { app: "appkit", bundle: root, build };
    expect(() => assertReleaseSet([record])).not.toThrow();
    expect(() => assertReleaseSet([record, { ...record, build: { ...build, release: undefined } }])).toThrow("mix local");
    expect(() => assertReleaseSet([record, { ...record, build: { ...build, release: { ...identity, tag: "bench-2" } } }])).toThrow("different prebuilt");
    writeFileSync(resolve(root, "binary"), "changed");
    expect(() => assertReleaseSet([record])).toThrow("bundle changed");
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("failed install restores both replaced files and bundles", () => {
  const root = mkdtempSync(resolve(tmpdir(), "release-install-"));
  try {
    const destination = resolve(root, "installed");
    mkdirSync(destination); writeFileSync(resolve(destination, "binary"), "old");
    const staged = resolve(root, "staged"); mkdirSync(staged); writeFileSync(resolve(staged, "binary"), "new");
    expect(() => installTransaction([{ staged, destination }, { staged: resolve(root, "missing"), destination: resolve(root, "manifest") }], resolve(root, "backups"))).toThrow();
    expect(readFileSync(resolve(destination, "binary"), "utf8")).toBe("old");
    mkdirSync(staged); writeFileSync(resolve(staged, "binary"), "new");
    installTransaction([{ staged, destination }], resolve(root, "other-backups"));
    expect(readFileSync(resolve(destination, "binary"), "utf8")).toBe("new");
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("version floor and strict options", () => {
  expect(compatibleOS("26.1", "26.0.2")).toBe(true);
  expect(compatibleOS("26.0", "26.0.1")).toBe(false);
  expect(compatibleOS("26.0", "26.0.0")).toBe(true);
  expect(() => tag("../escape")).toThrow();
  expect(() => tag("latest")).toThrow();
  expect(() => options(["--repo"], ["--repo"])).toThrow();
  expect(() => options(["--unknown"], [])).toThrow();
});

test("release entry points show help without GitHub or build side effects", () => {
  for (const script of ["package", "publish", "download"]) {
    const child = Bun.spawnSync([process.execPath, resolve(import.meta.dir, `${script}.ts`), "--help"]);
    expect(child.exitCode).toBe(0);
    expect(child.stdout.toString()).toContain("Usage:");
  }
});

test("release grammar assets must match every chat app's engine and pinned pack", async () => {
  const { grammarEngines, grammarEngineForApp } = await import("../chat-history/grammar-packs");
  const value = manifest();
  value.grammarAssets = grammarEngines.map(engine => ({ name: `grammars-${engine}-v1-macos-arm64.tar.gz`, bytes: 10, sha256: sha, treeSha256: sha, pack: { engine, version: "v1", bytes: 20, manifestSha256: sha } }));
  for (const asset of value.assets) if (asset.suite === "chat-history") asset.build.grammarPack = { ...value.grammarAssets.find(pack => pack.pack.engine === grammarEngineForApp(asset.app))!.pack };
  expect(validateManifest(value).grammarAssets).toHaveLength(6);
  const missing = structuredClone(value); missing.grammarAssets!.pop();
  expect(() => validateManifest(missing)).toThrow("Missing or mismatched");
  const mismatch = structuredClone(value); mismatch.assets[0].build.grammarPack!.manifestSha256 = "f".repeat(64);
  expect(() => validateManifest(mismatch)).toThrow("Missing or mismatched");
  const escaped = structuredClone(value); escaped.grammarAssets![0].name = "../grammars.tar.gz";
  expect(() => validateManifest(escaped)).toThrow("Invalid grammar");
});
