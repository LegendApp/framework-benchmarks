import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

export type BuildEnvironment = { architecture: string; macOS: string; tools: Record<string, string> };
export function buildEnvironment(repositoryRoot: string, target: string): BuildEnvironment {
  const run = (command: string, args: string[]) => execFileSync(command, args, { encoding: "utf8", cwd: repositoryRoot, stdio: ["ignore", "pipe", "pipe"] }).trim();
  const tools: Record<string, string> = { bun: Bun.version, xcode: run("/usr/bin/xcodebuild", ["-version"]) };
  if (["gpui", "tauri"].includes(target)) tools.rust = run(resolve(repositoryRoot, "scripts/with-local-rust.sh"), ["rustc", "--version"]);
  if (target.startsWith("deno")) tools.deno = run(resolve(repositoryRoot, "scripts/with-local-deno.sh"), ["deno", "--version"]);
  if (target === "flutter") tools.flutter = run(resolve(repositoryRoot, "scripts/with-local-flutter.sh"), ["flutter", "--version"]);
  if (["react-native", "legend-shell"].includes(target)) tools.cocoapods = run("pod", ["--version"]);
  if (target === "compose") tools.composeToolchain = "Compose 1.10.3; Kotlin 2.3.10; Gradle 8.14.3; Temurin 21.0.8+9 ARM64 (pinned local toolchain)";
  return { architecture: process.arch, macOS: run("/usr/bin/sw_vers", ["-productVersion"]), tools };
}
