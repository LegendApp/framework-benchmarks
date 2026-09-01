import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { openChatFile, parseChatText } from "./parser";
import { normalizedContentDigest } from "./model";

const fixtures = join(
  fileURLToPath(new URL(".", import.meta.url)),
  "../../../packages/chat-history/tests/fixtures",
);

describe("Electron native transcript parser", () => {
  test("normalizes Codex history", async () => {
    const path = join(fixtures, "codex.jsonl");
    const result = parseChatText("codex", await readFile(path, "utf8"));
    const fileResult = await openChatFile("codex", path);

    expect(result.recordCount).toBe(14);
    expect(result.warningCount).toBe(2);
    expect(result.rows.map((row) => row.kind)).toEqual(["user", "tool", "assistant", "files"]);
    expect(result.rows[0].markdown).toBe("Hello ☺\nworld\n");
    expect(result.rows[1].toolName).toBe("Worked for 4s");
    expect(result.rows[1].toolPreview).toBe("Read files, created an image");
    expect(result.rows[2].markdown).toBe("Done **quickly**.\n\n```text\n::git-commit{example}\n```");
    expect(result.rows[3].fileChanges).toEqual([
      { additions: 3, deletions: 2, path: "apps/demo.ts" },
      { additions: 1, deletions: 0, path: "packages/helper.ts" },
      { additions: 0, deletions: 2, path: "packages/old.ts" },
    ]);
    expect(fileResult.rows).toEqual(result.rows);
    expect(fileResult.recordCount).toBe(result.recordCount);
    expect(fileResult.warningCount).toBe(result.warningCount);
    expect(normalizedContentDigest(result.rows)).toBe("ea203684aeae72fb");
  });

  test("selects and normalizes Claude's latest main chain", async () => {
    const result = parseChatText("claude", await readFile(join(fixtures, "claude.jsonl"), "utf8"));

    expect(result.recordCount).toBe(8);
    expect(result.warningCount).toBe(1);
    expect(result.rows.map((row) => row.kind)).toEqual(["user", "tool", "assistant"]);
    expect(result.rows[0].markdown).toBe("Start here");
    expect(result.rows[1].toolName).toBe("Worked for 3s");
    expect(result.rows[1].toolPreview).toBe("I will check.\n\nRead files");
    expect(result.rows[2].markdown).toBe("Latest answer");
    expect(result.rows[2].hasImagePlaceholder).toBe(true);
    expect(normalizedContentDigest(result.rows)).toBe("4cb20d4c68d78408");
  });

  test("uses response-item user turns when current Codex files omit event messages", () => {
    const result = parseChatText("codex", [
      JSON.stringify({
        payload: {
          content: [{ text: "Current-format request", type: "input_text" }],
          role: "user",
          type: "message",
        },
        timestamp: "2026-08-28T00:00:00.000Z",
        type: "response_item",
      }),
      JSON.stringify({
        payload: {
          content: [{ text: "Current-format answer", type: "output_text" }],
          role: "assistant",
          type: "message",
        },
        timestamp: "2026-08-28T00:00:01.000Z",
        type: "response_item",
      }),
    ].join("\n"));

    expect(result.rows.map((row) => [row.kind, row.markdown])).toEqual([
      ["user", "Current-format request"],
      ["assistant", "Current-format answer"],
    ]);
  });
});
