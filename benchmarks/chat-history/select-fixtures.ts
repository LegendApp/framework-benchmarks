import { createHash } from "node:crypto";
import {
  closeSync,
  createReadStream,
  existsSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, extname, join, resolve, sep } from "node:path";
import type {
  BenchmarkConfig,
  BenchmarkFixture,
  ChatProvider,
} from "../../apps/chat-history-electron/src/model";

const defaultMinimumInactiveDays = 8;
const outputPath = resolve(import.meta.dir, "fixtures.local.json");

function option(name: string) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function jsonlFiles(root: string) {
  const files: string[] = [];
  const directories = [root];
  while (directories.length > 0) {
    const directory = directories.pop()!;
    let entries;
    try {
      entries = readdirSync(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        directories.push(path);
      } else if (entry.isFile() && extname(path) === ".jsonl") {
        files.push(path);
      }
    }
  }
  return files;
}

function edgeLine(path: string, edge: "first" | "last") {
  const handle = openSync(path, "r");
  try {
    const size = statSync(path).size;
    const length = Math.min(size, 256 * 1_024);
    const buffer = Buffer.alloc(length);
    readSync(handle, buffer, 0, length, edge === "first" ? 0 : size - length);
    const lines = buffer.toString("utf8").split("\n").filter(Boolean);
    return edge === "first" ? lines[0] : lines.at(-1);
  } finally {
    closeSync(handle);
  }
}

function recordTimestamp(line: string | undefined) {
  if (!line) {
    return 0;
  }
  try {
    const record = JSON.parse(line) as Record<string, unknown>;
    const value = record.timestamp ?? record.updated_at ?? record.created_at;
    const parsed = typeof value === "number" ? value : Date.parse(String(value ?? ""));
    return Number.isFinite(parsed) ? parsed : 0;
  } catch {
    return 0;
  }
}

function codexTitles(home: string) {
  const titles = new Map<string, string>();
  const path = join(home, ".codex", "session_index.jsonl");
  if (!existsSync(path)) {
    return titles;
  }
  for (const line of readFileSync(path, "utf8").split("\n")) {
    try {
      const record = JSON.parse(line) as { id?: string; thread_name?: string };
      if (record.id && record.thread_name) {
        titles.set(record.id, record.thread_name);
      }
    } catch {
      // The active final line may be incomplete.
    }
  }
  return titles;
}

function sessionId(path: string) {
  const stem = basename(path, ".jsonl");
  return stem.length >= 36 ? stem.slice(-36) : stem;
}

function isCodexSubagent(path: string) {
  try {
    const first = JSON.parse(edgeLine(path, "first") ?? "{}") as {
      payload?: { source?: { subagent?: unknown } };
    };
    return first.payload?.source?.subagent !== undefined;
  } catch {
    return false;
  }
}

async function sha256(path: string) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

type Candidate = Omit<BenchmarkFixture, "sha256">;

async function main() {
  const home = homedir();
  const minimumInactiveDays = Number(option("--min-inactive-days") ?? defaultMinimumInactiveDays);
  const cutoff = Date.now() - minimumInactiveDays * 86_400_000;
  const titles = codexTitles(home);
  const roots: [ChatProvider, string][] = [
    ["codex", join(home, ".codex", "sessions")],
    ["codex", join(home, ".codex", "archived_sessions")],
    ["claude", join(home, ".claude", "projects")],
  ];
  const candidates: Candidate[] = [];
  for (const [provider, root] of roots) {
    for (const path of jsonlFiles(root)) {
      if (provider === "claude" && (path.includes(`${sep}subagents${sep}`) || basename(path).startsWith("agent-"))) {
        continue;
      }
      if (provider === "codex" && isCodexSubagent(path)) {
        continue;
      }
      const stats = statSync(path);
      const lastActivityAt = recordTimestamp(edgeLine(path, "last")) || stats.mtimeMs;
      if (lastActivityAt > cutoff) {
        continue;
      }
      const id = sessionId(path);
      candidates.push({
        id: `${provider}:${id}`,
        lastActivityAt,
        modifiedAt: stats.mtimeMs,
        path,
        provider,
        sourceBytes: stats.size,
        title: provider === "codex"
          ? titles.get(id) ?? `Codex chat — ${id.slice(0, 8)}`
          : `Claude chat — ${id.slice(0, 8)}`,
        updatedAt: lastActivityAt,
      });
    }
  }
  const selected = candidates.sort((left, right) => right.sourceBytes - left.sourceBytes).slice(0, 2);
  if (selected.length !== 2) {
    throw new Error(`Only ${selected.length} eligible transcripts found; lower --min-inactive-days`);
  }
  const fixtures = await Promise.all(selected.map(async (fixture) => ({
    ...fixture,
    sha256: await sha256(fixture.path),
  }))) as [BenchmarkFixture, BenchmarkFixture];
  const config: BenchmarkConfig = {
    fixtures,
    loadImages: false,
    switchDelayMs: 3_000,
    version: 1,
  };
  writeFileSync(outputPath, `${JSON.stringify(config, null, 2)}\n`);
  for (const fixture of fixtures) {
    const inactiveDays = (Date.now() - fixture.lastActivityAt) / 86_400_000;
    console.log(`${fixture.title}: ${(fixture.sourceBytes / 1_048_576).toFixed(2)} MiB, inactive ${inactiveDays.toFixed(1)} days`);
  }
  console.log(outputPath);
}

await main();
