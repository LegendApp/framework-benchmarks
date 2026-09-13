import { realpath } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, isAbsolute, join, relative, sep } from "node:path";
import type { ChatProvider } from "./model";

function isWithin(root: string, path: string) {
  const value = relative(root, path);
  return value !== ".." && !value.startsWith(`..${sep}`)
    && !isAbsolute(value);
}

export async function validateChatPath(
  provider: ChatProvider,
  sourcePath: string,
  home = (process.env.CHAT_HISTORY_BENCHMARK_CONFIG && process.env.CHAT_HISTORY_BENCHMARK_HOME) || homedir(),
) {
  if (provider !== "codex" && provider !== "claude") {
    throw new Error("Unsupported chat provider");
  }
  const path = await realpath(sourcePath);
  const roots = provider === "codex"
    ? [join(home, ".codex", "sessions"), join(home, ".codex", "archived_sessions")]
    : [join(home, ".claude", "projects")];
  const canonicalRoots = await Promise.all(roots.map(async (root) => {
    try {
      return await realpath(root);
    } catch {
      return root;
    }
  }));
  if (extname(path) !== ".jsonl" || !canonicalRoots.some((root) => isWithin(root, path))) {
    throw new Error("Transcript path is outside the provider history directory");
  }
  return path;
}
