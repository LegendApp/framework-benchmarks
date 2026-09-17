import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export const renderingContract = {
  version: 1,
  objective: "Comparable visible features with idiomatic platform rendering engines.",
  sharedLibraries: "React Native and web hosts must use identical Legend List DOM artifacts from the same snapshot.",
  preparation: "Lazy documents and viewport-driven Markdown; retain normal framework prefetch and row caches. Do not pre-render the full history or preload persistent highlighting results.",
  configurableBufferPoints: 250,
  nativePrefetch: "Flutter's indexed list retains its two-viewport minimum; AppKit and SwiftUI retain framework-controlled preparation. Equal offscreen row counts are not claimed.",
  highlighting: "Explicit fence languages, common language and fallback policy, foreground-only colors; idiomatic engines may produce different token boundaries.",
  codeText: "Remove terminal newline characters only; preserve spaces, tabs and internal blank lines.",
  scope: "Pinned text-only transcripts; images disabled. Full Markdown extension conformance and pixel identity are not claimed.",
} as const;

export type RenderingInputs = {
  contractSha256: string;
  highlightingPolicySha256: string;
  legendList?: { version: string; artifacts: Record<string, string> };
};

const webTargets = new Set(["electron", "tauri", "deno", "deno-webview", "deno-cef"]);
const hash = (value: string | Buffer) => createHash("sha256").update(value).digest("hex");

export function renderingInputs(repositoryRoot: string, target: string, rnRoot?: string): RenderingInputs {
  const result: RenderingInputs = {
    contractSha256: hash(JSON.stringify(renderingContract)),
    highlightingPolicySha256: hash(readFileSync(resolve(repositoryRoot, "benchmarks/chat-history/syntax-highlighting-policy.json"))),
  };
  if (target === "react-native" || webTargets.has(target)) {
    const packageRoot = resolve(target === "react-native" ? rnRoot ?? repositoryRoot : repositoryRoot, "packages/legend-list-sparse-layout");
    const metadata = JSON.parse(readFileSync(resolve(packageRoot, "package.json"), "utf8"));
    result.legendList = {
      version: metadata.version,
      artifacts: Object.fromEntries(["react.js", "react.mjs", "react.d.ts"].map((file) => [file, hash(readFileSync(resolve(packageRoot, file)))])),
    };
  }
  return result;
}

export function verifyRenderingInputs(records: Record<string, RenderingInputs | undefined>) {
  let sharedList: string | undefined;
  let contract: string | undefined;
  let highlighting: string | undefined;
  for (const [target, record] of Object.entries(records)) {
    if (!record) throw new Error(`Missing rendering provenance for ${target}; rebuild the selected apps.`);
    contract ??= record.contractSha256;
    highlighting ??= record.highlightingPolicySha256;
    if (record.contractSha256 !== contract || record.highlightingPolicySha256 !== highlighting) {
      throw new Error(`Rendering policy differs for ${target}; rebuild all selected apps under one policy.`);
    }
    if (target === "react-native" || webTargets.has(target)) {
      if (!record.legendList) throw new Error(`Missing Legend List provenance for ${target}; rebuild it.`);
      const identity = JSON.stringify([record.legendList.version, Object.entries(record.legendList.artifacts).sort()]);
      sharedList ??= identity;
      if (identity !== sharedList) throw new Error(`Legend List snapshot differs for ${target}; align the shared dependency and rebuild before comparing.`);
    }
  }
}
