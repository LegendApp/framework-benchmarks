import hljs from "highlight.js/lib/core";
import policy from "../../../benchmark/syntax-highlighting-policy.json";

let ready = false;
export async function initializeGrammarPack(source: string) {
  const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
  try {
    const pack = await import(url);
    if (typeof pack.register !== "function") throw new Error("Invalid external grammar pack");
    pack.register(hljs);
    ready = true;
  } finally { URL.revokeObjectURL(url); }
}

const languages: Record<string, string> = policy.languages;
const encoder = new TextEncoder();
const escape = (source: string) => source.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#x27;");

// Declared language only; the same whole-block fallback bounds as RN.
export function highlightCode(source: string, fence: string): string {
  const language = languages[fence.toLowerCase()];
  if (!language || encoder.encode(source).length > policy.maxBytes || source.split("\n").length > policy.maxLines) return escape(source);
  if (!ready) throw new Error("External highlight.js grammar pack is not initialized");
  return hljs.highlight(source, { language, ignoreIllegals: true }).value;
}

// Match RN code panes: remove parser-supplied trailing newlines, not code whitespace.
export function codePaneSource(source: string): string {
  return source.replace(/\n+$/, "");
}
