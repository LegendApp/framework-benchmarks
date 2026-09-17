import { command } from "./shared";

export function options(args: string[], names: string[], flags: string[] = []) {
  const result: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const [name, ...rest] = args[i].split("=");
    if (Object.hasOwn(result, name)) throw new Error(`Repeated option: ${name}`);
    if (["--help", ...flags].includes(name) && !rest.length) { result[name] = "true"; continue; }
    if (!names.includes(name)) throw new Error(`Unknown option: ${args[i]}. Use --help.`);
    const value = rest.length ? rest.join("=") : args[++i];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for ${name}`);
    result[name] = value;
  }
  return result;
}
export function repository(explicit?: string) {
  let value = explicit ?? process.env.BENCHMARK_RELEASE_REPO;
  if (!value) {
    try {
      const origin = command("git", ["remote", "get-url", "origin"]);
      value = origin.match(/github\.com[:/]([^/]+\/[^/]+?)(?:\.git)?$/)?.[1];
    } catch { /* A checkout without a remote must supply a destination. */ }
  }
  if (!value || !/^[\w.-]+\/[\w.-]+$/.test(value)) throw new Error("Specify --repo owner/repo or BENCHMARK_RELEASE_REPO (no GitHub origin found).");
  return value;
}
export function tag(value?: string) {
  if (!value || !/^[\w.-]+$/.test(value) || value.startsWith("-") || value === "." || value === ".." || value === "latest") throw new Error("Supply --tag with a fixed release tag (letters, digits, dots, underscores, hyphens; not latest).");
  return value;
}
