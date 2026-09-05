import { open, readFile, readdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, extname, join } from "node:path";
import { performance } from "node:perf_hooks";
import type { CatalogResult, ChatProvider, ChatSummary } from "./model";

type Metadata = {
  title: string;
  updatedAt: number;
};

async function readJson(path: string) {
  try {
    return JSON.parse(await readFile(path, "utf8")) as unknown;
  } catch {
    return undefined;
  }
}

async function walkJsonl(root: string) {
  const files: string[] = [];
  const directories = [root];
  while (directories.length > 0) {
    const directory = directories.pop()!;
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        directories.push(path);
      } else if (entry.isFile() && extname(entry.name) === ".jsonl") {
        files.push(path);
      }
    }
  }
  return files;
}

function sessionId(path: string) {
  const stem = basename(path, ".jsonl");
  return stem.length >= 36 ? stem.slice(-36) : stem;
}

function timestamp(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  const parsed = typeof value === "string" ? Date.parse(value) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : 0;
}

function fallbackTitle(provider: ChatProvider, updatedAt: number) {
  const date = new Date(updatedAt);
  const label = Number.isFinite(date.valueOf())
    ? date.toLocaleDateString(undefined, { day: "numeric", month: "short" })
    : "Unknown date";
  return `${provider === "codex" ? "Codex" : "Claude"} chat — ${label}`;
}

async function modifiedAt(path: string) {
  try {
    return (await stat(path)).mtimeMs;
  } catch {
    return 0;
  }
}

async function loadCodexMetadata(home: string) {
  const metadata = new Map<string, Metadata>();
  try {
    const content = await readFile(join(home, ".codex", "session_index.jsonl"), "utf8");
    for (const line of content.split("\n")) {
      try {
        const record = JSON.parse(line) as Record<string, unknown>;
        if (typeof record.id === "string") {
          metadata.set(record.id, {
            title: typeof record.thread_name === "string" ? record.thread_name : "",
            updatedAt: timestamp(record.updated_at),
          });
        }
      } catch {
        // An actively written final index record is allowed to be incomplete.
      }
    }
  } catch {
    // Codex may not be installed.
  }
  return metadata;
}

async function loadClaudeMetadata(root: string) {
  const metadata = new Map<string, Metadata>();
  const directories = [root];
  while (directories.length > 0) {
    const directory = directories.pop()!;
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) {
        directories.push(path);
      } else if (entry.isFile() && entry.name === "sessions-index.json") {
        const index = await readJson(path) as { entries?: Record<string, unknown>[] } | undefined;
        for (const item of index?.entries ?? []) {
          const fullPath = typeof item.fullPath === "string" ? item.fullPath : "";
          const id = typeof item.sessionId === "string" ? item.sessionId : "";
          const value = {
            title: typeof item.summary === "string"
              ? item.summary
              : typeof item.firstPrompt === "string" ? item.firstPrompt : "",
            updatedAt: timestamp(item.modified) || timestamp(item.fileMtime),
          };
          if (fullPath) {
            metadata.set(fullPath, value);
          }
          if (id) {
            metadata.set(id, value);
          }
        }
      }
    }
  }
  return metadata;
}

async function isCodexSubagent(path: string) {
  let handle: Awaited<ReturnType<typeof open>> | undefined;
  try {
    handle = await open(path, "r");
    const buffer = Buffer.allocUnsafe(64 * 1_024);
    const { bytesRead } = await handle.read(buffer, 0, buffer.byteLength, 0);
    const source = buffer.toString("utf8", 0, bytesRead);
    const lineEnd = source.indexOf("\n");
    const firstLine = lineEnd >= 0 ? source.slice(0, lineEnd) : source;
    const root = JSON.parse(firstLine) as { payload?: { source?: { subagent?: unknown } } };
    return root.payload?.source?.subagent !== undefined;
  } catch {
    return false;
  } finally {
    await handle?.close();
  }
}

export async function getRecentChats(limit = 20, home = homedir()): Promise<CatalogResult> {
  const startedAt = performance.now();
  const boundedLimit = Math.max(0, Math.floor(limit));
  if (boundedLimit === 0) {
    return { nativeTotalMs: performance.now() - startedAt, summaries: [] };
  }
  const claudeRoot = join(home, ".claude", "projects");
  const [codexMetadata, claudeMetadata, codexFiles, archivedCodexFiles, claudeFiles] = await Promise.all([
    loadCodexMetadata(home),
    loadClaudeMetadata(claudeRoot),
    walkJsonl(join(home, ".codex", "sessions")),
    walkJsonl(join(home, ".codex", "archived_sessions")),
    walkJsonl(claudeRoot),
  ]);
  const candidates = await Promise.all([
    ...codexFiles,
    ...archivedCodexFiles,
  ].map(async (path) => {
    const id = sessionId(path);
    const metadata = codexMetadata.get(id);
    const updatedAt = metadata?.updatedAt || await modifiedAt(path);
    return {
      indexed: metadata !== undefined,
      summary: {
        id: `codex:${id}`,
        path,
        provider: "codex" as const,
        title: metadata?.title || fallbackTitle("codex", updatedAt),
        updatedAt,
      },
    };
  }));
  const claudeCandidates = await Promise.all(claudeFiles
    .filter((path) => !path.split("/").includes("subagents") && !basename(path).startsWith("agent-"))
    .map(async (path) => {
      const id = sessionId(path);
      const metadata = claudeMetadata.get(path) ?? claudeMetadata.get(id);
      const updatedAt = metadata?.updatedAt || await modifiedAt(path);
      return {
        indexed: true,
        summary: {
          id: `claude:${id}`,
          path,
          provider: "claude" as const,
          title: metadata?.title || fallbackTitle("claude", updatedAt),
          updatedAt,
        },
      };
    }));
  const sorted = [...candidates, ...claudeCandidates]
    .sort((left, right) => right.summary.updatedAt - left.summary.updatedAt || left.summary.id.localeCompare(right.summary.id));
  const summaries: ChatSummary[] = [];
  const seenIds = new Set<string>();
  for (const candidate of sorted) {
    if (seenIds.has(candidate.summary.id)) {
      continue;
    }
    seenIds.add(candidate.summary.id);
    if (!candidate.indexed && await isCodexSubagent(candidate.summary.path)) {
      continue;
    }
    summaries.push(candidate.summary);
    if (summaries.length === boundedLimit) {
      break;
    }
  }
  return { nativeTotalMs: performance.now() - startedAt, summaries };
}
