import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { options, repository } from "./options";
import { command, hashFile, manifestName, readManifest } from "./shared";

async function main() {
  const args = options(process.argv.slice(2), ["--directory", "--repo"], ["--draft"]);
  if (args["--help"]) { console.log("Usage: bun run benchmark:release:publish --directory <package-directory> [--repo owner/repo] [--draft]\nVerifies all 19 archives and the existing remote tag, creates a draft, uploads all assets, then publishes unless --draft is set. Never replaces existing releases."); return; }
  if (!args["--directory"]) throw new Error("--directory is required");
  const repo = repository(args["--repo"]);
  const directory = resolve(args["--directory"]);
  const manifest = readManifest(resolve(directory, manifestName));
  for (const asset of [...manifest.assets, ...(manifest.grammarAssets ?? [])]) {
    const path = resolve(directory, asset.name);
    if (statSync(path).size !== asset.bytes || hashFile(path) !== asset.sha256) throw new Error(`Archive checksum mismatch: ${asset.name}`);
  }
  const files = [manifestName, ...manifest.assets.map(asset => asset.name), ...(manifest.grammarAssets ?? []).map(asset => asset.name)];
  const sums = files.map(name => `${hashFile(resolve(directory, name))}  ${name}\n`).join("");
  if (readFileSync(resolve(directory, "SHA256SUMS"), "utf8") !== sums) throw new Error("SHA256SUMS does not match the package.");
  // Resolve the actual tag ref, including annotated tags; never create a tag implicitly.
  let object = JSON.parse(command("gh", ["api", `repos/${repo}/git/ref/tags/${encodeURIComponent(manifest.tag)}`])).object;
  for (let depth = 0; object.type === "tag" && depth < 5; depth++) object = JSON.parse(command("gh", ["api", `repos/${repo}/git/tags/${object.sha}`])).object;
  if (object.type !== "commit" || object.sha !== manifest.comparisonCommit) throw new Error("Remote release tag does not match the packaged source commit. Push the matching tag first.");
  const temp = mkdtempSync(resolve(tmpdir(), "benchmark-release-notes-"));
  try {
    const notes = resolve(temp, "notes.md");
    writeFileSync(notes, `Prebuilt desktop benchmarks: all ${manifest.assets.length} apps, macOS ${manifest.minimumMacOS}+ (${manifest.arch}).\n\nComparison source: ${manifest.comparisonCommit}\nLegend Apps source: ${manifest.legendAppsCommit}\n\nUse the harness at this tag. Run \`bun run benchmark:download --repo ${repo} --release ${manifest.tag}\`, then \`bun run benchmark:run\`.\n\nThese are benchmark builds; notarization is not verified. Private histories are not included. See the README for measurement prerequisites and fixture selection.\n`);
    // Create first: an existing release fails here before any upload can overwrite it.
    command("gh", ["release", "create", manifest.tag, "--repo", repo, "--verify-tag", "--draft", "--title", `Desktop benchmarks ${manifest.tag}`, "--notes-file", notes]);
    command("gh", ["release", "upload", manifest.tag, "--repo", repo, resolve(directory, manifestName), resolve(directory, "SHA256SUMS"), ...[...manifest.assets, ...(manifest.grammarAssets ?? [])].map(asset => resolve(directory, asset.name))]);
    if (!args["--draft"]) command("gh", ["release", "edit", manifest.tag, "--repo", repo, "--draft=false", "--latest"]);
    console.log(`${args["--draft"] ? "Draft created" : "Published"}: https://github.com/${repo}/releases/tag/${manifest.tag}`);
  } finally { rmSync(temp, { recursive: true, force: true }); }
}
try { await main(); } catch (error) { console.error(error instanceof Error ? error.message : error); console.error("If uploading failed after draft creation, the incomplete release remains a draft; inspect it before retrying."); process.exitCode = 1; }
