import { readFileSync } from "node:fs";
import { initializeGrammarPack } from "./syntax-highlighting";
await initializeGrammarPack(readFileSync(new URL("../../../.build/chat-history-benchmarks/grammar-packs/v1/highlight-js/grammars.mjs", import.meta.url), "utf8"));
import { expect, test } from "bun:test";
import fixtures from "../../../benchmarks/chat-history/syntax-highlighting-fixtures.json";
import { codePaneSource, highlightCode } from "./syntax-highlighting";

test("every RN language and alias emits tokens without changing source", () => {
  for (const { source, language } of fixtures) {
    const result = highlightCode(source, language);
    expect(result).toContain('class="hljs-');
    const decoded = result.replace(/<[^>]*>/g, "").replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&quot;", '"').replaceAll("&#x27;", "'").replaceAll("&amp;", "&");
    expect(decoded).toBe(source);
    expect(highlightCode(source, language.toUpperCase())).toBe(result);
  }
});
test("unknown, oversized and too many lines stay escaped plain text", () => {
  for (const [source, language] of [["<script>alert('x')</script>", "unknown"], ["a".repeat(51201), "js"], ["😀".repeat(12801), "js"], ["\n".repeat(2000), "js"], ["const x = 1", ""]]) {
    expect(highlightCode(source!, language!)).not.toContain('class="hljs-');
  }
  expect(highlightCode("<script>", "unknown")).toBe("&lt;script&gt;");
});

test("code panes remove all terminal newlines but retain significant whitespace", () => {
  for (const [source, expected] of [["let x = 1;  \n\n", "let x = 1;  "], ["\n  \t\n", "\n  \t"], ["a\n\nb\n", "a\n\nb"], ["\n\n", ""]]) {
    expect(codePaneSource(source!)).toBe(expected!);
  }
});
