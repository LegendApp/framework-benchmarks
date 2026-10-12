import { prepareGrammarPack, sealGrammarPack } from "../ChatHistory/benchmark/grammar-packs";
import { cpSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

export function copySwiftResources(appRoot: string, outputApp: string) {
  const release = resolve(appRoot, ".build/release");
  for (const entry of readdirSync(release)) {
    if (!entry.endsWith(".bundle")) continue;
    if (entry === "Highlighter_Highlighter.bundle") {
      const pack = prepareGrammarPack(resolve(import.meta.dir, ".."), "highlighter-swift");
      cpSync(resolve(release, entry), resolve(pack, entry), { recursive: true });
      sealGrammarPack(pack, "highlighter-swift");
    } else cpSync(resolve(release, entry), resolve(outputApp, "Contents/Resources", entry), { recursive: true });
  }
}
