import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { getRecentChats } from "./catalog";

test("returns an empty catalog when neither provider is installed", async () => {
  const home = await mkdtemp(join(tmpdir(), "legend-electron-empty-catalog-"));
  try {
    const result = await getRecentChats(20, home);
    expect(result.summaries).toEqual([]);
  } finally {
    await rm(home, { force: true, recursive: true });
  }
});

test("discovers indexed sessions while excluding subagents", async () => {
  const home = await mkdtemp(join(tmpdir(), "legend-electron-catalog-"));
  try {
    const codexRoot = join(home, ".codex", "sessions");
    const claudeRoot = join(home, ".claude", "projects", "demo");
    await mkdir(codexRoot, { recursive: true });
    await mkdir(claudeRoot, { recursive: true });

    const codexId = "11111111-1111-1111-1111-111111111111";
    const codexPath = join(codexRoot, `rollout-2026-01-01-${codexId}.jsonl`);
    await writeFile(codexPath, "{\"body\":\"catalog must not parse this\"}\n");
    await writeFile(
      join(home, ".codex", "session_index.jsonl"),
      `{\"id\":\"${codexId}\",\"thread_name\":\"Indexed Codex\",\"updated_at\":\"2026-01-01T10:00:00Z\"}\n`,
    );

    const subagentId = "22222222-2222-2222-2222-222222222222";
    await writeFile(
      join(codexRoot, `rollout-2026-01-02-${subagentId}.jsonl`),
      `{\"payload\":{\"source\":{\"subagent\":{\"thread_spawn\":{\"parent_thread_id\":\"${codexId}\"}}}},\"type\":\"session_meta\"}\n`,
    );

    const claudeId = "33333333-3333-3333-3333-333333333333";
    const claudePath = join(claudeRoot, `${claudeId}.jsonl`);
    await writeFile(claudePath, "{\"body\":\"catalog must not parse this either\"}\n");
    await writeFile(
      join(claudeRoot, "sessions-index.json"),
      JSON.stringify({
        entries: [{
          fullPath: claudePath,
          modified: "2026-01-03T10:00:00Z",
          sessionId: claudeId,
          summary: "Indexed Claude",
        }],
        version: 1,
      }),
    );

    const result = await getRecentChats(20, home);

    expect(result.nativeTotalMs).toBeGreaterThanOrEqual(0);
    expect(result.summaries.map((summary) => summary.title)).toEqual([
      "Indexed Claude",
      "Indexed Codex",
    ]);
    expect(result.summaries.some((summary) => summary.id === `codex:${subagentId}`)).toBe(false);
    expect((await getRecentChats(0, home)).summaries).toEqual([]);
  } finally {
    await rm(home, { force: true, recursive: true });
  }
});

test("subagent filtering ignores a UTF-8 character split after the first line", async () => {
  const home = await mkdtemp(join(tmpdir(), "legend-catalog-boundary-"));
  try {
    const root = join(home, ".codex/sessions");
    await mkdir(root, { recursive: true });
    const header = Buffer.from('{"payload":{"source":{"subagent":{}}}}\n');
    const source = Buffer.concat([header, Buffer.alloc(65535 - header.length, 120), Buffer.from("é")]);
    await writeFile(join(root, "rollout-2026-01-01-22222222-2222-2222-2222-222222222222.jsonl"), source);
    expect((await getRecentChats(20, home)).summaries).toEqual([]);
  } finally { await rm(home, { recursive: true, force: true }); }
});
