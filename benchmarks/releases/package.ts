import { grammarPackRoot, verifyAppGrammarPack } from "../chat-history/grammar-packs";
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs, plan } from "../cli";
import { repositoryRoot } from "../hello-world/config";
import { renderingInputs, verifyRenderingInputs } from "../chat-history/fairness";
import { options, tag } from "./options";
import { buildKey, bundleHash, bundleName, cleanCommit, command, hashFile, manifestName, validateManifest, type BuildRecord, type Manifest } from "./shared";

async function main() {
  const args = options(process.argv.slice(2), ["--tag", "--output", "--legend-apps-repo"]);
  if (args["--help"]) {
    console.log("Usage: bun run benchmark:release:package --tag <tag> [--output <new-directory>] [--legend-apps-repo <path>]\nPackages all 20 existing builds. Requires clean source checkouts and matching clean build provenance. Does not build or publish. Default output: .build/releases/<tag>-macos-<arch>."); return;
  }
  if (process.platform !== "darwin") throw new Error("Packaging requires macOS.");
  const releaseTag = tag(args["--tag"]);
  const legendRoot = resolve(args["--legend-apps-repo"] ?? process.env.LEGEND_APPS_REPO ?? resolve(repositoryRoot, "../legend-apps"));
  const comparisonCommit = cleanCommit(repositoryRoot);
  const legendAppsCommit = cleanCommit(legendRoot);
  const output = resolve(args["--output"] ?? resolve(repositoryRoot, `.build/releases/${releaseTag}-macos-${process.arch}`));
  if (existsSync(output)) throw new Error(`Output already exists; choose a new directory: ${output}`);
  const jobs = plan("run", parseArgs("run", []));
  const selected = jobs.flatMap(job => {
    const directory = resolve(repositoryRoot, `.build/${job.suite}-benchmarks`);
    const manifest = JSON.parse(readFileSync(resolve(directory, "build-manifest.json"), "utf8"));
    return job.apps.map(app => {
      const record: BuildRecord = manifest.builds?.[buildKey(job.suite, app)];
      const expected = (job.suite === "chat-history" && app === "react-native") || app === "legend-shell" ? legendAppsCommit : comparisonCommit;
      if (!record || record.gitDirty !== false || record.gitCommit !== expected || record.release || record.environment?.architecture !== process.arch) throw new Error(`${job.suite}/${app}: rebuild from the current clean source before packaging.`);
      const bundle = resolve(directory, bundleName(job.suite, app));
      command("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle]);
      const executable = command("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleExecutable", resolve(bundle, "Contents/Info.plist")]);
      if (executable.includes("/") || executable === "..") throw new Error(`Invalid executable: ${bundle}`);
      const archs = command("/usr/bin/lipo", ["-archs", resolve(bundle, "Contents/MacOS", executable)]).split(/\s+/);
      if (!archs.includes(process.arch === "x64" ? "x86_64" : process.arch)) throw new Error(`Architecture mismatch: ${bundle}`);
      if (job.suite === "chat-history") verifyAppGrammarPack(repositoryRoot, app, record.grammarPack);
      return { suite: job.suite, app, bundle, record };
    });
  });
  verifyRenderingInputs({ ...Object.fromEntries(selected.filter(item => item.suite === "chat-history").map(item => [item.app, item.record.renderingInputs])), currentPolicy: renderingInputs(repositoryRoot, "policy") });
  const tools: Record<string, string> = { bun: Bun.version, macOS: command("/usr/bin/sw_vers", ["-productVersion"]), xcode: command("/usr/bin/xcodebuild", ["-version"]) };
  for (const [name, executable, toolArgs] of [
    ["rust", resolve(repositoryRoot, "scripts/with-local-rust.sh"), ["rustc", "--version"]],
    ["flutter", resolve(repositoryRoot, "scripts/with-local-flutter.sh"), ["flutter", "--version"]],
    ["deno", resolve(repositoryRoot, "scripts/with-local-deno.sh"), ["deno", "--version"]],
    ["cocoapods", "pod", ["--version"]],
  ] as const) tools[name] = command(executable, [...toolArgs]);
  const manifest: Manifest = { version: 1, tag: releaseTag, createdAt: new Date().toISOString(), platform: "darwin", arch: process.arch, minimumMacOS: tools.macOS, comparisonCommit, legendAppsCommit, tools, signing: "ad-hoc-or-developer-signed-not-notarization-verified", assets: [], grammarAssets: [] };
  mkdirSync(output, { recursive: true });
  for (const item of selected) {
    const name = `${item.suite}-${item.app}-macos-${process.arch}.tar.gz`;
    console.log(`Packaging ${name}`);
    const before = bundleHash(item.bundle);
    // Store only bundle files, modes and symlinks, without owner names or AppleDouble sidecars.
    command("python3", [resolve(import.meta.dir, "archive.py"), "create", item.bundle, resolve(output, name)]);
    if (bundleHash(item.bundle) !== before) throw new Error(`Bundle changed while packaging: ${item.bundle}`);
    const verification = resolve(output, `.verify-${item.suite}-${item.app}`);
    try {
      command("python3", [resolve(import.meta.dir, "archive.py"), "extract", resolve(output, name), verification, bundleName(item.suite, item.app)]);
      if (bundleHash(resolve(verification, bundleName(item.suite, item.app))) !== before) throw new Error(`Archive round trip changed bundle: ${name}`);
    } finally { rmSync(verification, { recursive: true, force: true }); }
    const { repositoryPath: _path, bundle: _bundle, release: _release, ...build } = item.record;
    manifest.assets.push({ suite: item.suite, app: item.app, name, bytes: statSync(resolve(output, name)).size, sha256: hashFile(resolve(output, name)), bundleSha256: before, build });
  }
  const grammarRecords = new Map(selected.filter(item => item.suite === "chat-history").map(item => [item.record.grammarPack!.engine, item.record.grammarPack!]));
  for (const [engine, pack] of grammarRecords) {
    const source = resolve(grammarPackRoot(repositoryRoot), engine);
    const name = `grammars-${engine}-v1-macos-${process.arch}.tar.gz`;
    const treeSha256 = bundleHash(source);
    command("python3", [resolve(import.meta.dir, "archive.py"), "create", source, resolve(output, name)]);
    const verification = resolve(output, `.verify-grammar-${engine}`);
    try {
      command("python3", [resolve(import.meta.dir, "archive.py"), "extract", resolve(output, name), verification, engine]);
      if (bundleHash(resolve(verification, engine)) !== treeSha256 || bundleHash(source) !== treeSha256) throw new Error(`Grammar archive round trip failed: ${engine}`);
    } finally { rmSync(verification, { recursive: true, force: true }); }
    manifest.grammarAssets!.push({ name, bytes: statSync(resolve(output, name)).size, sha256: hashFile(resolve(output, name)), treeSha256, pack });
  }
  if (cleanCommit(repositoryRoot) !== comparisonCommit || cleanCommit(legendRoot) !== legendAppsCommit) throw new Error("Source changed during packaging.");
  validateManifest(manifest);
  writeFileSync(resolve(output, manifestName), JSON.stringify(manifest, null, 2) + "\n");
  writeFileSync(resolve(output, "SHA256SUMS"), [manifestName, ...manifest.assets.map(asset => asset.name), ...manifest.grammarAssets!.map(asset => asset.name)].map(name => `${hashFile(resolve(output, name))}  ${name}\n`).join(""));
  console.log(`Release package: ${output}\nNo files published. The manifest is only written after every archive succeeds.`);
}
try { await main(); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
