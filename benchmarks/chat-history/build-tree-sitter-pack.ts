import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { prepareGrammarPack, sealGrammarPack } from "./grammar-packs";

export function buildTreeSitterPack(legendRoot: string, root = resolve(import.meta.dir, "../..")) {
  const require = createRequire(resolve(legendRoot, "apps/chat-history/package.json"));
  const dependency = dirname(require.resolve("react-native-enriched-markdown/package.json"));
  const highlight = join(dependency, "cpp/highlight");
  const config = JSON.parse(readFileSync(join(legendRoot, "apps/chat-history/scripts/benchmark-markdown.json"), "utf8"));
  if (!config.externalCodeHighlightGrammars) throw new Error("Legend Apps must support external benchmark grammars");
  const temporary = resolve(root, ".build/grammar-build/tree-sitter");
  mkdirSync(temporary, { recursive: true });
  execFileSync(process.execPath, [join(highlight, "gen-registry.mjs"), "--vendor-dir", join(highlight, "vendor"), "--languages", config.codeHighlightLanguages.join(","), "--out", temporary], { stdio: "inherit" });
  const objects: string[] = [];
  for (const language of config.codeHighlightLanguages as string[]) {
    for (const file of ["parser.c", "scanner.c"]) {
      const source = join(highlight, "vendor/grammars", language, file);
      if (!existsSync(source)) { if (file === "parser.c") throw new Error(`Missing ${source}`); continue; }
      const object = join(temporary, `${language}-${file}.o`);
      execFileSync("xcrun", ["clang", "-O2", "-fPIC", "-c", source, "-I", join(highlight, "vendor/grammars", language), "-o", object], { stdio: "inherit" });
      objects.push(object);
    }
  }
  const bridge = join(temporary, "bridge.cpp");
  writeFileSync(bridge, '#include "HighlightGrammars.hpp"\nextern "C" const Markdown::GrammarEntry *benchmark_find_grammar_v1(const char *id) { return Markdown::findGrammar(id); }\n');
  const pack = prepareGrammarPack(root, "tree-sitter");
  const library = join(pack, "grammars.dylib");
  execFileSync("xcrun", ["clang++", "-std=c++17", "-O2", "-dynamiclib", ...objects, join(temporary, "generated_registry.cpp"), bridge, "-I", highlight, "-I", temporary, "-Wl,-install_name,@rpath/grammars.dylib", "-o", library], { stdio: "inherit" });
  execFileSync("strip", ["-S", "-x", library]);
  execFileSync("codesign", ["--force", "--sign", "-", library], { stdio: "inherit" });
  return sealGrammarPack(pack, "tree-sitter");
}
if (import.meta.main) buildTreeSitterPack(resolve(process.argv[2] ?? resolve(import.meta.dir, "../../../legend-apps")));
