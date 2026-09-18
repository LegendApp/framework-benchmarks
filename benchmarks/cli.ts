import { verifyAppGrammarPack } from "./chat-history/grammar-packs";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { allApps, labels, type AppName, repositoryRoot } from "./hello-world/config";
import { renderingInputs, verifyRenderingInputs, type RenderingInputs } from "./chat-history/fairness";

import { assertReleaseSet, type BuildRecord } from "./releases/shared";

export type Mode = "build" | "run";
export type Suite = "chat-history" | "hello-world";
export type Options = {
  suite: "all" | Suite; apps: AppName[]; yes: boolean; dryRun: boolean; help: boolean;
  legendRepo: string; iterations: number; warmups: number; settleMs: number;
};
const suites: Suite[] = ["chat-history", "hello-world"];

export function parseArgs(mode: Mode, args: string[]): Options {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  const valueNames = ["--suite", "--app", ...(mode === "build" ? ["--legend-apps-repo"] : ["--iterations", "--warmups", "--settle-ms"])];
  const flagNames = ["--help", "--dry-run", ...(mode === "build" ? ["--yes"] : [])];
  for (let i = 0; i < args.length; i++) {
    const [name, ...rest] = args[i].split("=");
    if (flagNames.includes(name) && !rest.length) { flags.add(name); continue; }
    if (!valueNames.includes(name)) throw new Error(`Unknown argument: ${args[i]}. Use --help.`);
    if (values.has(name)) throw new Error(`Repeated argument: ${name}`);
    const value = rest.length ? rest.join("=") : args[++i];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for ${name}`);
    values.set(name, value);
  }
  const suite = values.get("--suite") ?? "all";
  if (suite !== "all" && !suites.includes(suite as Suite)) throw new Error(`Unknown suite: ${suite}`);
  const rawApps = values.get("--app") ?? "all";
  const apps = rawApps === "all" ? allApps : [...new Set(rawApps.split(",").flatMap(app => app === "deno" ? ["deno-webview", "deno-cef"] : [app]))];
  if (!apps.length || apps.some(app => !allApps.includes(app as AppName))) throw new Error(`Unknown app: ${rawApps}. Use --help.`);
  if (suite === "chat-history" && apps.includes("legend-shell") && rawApps !== "all") throw new Error("legend-shell is only available in the hello-world suite.");
  const integer = (name: string, fallback: number, minimum: number) => {
    const raw = values.get(name);
    if (raw === undefined) return fallback;
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(Number(raw)) || Number(raw) < minimum) throw new Error(`${name} must be an integer >= ${minimum}`);
    return Number(raw);
  };
  if (suite === "chat-history" && values.has("--settle-ms")) throw new Error("--settle-ms only applies to hello-world.");
  return {
    suite: suite as Options["suite"], apps: apps as AppName[], yes: flags.has("--yes"), dryRun: flags.has("--dry-run"), help: flags.has("--help"),
    legendRepo: resolve(values.get("--legend-apps-repo") ?? process.env.LEGEND_APPS_REPO ?? resolve(repositoryRoot, "../legend-apps")),
    iterations: integer("--iterations", 10, 1), warmups: integer("--warmups", 2, 0), settleMs: integer("--settle-ms", 5000, 1000),
  };
}

export function plan(mode: Mode, options: Options) {
  return suites.filter(suite => options.suite === "all" || options.suite === suite).flatMap(suite => {
    let apps = options.apps.filter(app => suite !== "chat-history" || app !== "legend-shell");
    if (!apps.length) return [];
    // The product exporter packages both Deno backends as one build target.
    if (mode === "build" && suite === "chat-history" && apps.some(app => app.startsWith("deno-"))) {
      apps = [...new Set([...apps, "deno-webview", "deno-cef"])] as AppName[];
    }
    const targets = mode === "build" && suite === "chat-history"
      ? [...new Set(apps.map(app => app.startsWith("deno-") ? "deno" : app))] : apps;
    const args = [resolve(repositoryRoot, `benchmarks/${suite}/${mode}.ts`), "--app", targets.join(",")];
    if (mode === "build") {
      args.push(suite === "chat-history" ? "--react-native-repo" : "--legend-apps-repo", options.legendRepo);
    } else {
      args.push("--warmups", String(options.warmups), "--iterations", String(options.iterations));
      if (suite === "hello-world") args.push("--settle-ms", String(options.settleMs));
    }
    return [{ suite, apps, args }];
  });
}

export function preflightBuilds(jobs: ReturnType<typeof plan>, root = repositoryRoot) {
  const releaseRecords: { app: string; bundle: string; build: BuildRecord }[] = [];
  for (const job of jobs) {
    const directory = resolve(root, `.build/${job.suite}-benchmarks`);
    const manifestPath = resolve(directory, "build-manifest.json");
    if (!existsSync(manifestPath)) throw new Error(`Missing ${manifestPath}. Run benchmark:build first.`);
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    const inputs: Record<string, RenderingInputs | undefined> = {};
    for (const app of job.apps) {
      const bundle = resolve(directory, `${job.suite === "chat-history" ? "Chat History" : "Hello World"} — ${labels[app]}.app`);
      const key = job.suite === "chat-history" && app.startsWith("deno-") ? "deno" : app;
      if (!existsSync(resolve(bundle, "Contents/Info.plist")) || !manifest.builds?.[key]) {
        throw new Error(`Missing build or provenance for ${job.suite}/${app}. Run benchmark:build --suite ${job.suite} --app ${app}.`);
      }
      if (job.suite === "chat-history") verifyAppGrammarPack(root, app, manifest.builds[key].grammarPack);
      inputs[app] = manifest.builds[key].renderingInputs;
      releaseRecords.push({ app, bundle, build: manifest.builds[key] });
    }
    if (job.suite === "chat-history") {
      verifyRenderingInputs({ ...inputs, currentPolicy: renderingInputs(root, "policy") });
      if (!existsSync(resolve(root, "benchmarks/chat-history/fixtures.local.json"))) throw new Error("Missing pinned chat fixtures. Run bun run benchmark:fixtures first.");
    }
  }
  assertReleaseSet(releaseRecords, root);
}

export function help(mode: Mode) {
  return `Usage: bun run benchmark:${mode} [options]

${mode === "build" ? "Build release apps after showing the plan and asking for confirmation." : "Benchmark existing release apps; never build application bundles."}
No arguments selects both workloads and all 20 apps.

  --suite all|chat-history|hello-world   Default: all
  --app all|<comma-separated apps>      Default: all
  --dry-run                            Print commands without executing
  --help                               Show this help
${mode === "build" ? `  --yes                                Skip interactive confirmation (automation)
  --legend-apps-repo <path>             Default: LEGEND_APPS_REPO or ../legend-apps` : `  --iterations <N>                     Measured rounds per app (default: 10, min: 1)
  --warmups <N>                        Discarded rounds per app (default: 2, min: 0)
  --settle-ms <N>                      Hello World reference wait (default: 5000, min: 1000)`}

Apps: ${allApps.join(", ")}
Alias: deno selects both backends.
Chat-history Deno builds always produce both backends.
`;
}

export async function main(mode: Mode, args = process.argv.slice(2)) {
  const options = parseArgs(mode, args);
  if (options.help) { console.log(help(mode)); return; }
  const jobs = plan(mode, options);
  console.log(`${mode === "build" ? "Build" : "Benchmark"} plan (${jobs.reduce((n, job) => n + job.apps.length, 0)} apps):`);
  for (const job of jobs) {
    console.log(`\n${job.suite}: ${job.apps.join(", ")}`);
    console.log(`  Bundles: ${resolve(repositoryRoot, `.build/${job.suite}-benchmarks`)}`);
    console.log(`  Command: ${[process.execPath, ...job.args].map(value => JSON.stringify(value)).join(" ")}`);
  }
  if (mode === "build") {
    console.log(`\nLegend Apps source: ${options.legendRepo}`);
    console.log("Selected bundles will be replaced. Toolchains may download dependencies. Building all apps can take a long time.");
  } else {
    console.log(`\n${options.warmups} warmups + ${options.iterations} measured rounds per app; video timing and separate memory launches.`);
    console.log("Keep the Mac unlocked and idle. Both full suites can take over an hour. Reports and videos: benchmarks/<suite>/results/.");
  }
  if (options.dryRun) return;
  if (process.platform !== "darwin") throw new Error("These desktop suites require macOS.");
  if (mode === "build" && !options.yes) {
    if (!process.stdin.isTTY) throw new Error("Confirmation requires an interactive terminal. Review --dry-run, then use --yes for automation.");
    const prompt = createInterface({ input: process.stdin, output: process.stdout });
    let answer: string;
    try { answer = await prompt.question("\nStart building? [y/N] "); } finally { prompt.close(); }
    if (!/^y(es)?$/i.test(answer.trim())) { console.log("Build cancelled; no apps built."); return; }
  }
  if (mode === "run") preflightBuilds(jobs);
  for (const job of jobs) {
    // Keep the display awake during both suites, including the chat runner.
    const command = mode === "run" ? "/usr/bin/caffeinate" : process.execPath;
    const childArgs = mode === "run" ? ["-diu", process.execPath, ...job.args] : job.args;
    const result = spawnSync(command, childArgs, { cwd: repositoryRoot, env: process.env, stdio: "inherit" });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${job.suite} ${mode} failed (${result.signal ?? result.status}); remaining suites were not started.`);
  }
}
