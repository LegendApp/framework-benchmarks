import { execFileSync } from "node:child_process";
import { resolve, join } from "node:path";
import { mkdirSync } from "node:fs";
import { prepareGrammarPack, sealGrammarPack } from "./grammar-packs";

const root = resolve(import.meta.dir, "../..");
export async function buildWebGrammarPack() {
  const pack = prepareGrammarPack(root, "highlight-js");
  const result = await Bun.build({ entrypoints: [resolve(root, "apps/chat-history-electron/scripts/grammar-source.ts")], target: "browser", format: "esm", minify: true });
  if (!result.success) throw new Error(result.logs.join("\n"));
  await Bun.write(join(pack, "grammars.mjs"), result.outputs[0]);
  return sealGrammarPack(pack, "highlight-js");
}
export function buildSyntectGrammarPack() {
  const pack = prepareGrammarPack(root, "syntect");
  execFileSync(resolve(root, "scripts/with-local-rust.sh"), ["cargo", "run", "--release", "--manifest-path", resolve(root, "apps/chat-history-gpui/Cargo.toml"), "--features", "grammar-builder", "--bin", "export-grammar-pack", "--", join(pack, "syntaxes.pack")], { stdio: "inherit" });
  return sealGrammarPack(pack, "syntect");
}
if (import.meta.main) {
  const engine = process.argv[2];
  if (engine === "syntect") buildSyntectGrammarPack();
  else if (engine === "highlight-js") await buildWebGrammarPack();
  else throw new Error("Expected highlight-js or syntect");
}
