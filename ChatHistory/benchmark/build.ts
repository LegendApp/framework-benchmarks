import { buildWebGrammarPack, buildSyntectGrammarPack } from "./build-grammar-packs";
import { buildTreeSitterPack } from "./build-tree-sitter-pack";
import { grammarPackRecord, prepareGrammarPack, sealGrammarPack, type GrammarPackRecord } from "./grammar-packs";
import { buildEnvironment, type BuildEnvironment } from "../../benchmarks/build-environment";
import { renderingInputs, verifyRenderingInputs, type RenderingInputs } from "./fairness";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

type BuildTarget =
  | "appkit"
  | "deno"
  | "electron"
  | "flutter"
  | "compose"
  | "gpui"
  | "react-native"
  | "swiftui"
  | "tauri";

type BuildRecord = {
  grammarPack?: GrammarPackRecord;
  environment?: BuildEnvironment;
  renderingInputs?: RenderingInputs;
  builtAt: string;
  gitCommit: string;
  gitDirty: boolean;
  repositoryPath: string;
};

// import.meta.dir is the benchmark folder, where results live; .build/ and the
// toolchain wrappers live at the repository root.
const repositoryRoot = resolve(import.meta.dir, "../..");
const buildRoot = resolve(repositoryRoot, ".build/chat-history-benchmarks");
const buildManifestPath = resolve(buildRoot, "build-manifest.json");
const allTargets: BuildTarget[] = [
  "react-native",
  "electron",
  "tauri",
  "deno",
  "flutter",
  "gpui",
  "compose",
  "swiftui",
  "appkit",
];

function option(name: string) {
  const equals = process.argv.find((argument) => argument.startsWith(`${name}=`));
  if (equals) {
    return equals.slice(name.length + 1);
  }
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function run(command: string, args: string[], cwd = repositoryRoot) {
  console.log(`\n$ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, {
    cwd,
    env: process.env,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function hasExporter(path: string) {
  try {
    const packageJson = JSON.parse(readFileSync(resolve(path, "package.json"), "utf8")) as {
      scripts?: Record<string, string>;
    };
    return typeof packageJson.scripts?.["chat-history:benchmark:export"] === "string";
  } catch {
    return false;
  }
}

function mainWorktree(path: string) {
  try {
    const output = execFileSync("git", ["-C", path, "worktree", "list", "--porcelain"], {
      encoding: "utf8",
    });
    let worktree: string | undefined;
    for (const line of output.split("\n")) {
      if (line.startsWith("worktree ")) {
        worktree = line.slice("worktree ".length);
      } else if (line === "branch refs/heads/main" && worktree && hasExporter(worktree)) {
        return worktree;
      }
    }
  } catch {
    return undefined;
  }
  return undefined;
}

function reactNativeRepository() {
  const explicit = option("--react-native-repo") ?? process.env.LEGEND_APPS_REPO;
  if (explicit) {
    const path = resolve(explicit);
    if (!hasExporter(path)) {
      throw new Error(
        `React Native repository at ${path} does not expose chat-history:benchmark:export`,
      );
    }
    return path;
  }

  const sibling = resolve(repositoryRoot, "../legend-apps");
  let siblingBranch: string | undefined;
  try {
    siblingBranch = execFileSync("git", ["-C", sibling, "branch", "--show-current"], {
      encoding: "utf8",
    }).trim();
  } catch {
    siblingBranch = undefined;
  }
  if (siblingBranch === "main" && hasExporter(sibling)) {
    return sibling;
  }
  const main = existsSync(sibling) ? mainWorktree(sibling) : undefined;
  if (main) {
    return main;
  }
  if (hasExporter(sibling)) {
    return sibling;
  }
  throw new Error(
    "Could not find legend-apps with chat-history:benchmark:export. " +
    "Set LEGEND_APPS_REPO or pass --react-native-repo <path>.",
  );
}

function selectedTargets(): BuildTarget[] {
  const app = option("--app") ?? "all";
  if (app === "all") {
    return allTargets;
  }
  if (app === "deno-cef" || app === "deno-webview") {
    return ["deno"];
  }
  const requested = [...new Set(app.split(","))] as BuildTarget[];
  if (requested.every((target) => allTargets.includes(target))) {
    return requested;
  }
  throw new Error(`Unknown build target: ${app}`);
}

function gitRecord(path: string): BuildRecord {
  const git = (...args: string[]) => execFileSync("git", ["-C", path, ...args], {
    encoding: "utf8",
  }).trim();
  return {
    builtAt: new Date().toISOString(),
    gitCommit: git("rev-parse", "HEAD"),
    gitDirty: git("status", "--porcelain").length > 0,
    repositoryPath: path,
  };
}

function readBuildManifest() {
  try {
    return JSON.parse(readFileSync(buildManifestPath, "utf8")) as {
      builds: Partial<Record<BuildTarget, BuildRecord>>;
      version: 1;
    };
  } catch {
    return { builds: {}, version: 1 as const };
  }
}

const commands: Record<Exclude<BuildTarget, "react-native">, [string, string[]]> = {
  appkit: ["bun", ["run", "chat-history:appkit:build-benchmark"]],
  deno: ["bun", ["--cwd", "ChatHistory/apps/chat-history-deno", "build:benchmark"]],
  electron: ["bun", ["--cwd", "ChatHistory/apps/chat-history-electron", "build:benchmark"]],
  flutter: ["bun", ["run", "chat-history:flutter:build-benchmark"]],
  compose: ["bun", ["shared/compose-desktop/package.ts", "chat-history"]],
  gpui: ["bun", ["run", "chat-history:gpui:build-benchmark"]],
  swiftui: ["bun", ["run", "chat-history:swiftui:build-benchmark"]],
  tauri: ["bun", ["--cwd", "ChatHistory/apps/chat-history-tauri", "build:benchmark"]],
};

const targets = selectedTargets();
const manifest = readBuildManifest();
const rnRoot = targets.includes("react-native") ? reactNativeRepository() : undefined;
const inputRecords = Object.fromEntries(targets.map(target => [target, renderingInputs(repositoryRoot, target, rnRoot)]));
verifyRenderingInputs(inputRecords);
mkdirSync(dirname(buildManifestPath), { recursive: true });
const saveManifest = () => writeFileSync(buildManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
for (const target of targets) {
  delete manifest.builds[target];
  saveManifest(); // A failed replacement must not retain provenance for the previous bundle.
  const environment = buildEnvironment(repositoryRoot, target);
  if (["electron", "tauri", "deno"].includes(target)) await buildWebGrammarPack();
  if (target === "gpui") buildSyntectGrammarPack();
  if (target === "react-native") buildTreeSitterPack(rnRoot!, repositoryRoot);
  if (target === "flutter") {
    const directory = prepareGrammarPack(repositoryRoot, "dart-highlighting");
    run(resolve(repositoryRoot, "scripts/with-local-flutter.sh"), ["flutter", "pub", "get"], resolve(import.meta.dir, "../apps/chat-history-flutter"));
    run(resolve(repositoryRoot, "scripts/with-local-flutter.sh"), ["dart", "run", "scripts/export-grammar-pack.dart", resolve(directory, "grammars.json")], resolve(import.meta.dir, "../apps/chat-history-flutter"));
    sealGrammarPack(directory, "dart-highlighting");
  }
  if (target === "react-native") {
    const sourceRepository = reactNativeRepository();
    const output = resolve(buildRoot, "Chat History — React Native.app");
    run(
      "bun",
      ["run", "chat-history:benchmark:export", "--output", output],
      sourceRepository,
    );
    manifest.builds[target] = { ...gitRecord(sourceRepository), renderingInputs: inputRecords[target], environment };
  } else {
    const [command, args] = commands[target];
    run(command, args);
    manifest.builds[target] = { ...gitRecord(repositoryRoot), renderingInputs: inputRecords[target], environment };
  }
  manifest.builds[target]!.grammarPack = grammarPackRecord(repositoryRoot, target);
  saveManifest();
}

mkdirSync(dirname(buildManifestPath), { recursive: true });
writeFileSync(buildManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`\nBuild manifest: ${buildManifestPath}`);
