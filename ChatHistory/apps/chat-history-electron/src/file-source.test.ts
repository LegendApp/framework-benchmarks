import { test, expect } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync, truncateSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FileSource } from "./file-source";
import { parseJsonRange } from "./json-range";

test("file ranges decode Unicode and escapes across blocks and after eviction", () => {
  const root = mkdtempSync(join(tmpdir(), "chat-file-source-"));
  const path = join(root, "source");
  const value = "x".repeat(65524) + "🌍\\\n" + "z".repeat(700000);
  const json = JSON.stringify({ text: value, ignored: [true, null] });
  writeFileSync(path, json);
  const source = new FileSource(path);
  try {
    const range = parseJsonRange(source).object()!.text;
    expect(range.string()).toBe(value);
    expect(source.at(source.length - 1)).toBe(125);
    expect(range.string()).toBe(value);
    source.close();
    expect(() => range.string()).toThrow("closed");
  } finally { source.close(); rmSync(root, { recursive: true }); }
});

test("empty files and truncated unread ranges do not loop or expose uninitialized bytes", () => {
  const root = mkdtempSync(join(tmpdir(), "chat-file-source-"));
  const path = join(root, "source");
  writeFileSync(path, "");
  const empty = new FileSource(path);
  expect(empty.length).toBe(0);
  empty.close();
  writeFileSync(path, Buffer.alloc(70000, 120));
  const source = new FileSource(path);
  try {
    truncateSync(path, 0);
    expect(() => source.at(65536)).toThrow("truncated");
  } finally { source.close(); rmSync(root, { recursive: true }); }
});
