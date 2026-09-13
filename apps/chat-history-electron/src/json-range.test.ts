import { expect, test } from "bun:test";
import { parseJsonRange } from "./json-range";
import { openChatFile, parseChatText } from "./parser";
import { normalizedContentDigest } from "./model";
import { readFile } from "node:fs/promises";
import { DocumentRegistry } from "./document-registry";
import { RowLoader } from "./row-loader";

test("range JSON validates skipped values and decodes escaped strings", () => {
  const value = parseJsonRange(
    Buffer.from('{"ignored":[null,true,-1.2e+3,{"x":"\\u263a"}],"text":"a\\nb"}'),
  );
  expect(value.object()?.text.string()).toBe("a\nb");
  for (
    const source of [
      '{"skip":[1,]}',
      '{"skip":"\\q"}',
      '{"skip":01}',
      "[false true]",
      '{"skip":1} trailing',
    ]
  ) {
    expect(() => parseJsonRange(Buffer.from(source))).toThrow();
  }
});

for (const provider of ["codex", "claude"] as const) {
  test(`${provider} deferred production parser matches eager reference`, async () => {
    const path =
      new URL(`../../../packages/chat-history/tests/fixtures/${provider}.jsonl`, import.meta.url)
        .pathname;
    const document = await openChatFile(provider, path);
    const reference = parseChatText(provider, await readFile(path, "utf8"));
    expect(document.rows).toEqual(reference.rows);
    expect(document.warningCount).toBe(reference.warningCount);
    const registry = new DocumentRegistry();
    const descriptor = await registry.request({ op: "open", provider, path }) as typeof document;
    expect(descriptor.rows.every((row) => row.deferred && !row.markdown && !row.toolPreview)).toBe(
      true,
    );
    const tool = reference.rows.findIndex((row) => row.kind === "tool" && row.toolPreview);
    if (tool >= 0) {
      const collapsed = await registry.request({ op: "rows", documentId: descriptor.documentId!, indices: [tool] }) as typeof document.rows;
      expect(collapsed[0].toolPreview).toBe("");
      const expanded = await registry.request({ op: "rows", documentId: descriptor.documentId!, indices: [tool], includeToolPreview: true }) as typeof document.rows;
      expect(expanded[0].toolPreview).toBe(reference.rows[tool].toolPreview);
    }
    await expect(registry.request({ op: "rows", documentId: descriptor.documentId!, indices: [document.rows.length] })).rejects.toThrow("Invalid row request");
    const requests: number[][] = [];
    const loader = new RowLoader(descriptor, async (documentId, indices) => {
      requests.push(indices);
      return await registry.request({ op: "rows", documentId, indices }) as typeof document.rows;
    });
    const rows = await Promise.all([loader.get(0), loader.get(1), loader.get(0)]);
    expect(requests).toEqual([[0, 1]]);
    expect(rows[0]).toEqual(reference.rows[0]);
    expect(await registry.request({ op: "digest", documentId: descriptor.documentId! })).toBe(
      normalizedContentDigest(reference.rows),
    );
    await registry.request({ op: "open", provider, path });
    await expect(registry.request({ op: "rows", documentId: descriptor.documentId!, indices: [0] }))
      .rejects.toThrow("no longer open");
  });
}
