import { resolve } from "node:path";

export const repositoryRoot = resolve(import.meta.dir, "../..");
export const buildRoot = resolve(repositoryRoot, ".build/hello-world-benchmarks");
export const labels = {
  "react-native": "React Native",
  "legend-shell": "Legend Shell",
  electron: "Electron",
  tauri: "Tauri",
  "deno-webview": "Deno WebView",
  "deno-cef": "Deno CEF",
  flutter: "Flutter",
  gpui: "GPUI",
  compose: "Compose Multiplatform",
  swiftui: "SwiftUI",
  appkit: "AppKit",
} as const;
export type AppName = keyof typeof labels;
// Retain the legacy label for archived results, but exclude the duplicate RN host.
export const allApps: AppName[] = (Object.keys(labels) as AppName[]).filter(app => app !== "legend-shell");
export const bundlePath = (app: AppName) => resolve(buildRoot, `Hello World — ${labels[app]}.app`);

export function option(name: string, args = process.argv.slice(2)) {
  const equals = args.find((arg) => arg.startsWith(`${name}=`));
  if (equals) return equals.slice(name.length + 1);
  const index = args.indexOf(name);
  if (index < 0) return undefined;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`Missing value for ${name}`);
  return value;
}

export function selectedApps(args = process.argv.slice(2)): AppName[] {
  const value = option("--app", args) ?? "all";
  if (value === "all") return allApps;
  if (value === "deno") return ["deno-webview", "deno-cef"];
  const requested = value.split(",") as AppName[];
  if (requested.every((app) => allApps.includes(app))) return [...new Set(requested)];
  throw new Error(`Unknown app: ${value}. Choose ${allApps.join(", ")}, deno, or all.`);
}

export function integerOption(name: string, fallback: number, minimum: number) {
  const value = option(name);
  if (value === undefined) return fallback;
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) < minimum) {
    throw new Error(`${name} must be an integer >= ${minimum}`);
  }
  return Number(value);
}
