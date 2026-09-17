import { execFileSync } from "node:child_process";
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs, plan } from "../cli";
import { repositoryRoot } from "../hello-world/config";
import { renderingInputs, verifyRenderingInputs } from "../chat-history/fairness";
import { options, repository, tag } from "./options";
import { buildKey, bundleHash, bundleName, cleanCommit, command, hashFile, manifestName, readManifest, type BuildRecord, type ReleaseIdentity } from "./shared";
import { installTransaction } from "./install";

type GitHubAsset = { id: number; name: string; size: number; digest: string };
function fetchAsset(repo: string, asset: GitHubAsset | undefined, path: string) {
  if (!asset || !Number.isSafeInteger(asset.id) || !/^sha256:[a-f0-9]{64}$/.test(asset.digest ?? "")) throw new Error(`Missing asset or GitHub SHA-256 digest: ${path}`);
  console.log(`Downloading ${asset.name} (${(asset.size / 1024 / 1024).toFixed(1)} MiB)`);
  const fd = openSync(path, "wx");
  try { execFileSync("gh", ["api", `repos/${repo}/releases/assets/${asset.id}`, "-H", "Accept: application/octet-stream"], { stdio: ["ignore", fd, "pipe"] }); }
  finally { closeSync(fd); }
  if (statSync(path).size !== asset.size || `sha256:${hashFile(path)}` !== asset.digest) throw new Error(`GitHub asset verification failed: ${asset.name}`);
}
export function compatibleOS(actual: string, minimum: string) {
  const a = actual.split(".").map(Number), b = minimum.split(".").map(Number);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) > (b[i] ?? 0);
  }
  return true;
}
async function main() {
  const args = options(process.argv.slice(2), ["--repo", "--release", "--suite", "--app"]);
  if (args["--help"]) { console.log("Usage: bun run benchmark:download [--repo owner/repo] [--release latest|<tag>] [--suite all|chat-history|hello-world] [--app all|<comma-list>]\nDefaults: latest, both suites, all apps. Requires gh authentication, macOS, Python 3, and a clean checkout at the release's source commit. Resolves one release, verifies and stages every selected asset, then replaces selected local builds. Chat-history Deno downloads include both backends."); return; }
  if (process.platform !== "darwin") throw new Error("Prebuilt benchmarks require macOS.");
  const repo = repository(args["--repo"]);
  const requested = args["--release"] ?? "latest";
  if (requested !== "latest") tag(requested);
  const jobs = plan("build", parseArgs("build", ["--suite", args["--suite"] ?? "all", "--app", args["--app"] ?? "all"]));
  // Resolve latest exactly once; all subsequent downloads use this snapshot's asset IDs/digests.
  const release = JSON.parse(command("gh", ["api", `repos/${repo}/releases/${requested === "latest" ? "latest" : `tags/${encodeURIComponent(requested)}`}`]));
  if (release.draft || !Array.isArray(release.assets)) throw new Error("Select a published benchmark release.");
  const apiAssets: GitHubAsset[] = release.assets;
  const buildRoot = resolve(repositoryRoot, ".build");
  mkdirSync(buildRoot, { recursive: true });
  const staging = mkdtempSync(resolve(buildRoot, "release-download-"));
  let keepStaging = false;
  try {
    const manifestPath = resolve(staging, manifestName);
    fetchAsset(repo, apiAssets.find(asset => asset.name === manifestName), manifestPath);
    const manifest = readManifest(manifestPath);
    if (manifest.tag !== release.tag_name || (requested !== "latest" && manifest.tag !== requested)) throw new Error("Release tag and manifest differ.");
    if (manifest.arch !== process.arch) throw new Error(`Release requires ${manifest.arch}; this Bun process uses ${process.arch}.`);
    if (!compatibleOS(command("/usr/bin/sw_vers", ["-productVersion"]), manifest.minimumMacOS)) throw new Error(`Release requires macOS ${manifest.minimumMacOS} or newer.`);
    if (cleanCommit(repositoryRoot) !== manifest.comparisonCommit) throw new Error(`Use a clean checkout at ${manifest.comparisonCommit} (release ${manifest.tag}), then run this downloader there.`);
    const identity: ReleaseIdentity = { repository: repo, tag: manifest.tag, manifestSha256: hashFile(manifestPath), comparisonCommit: manifest.comparisonCommit, bundles: {} };
    const replacements: { staged: string; destination: string }[] = [];
    for (const job of jobs) {
      const selected = job.apps.map(app => manifest.assets.find(asset => asset.suite === job.suite && asset.app === app)!);
      if (job.suite === "chat-history") verifyRenderingInputs({ ...Object.fromEntries(selected.map(asset => [asset.app, asset.build.renderingInputs])), currentPolicy: renderingInputs(repositoryRoot, "policy") });
      const destination = resolve(buildRoot, `${job.suite}-benchmarks`);
      const oldManifestPath = resolve(destination, "build-manifest.json");
      const local = existsSync(oldManifestPath) ? JSON.parse(readFileSync(oldManifestPath, "utf8")) : { version: 1, builds: {} };
      for (const asset of selected) {
        const archive = resolve(staging, asset.name);
        fetchAsset(repo, apiAssets.find(item => item.name === asset.name), archive);
        if (statSync(archive).size !== asset.bytes || hashFile(archive) !== asset.sha256) throw new Error(`Manifest checksum mismatch: ${asset.name}`);
        const extracted = resolve(staging, `${asset.suite}-${asset.app}`);
        command("python3", [resolve(import.meta.dir, "archive.py"), "extract", archive, extracted, bundleName(asset.suite, asset.app)]);
        const bundle = resolve(extracted, bundleName(asset.suite, asset.app));
        if (bundleHash(bundle) !== asset.bundleSha256) throw new Error(`Extracted bundle differs: ${asset.name}`);
        command("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle]);
        replacements.push({ staged: bundle, destination: resolve(destination, bundleName(asset.suite, asset.app)) });
        const key = buildKey(asset.suite, asset.app);
        const previous: BuildRecord | undefined = local.builds[key];
        const releaseIdentity: ReleaseIdentity = { ...identity, bundles: { ...(selected.some(item => buildKey(item.suite, item.app) === key && item.app !== asset.app) && previous?.release?.manifestSha256 === identity.manifestSha256 ? previous.release.bundles : {}), [asset.app]: { archiveSha256: asset.sha256, bundleSha256: asset.bundleSha256 } } };
        local.builds[key] = { ...asset.build, release: releaseIdentity };
      }
      const nextManifest = resolve(staging, `${job.suite}-build-manifest.json`);
      writeFileSync(nextManifest, JSON.stringify(local, null, 2) + "\n");
      replacements.push({ staged: nextManifest, destination: oldManifestPath });
    }
    // All downloads, hashes, signatures and provenance checks have passed before any replacement.
    console.log(`Installing ${replacements.length - jobs.length} apps from ${repo}@${manifest.tag}`);
    try { installTransaction(replacements, resolve(staging, "backups")); }
    catch (error) { keepStaging = true; throw new Error(`Install failed; rollback attempted. Recovery files retained at ${staging}. ${error}`); }
    console.log(`Installed verified builds. Run bun run benchmark:run with the same --suite/--app selection.\nRelease: https://github.com/${repo}/releases/tag/${manifest.tag}`);
  } finally { if (!keepStaging) rmSync(staging, { recursive: true, force: true }); }
}
if (import.meta.main) {
  try { await main(); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
}
