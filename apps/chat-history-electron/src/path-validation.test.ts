import { mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateChatPath } from "./path-validation";

test("allows only provider transcript roots", async () => {
  const home = await mkdtemp(join(tmpdir(), "chat-history-electron-"));
  try {
    const codexRoot = join(home, ".codex", "sessions");
    const claudeRoot = join(home, ".claude", "projects");
    await mkdir(codexRoot, { recursive: true });
    await mkdir(claudeRoot, { recursive: true });
    const codexPath = join(codexRoot, "chat.jsonl");
    const claudePath = join(claudeRoot, "chat.jsonl");
    const outsidePath = join(home, "outside.jsonl");
    await Promise.all([
      writeFile(codexPath, "{}\n"),
      writeFile(claudePath, "{}\n"),
      writeFile(outsidePath, "{}\n"),
    ]);

    expect(await validateChatPath("codex", codexPath, home)).toBe(await realpath(codexPath));
    expect(await validateChatPath("claude", claudePath, home)).toBe(await realpath(claudePath));
    await expect(validateChatPath("claude", codexPath, home)).rejects.toThrow(
      "outside the provider history directory",
    );
    await expect(validateChatPath("codex", outsidePath, home)).rejects.toThrow(
      "outside the provider history directory",
    );
  } finally {
    await rm(home, { force: true, recursive: true });
  }
});
