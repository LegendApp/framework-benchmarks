import { dirname, join, resolve } from "node:path";

export function externalGrammarRoot(executable: string, override?: string) {
  if (override) return resolve(override);
  let path = executable;
  while (dirname(path) !== path) {
    if (path.endsWith(".app")) return join(dirname(path), "grammar-packs/v1");
    path = dirname(path);
  }
  // Dev commands are run from their app directory; production resolves beside .app.
  return resolve("../../.build/chat-history-benchmarks/grammar-packs/v1");
}
