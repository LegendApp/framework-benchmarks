import { expect, test } from "bun:test";
import { closeChatDocument, openChatFile } from "../apps/chat-history-electron/src/parser";
import { normalizedContentDigest } from "../apps/chat-history-electron/src/model";
import { prepareFixtures } from "./fixtures";

test("every published sample opens in the shared web parser", async () => {
  const manifest = await prepareFixtures();
  expect(manifest.fixtures.length).toBe(8);
  expect(manifest.fixtures.slice(0, 2).map((fixture) => fixture.sourceBytes)).toEqual([239115823, 148125953]);
  for (const fixture of manifest.fixtures) {
    const document = await openChatFile(fixture.provider, fixture.path);
    try {
      expect(document.sourceBytes).toBe(fixture.sourceBytes);
      expect(document.recordCount).toBeGreaterThan(0);
      expect(document.rows.some((row) => row.kind === "user")).toBe(true);
      expect(document.rows.some((row) => row.kind === "assistant")).toBe(true);
      expect(document.warningCount).toBe(0);
      expect(normalizedContentDigest(document.rows)).toMatch(/^[0-9a-f]{16}$/);
    } finally { closeChatDocument(document); }
  }
}, 120_000);
