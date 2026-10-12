import {
  decodeText,
  type DeferredText,
  deferText,
  hasText,
  isStringValue,
  JsonRange,
  parseJsonRange,
  textValue,
} from "./json-range";
import { Buffer } from "node:buffer";
import { FileSource, type ByteSource } from "./file-source";
import { performance } from "node:perf_hooks";
import {
  type ChatDocument,
  type ChatFileChange,
  type ChatProvider,
  type ChatRow,
  normalizedContentDigest,
} from "./model";

type JsonObject = Record<string, unknown>;

type WorkingRow = Omit<ChatRow, "id" | "markdown" | "toolPreview"> & {
  markdown: DeferredText;
  toolPreview: DeferredText;
  callId: string;
  endedAtMs: number;
  startedAtMs: number;
};

type ClaudeRecord = {
  isSidechain: boolean;
  parentUuid: string;
  root: JsonObject;
  timestampMs: number;
  type: string;
  uuid: string;
};

function objectValue(value: unknown): JsonObject | undefined {
  if (value instanceof JsonRange) return value.object();
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : undefined;
}

function arrayValue(value: unknown): unknown[] | undefined {
  return value instanceof JsonRange ? value.array() : Array.isArray(value) ? value : undefined;
}

function stringValue(value: unknown) {
  return value instanceof JsonRange ? value.string() : typeof value === "string" ? value : "";
}

function booleanValue(value: unknown) {
  return value instanceof JsonRange ? value.boolean() : value === true;
}

function timestampValue(value: unknown) {
  const timestamp = Date.parse(stringValue(value));
  return Number.isFinite(timestamp) ? timestamp : 0;
}

function emptyRow(kind: WorkingRow["kind"], timestampMs: number): WorkingRow {
  return {
    callId: "",
    endedAtMs: timestampMs,
    fileChanges: [],
    hasImagePlaceholder: false,
    imageSources: [],
    kind,
    markdown: "",
    startedAtMs: timestampMs,
    toolName: "",
    toolPreview: "",
    toolStatus: "",
  };
}

function joinText(parts: DeferredText[]): DeferredText {
  return deferText(() => parts.map(decodeText).filter(Boolean).join("\n\n"), parts.some(hasText));
}

function visibleUserMarkdown(markdown: string, row: WorkingRow) {
  const filesHeading = "# Files mentioned by the user:";
  const requestHeading = "## My request for Codex:";
  const firstContent = markdown.search(/[^\r\n]/);
  if (
    row.kind === "user" &&
    (row.imageSources.length > 0 || row.hasImagePlaceholder) &&
    firstContent >= 0 &&
    markdown.startsWith(filesHeading, firstContent)
  ) {
    const requestIndex = markdown.indexOf(requestHeading, firstContent + filesHeading.length);
    if (requestIndex >= 0) {
      let contentIndex = requestIndex + requestHeading.length;
      while (markdown[contentIndex] === "\r" || markdown[contentIndex] === "\n") {
        contentIndex += 1;
      }
      return markdown.slice(contentIndex);
    }
  }
  return markdown;
}

function visibleAssistantMarkdown(markdown: string, kind: WorkingRow["kind"]) {
  if (kind !== "assistant") {
    return markdown;
  }
  const directive =
    /^\s*::(?:git-stage|git-commit|git-create-branch|git-push|git-create-pr|created-thread|code-comment)\{/;
  const output: string[] = [];
  let inCodeFence = false;
  let inMemoryCitation = false;
  for (const line of markdown.split("\n")) {
    const trimmed = line.trim();
    if (!inCodeFence && trimmed.startsWith("<oai-mem-citation>")) {
      inMemoryCitation = !trimmed.includes("</oai-mem-citation>");
    } else if (inMemoryCitation) {
      inMemoryCitation = !trimmed.includes("</oai-mem-citation>");
    } else if (inCodeFence || !directive.test(line)) {
      output.push(line);
    }
    if (!inMemoryCitation && (trimmed.startsWith("```") || trimmed.startsWith("~~~"))) {
      inCodeFence = !inCodeFence;
    }
  }
  while (output.at(-1) === "" || output.at(-1) === "\r") {
    output.pop();
  }
  return output.join("\n");
}

function appendMessage(
  rows: WorkingRow[],
  kind: "assistant" | "user",
  markdownParts: DeferredText[],
  imageSources: string[],
  hasImagePlaceholder: boolean,
  timestampMs: number,
) {
  const markdown = joinText(markdownParts);
  if (hasText(markdown) || imageSources.length > 0 || hasImagePlaceholder) {
    const row = emptyRow(kind, timestampMs);
    row.markdown = markdown;
    row.imageSources = imageSources;
    row.hasImagePlaceholder = hasImagePlaceholder;
    rows.push(row);
  }
}

function appendTool(
  rows: WorkingRow[],
  toolRows: Map<string, number>,
  callId: string,
  name: string,
  preview: DeferredText,
  timestampMs: number,
) {
  const row = emptyRow("tool", timestampMs);
  row.callId = callId;
  row.toolName = name || "Tool";
  row.toolPreview = preview;
  row.toolStatus = "unknown";
  rows.push(row);
  const index = rows.length - 1;
  if (callId) {
    toolRows.set(callId, index);
  }
  return index;
}

function applyToolResult(
  rows: WorkingRow[],
  toolRows: Map<string, number>,
  callId: string,
  preview: DeferredText,
  failed: boolean,
  timestampMs: number,
) {
  const index = toolRows.get(callId) ??
    appendTool(rows, toolRows, callId, "Tool", "", timestampMs);
  const row = rows[index];
  row.toolStatus = failed ? "failed" : "completed";
  row.endedAtMs = Math.max(row.endedAtMs, timestampMs);
  if (hasText(preview)) {
    row.toolPreview = preview;
  }
}

function countLines(content: string) {
  if (!content) {
    return 0;
  }
  return content.split("\n").length - (content.endsWith("\n") ? 1 : 0);
}

function countDiffLines(diff: string) {
  let additions = 0;
  let deletions = 0;
  let inHunk = false;
  for (const line of diff.split("\n")) {
    if (line.startsWith("@@")) {
      inHunk = true;
    } else if (inHunk && line.startsWith("+")) {
      additions += 1;
    } else if (inHunk && line.startsWith("-")) {
      deletions += 1;
    }
  }
  return { additions, deletions };
}

function toolActivityLabel(row: WorkingRow) {
  const name = row.toolName.toLowerCase();
  let label = "Used a tool";
  if (/exec|shell|command|bash/.test(name)) {
    label = "Ran a command";
  } else if (name.includes("agent")) {
    label = "Worked with an agent";
  } else if (/patch|write|edit/.test(name)) {
    label = "Edited files";
  } else if (/read|open|find|glob|grep/.test(name)) {
    label = "Read files";
  } else if (/web|search|browser/.test(name)) {
    label = "Searched the web";
  } else if (name.includes("image")) {
    label = "Created an image";
  } else if (name) {
    label = `Used ${name.replaceAll(/[_-]/g, " ")}`;
  }
  return row.toolStatus === "failed" ? `${label} (failed)` : label;
}

function workLabel(rows: WorkingRow[]) {
  const starts = rows.map((row) => row.startedAtMs).filter((value) => value > 0);
  const ends = rows.map((row) => row.endedAtMs).filter((value) => value > 0);
  if (starts.length === 0 || ends.length === 0) {
    return "Worked";
  }
  const elapsedSeconds = Math.max(1, Math.round((Math.max(...ends) - Math.min(...starts)) / 1_000));
  const hours = Math.floor(elapsedSeconds / 3_600);
  const minutes = Math.floor((elapsedSeconds % 3_600) / 60);
  const seconds = elapsedSeconds % 60;
  let duration = `${seconds}s`;
  if (hours > 0) {
    duration = minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
  } else if (minutes > 0) {
    duration = seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`;
  }
  return `Worked for ${duration}`;
}

function workPreview(rows: WorkingRow[]) {
  const output: string[] = [];
  let activities: string[] = [];
  const flushActivities = () => {
    if (activities.length > 0) {
      output.push(
        activities.map((activity, index) =>
          index === 0 ? activity : `${activity[0].toLowerCase()}${activity.slice(1)}`
        ).join(", "),
      );
      activities = [];
    }
  };
  for (const row of rows) {
    if (row.kind === "tool") {
      const activity = toolActivityLabel(row);
      if (!activities.includes(activity)) {
        activities.push(activity);
      }
    } else {
      flushActivities();
      if (hasText(row.markdown)) {
        output.push(decodeText(row.markdown).slice(0, 4 * 1_024));
      }
      if (row.hasImagePlaceholder) {
        output.push("Image or attachment omitted");
      }
    }
  }
  flushActivities();
  return output.join("\n\n").slice(0, 64 * 1_024);
}

function displayRows(rows: WorkingRow[]) {
  const result: ChatRow[] = [];
  let sourceIndex = 0;
  while (sourceIndex < rows.length) {
    const row = rows[sourceIndex];
    if (row.kind === "user") {
      result.push(finalizeRow(row, result.length));
      sourceIndex += 1;
      continue;
    }
    let turnEnd = sourceIndex;
    let lastTool = -1;
    while (turnEnd < rows.length && rows[turnEnd].kind !== "user") {
      if (rows[turnEnd].kind === "tool") {
        lastTool = turnEnd;
      }
      turnEnd += 1;
    }
    if (lastTool >= sourceIndex) {
      const grouped = rows.slice(sourceIndex, lastTool + 1);
      const work = emptyRow("tool", 0);
      work.toolName = workLabel(grouped);
      work.toolPreview = deferText(() => workPreview(grouped));
      work.toolStatus = grouped.some((item) => item.kind === "tool" && item.toolStatus === "failed")
        ? "failed"
        : grouped.some((item) => item.kind === "tool" && item.toolStatus !== "completed")
        ? "unknown"
        : "completed";
      result.push(finalizeRow(work, result.length));
      sourceIndex = lastTool + 1;
    } else {
      result.push(finalizeRow(row, result.length));
      sourceIndex += 1;
    }
  }
  return result;
}

function finalizeRow(row: WorkingRow, index: number): ChatRow {
  return {
    fileChanges: row.fileChanges,
    hasImagePlaceholder: row.hasImagePlaceholder,
    id: `row:${index}`,
    imageSources: row.imageSources,
    kind: row.kind,
    get markdown() {
      return visibleAssistantMarkdown(visibleUserMarkdown(decodeText(row.markdown), row), row.kind);
    },
    toolName: row.toolName,
    get toolPreview() {
      return decodeText(row.toolPreview);
    },
    toolStatus: row.toolStatus,
  };
}

function parseCodex(lines: Iterable<string | JsonRange>) {
  const rows: WorkingRow[] = [];
  const toolRows = new Map<string, number>();
  let warningCount = 0;
  let cwd = "";
  let sawEventUserMessage = false;
  let pendingTurnId = "";
  let pendingFiles: ChatFileChange[] = [];
  const appendFiles = () => {
    if (pendingFiles.length > 0) {
      const row = emptyRow("files", 0);
      row.fileChanges = pendingFiles;
      rows.push(row);
    }
    pendingTurnId = "";
    pendingFiles = [];
  };

  for (const line of lines) {
    let root: JsonObject | undefined;
    try {
      root = objectValue(typeof line === "string" ? JSON.parse(line) : line);
    } catch {
      warningCount += 1;
      continue;
    }
    if (!root) {
      warningCount += 1;
      continue;
    }
    const recordType = stringValue(root.type);
    const payload = objectValue(root.payload);
    const timestampMs = timestampValue(root.timestamp);
    if (!recordType || root.payload === undefined) {
      warningCount += 1;
      continue;
    }
    if (recordType === "compacted") {
      continue;
    }
    if ((recordType === "session_meta" || recordType === "turn_context") && payload) {
      cwd = stringValue(payload.cwd) || cwd;
      continue;
    }
    if (recordType === "event_msg" && payload) {
      const eventType = stringValue(payload.type);
      if (eventType === "user_message") {
        sawEventUserMessage = true;
        appendFiles();
        const message = textValue(payload.message);
        if (!hasText(message)) {
          warningCount += 1;
        }
        const localImages = arrayValue(payload.local_images)?.map(stringValue).filter(Boolean) ??
          [];
        let hasImagePlaceholder = false;
        const remoteImages = (arrayValue(payload.images) ?? []).flatMap((value) => {
          const image = stringValue(value);
          if (!image || Buffer.byteLength(image) > 8 * 1_024) {
            hasImagePlaceholder = true;
            return [];
          }
          return [image];
        });
        appendMessage(
          rows,
          "user",
          [message],
          [...localImages, ...remoteImages],
          hasImagePlaceholder,
          timestampMs,
        );
      } else if (eventType === "patch_apply_end" && booleanValue(payload.success)) {
        const turnId = stringValue(payload.turn_id);
        if (pendingTurnId && turnId && pendingTurnId !== turnId) {
          appendFiles();
        }
        pendingTurnId = turnId;
        const changes = objectValue(payload.changes);
        if (changes) {
          for (const [path, rawChange] of Object.entries(changes)) {
            const change = objectValue(rawChange);
            if (!change) {
              warningCount += 1;
              continue;
            }
            const type = stringValue(change.type);
            let additions = 0;
            let deletions = 0;
            if (type === "update" && isStringValue(change.unified_diff)) {
              ({ additions, deletions } = countDiffLines(stringValue(change.unified_diff)));
            } else if ((type === "add" || type === "delete") && isStringValue(change.content)) {
              const count = countLines(stringValue(change.content));
              additions = type === "add" ? count : 0;
              deletions = type === "delete" ? count : 0;
            } else {
              warningCount += 1;
              continue;
            }
            const relativePath = cwd && path.startsWith(`${cwd}/`)
              ? path.slice(cwd.length + 1)
              : path;
            const existing = pendingFiles.find((file) => file.path === relativePath);
            if (existing) {
              existing.additions += additions;
              existing.deletions += deletions;
            } else {
              pendingFiles.push({ additions, deletions, path: relativePath });
            }
          }
        }
      }
      continue;
    }
    if (recordType !== "response_item") {
      continue;
    }
    if (!payload) {
      warningCount += 1;
      continue;
    }
    const payloadType = stringValue(payload.type);
    if (payloadType === "message") {
      const role = stringValue(payload.role);
      if (role !== "assistant" && (role !== "user" || sawEventUserMessage)) {
        continue;
      }
      const content = payload.content;
      const text: DeferredText[] = [];
      let hasImage = false;
      if (isStringValue(content)) {
        text.push(textValue(content));
      } else if (arrayValue(content)) {
        for (const rawBlock of arrayValue(content)!) {
          const block = objectValue(rawBlock);
          const blockType = stringValue(block?.type);
          if (block && ["input_text", "output_text", "text"].includes(blockType)) {
            text.push(textValue(block.text));
          } else if (["input_image", "image"].includes(blockType)) {
            hasImage = true;
          } else if (blockType) {
            warningCount += 1;
          }
        }
      } else if (content !== undefined) {
        warningCount += 1;
      }
      appendMessage(rows, role, text, [], hasImage, timestampMs);
    } else if (["function_call", "custom_tool_call", "local_shell_call"].includes(payloadType)) {
      appendTool(
        rows,
        toolRows,
        stringValue(payload.call_id),
        stringValue(payload.name),
        textValue(payload[payloadType === "custom_tool_call" ? "input" : "arguments"]),
        timestampMs,
      );
    } else if (["function_call_output", "custom_tool_call_output"].includes(payloadType)) {
      applyToolResult(
        rows,
        toolRows,
        stringValue(payload.call_id),
        textValue(payload.output),
        false,
        timestampMs,
      );
    } else if (payloadType === "image_generation_call") {
      const callId = stringValue(payload.id);
      const index = toolRows.get(callId) ??
        appendTool(rows, toolRows, callId, "Image generation", "", timestampMs);
      const row = rows[index];
      const hasResult = hasText(textValue(payload.result));
      row.toolStatus = stringValue(payload.status) === "failed"
        ? "failed"
        : hasResult
        ? "completed"
        : "unknown";
      row.hasImagePlaceholder ||= hasResult;
      row.endedAtMs = Math.max(row.endedAtMs, timestampMs);
    } else if (payloadType !== "reasoning" && payloadType) {
      warningCount += 1;
    }
  }
  appendFiles();
  return { rows: displayRows(rows), warningCount };
}

function parseClaudeMessage(
  record: ClaudeRecord,
  rows: WorkingRow[],
  toolRows: Map<string, number>,
) {
  const message = objectValue(record.root.message);
  if (!message || message.content === undefined) {
    return 1;
  }
  if (isStringValue(message.content)) {
    appendMessage(
      rows,
      record.type as "assistant" | "user",
      [textValue(message.content)],
      [],
      false,
      record.timestampMs,
    );
    return 0;
  }
  const content = arrayValue(message.content);
  if (!content) {
    return 1;
  }
  const text: DeferredText[] = [];
  let hasImage = false;
  let warningCount = 0;
  const deferredTools: (() => void)[] = [];
  for (const rawBlock of arrayValue(content)!) {
    const block = objectValue(rawBlock);
    if (!block) {
      warningCount += 1;
      continue;
    }
    const blockType = stringValue(block.type);
    if (blockType === "text") {
      text.push(textValue(block.text));
    } else if (blockType === "image" || blockType === "document") {
      hasImage = true;
    } else if (blockType === "tool_use") {
      const callId = stringValue(block.id);
      const name = stringValue(block.name);
      deferredTools.push(() => appendTool(rows, toolRows, callId, name, "", record.timestampMs));
    } else if (blockType === "tool_result") {
      const callId = stringValue(block.tool_use_id);
      const resultContent = block.content;
      const previews: DeferredText[] = [];
      let resultImage = false;
      if (isStringValue(resultContent)) {
        previews.push(textValue(resultContent));
      } else if (arrayValue(resultContent)) {
        for (const rawResult of arrayValue(resultContent)!) {
          if (isStringValue(rawResult)) {
            previews.push(textValue(rawResult));
          } else {
            const result = objectValue(rawResult);
            const resultType = stringValue(result?.type);
            if (resultType === "text") {
              previews.push(textValue(result?.text));
            } else if (resultType === "image") {
              resultImage = true;
            } else {
              warningCount += 1;
            }
          }
        }
      }
      deferredTools.push(() => {
        applyToolResult(
          rows,
          toolRows,
          callId,
          joinText(previews),
          booleanValue(block.is_error),
          record.timestampMs,
        );
        const index = toolRows.get(callId);
        if (resultImage && index !== undefined) {
          rows[index].hasImagePlaceholder = true;
        }
      });
    } else if (blockType !== "thinking") {
      warningCount += 1;
    }
  }
  appendMessage(rows, record.type as "assistant" | "user", text, [], hasImage, record.timestampMs);
  deferredTools.forEach((append) => append());
  return warningCount;
}

function parseClaude(lines: Iterable<string | JsonRange>) {
  const records: ClaudeRecord[] = [];
  const recordById = new Map<string, ClaudeRecord>();
  let warningCount = 0;
  let leafId = "";
  for (const line of lines) {
    let root: JsonObject | undefined;
    try {
      root = objectValue(typeof line === "string" ? JSON.parse(line) : line);
    } catch {
      warningCount += 1;
      continue;
    }
    if (!root) {
      warningCount += 1;
      continue;
    }
    const record: ClaudeRecord = {
      isSidechain: booleanValue(root.isSidechain),
      parentUuid: stringValue(root.parentUuid),
      root,
      timestampMs: timestampValue(root.timestamp),
      type: stringValue(root.type),
      uuid: stringValue(root.uuid),
    };
    records.push(record);
    if (record.uuid && !record.isSidechain) {
      recordById.set(record.uuid, record);
      leafId = record.uuid;
    }
  }
  const mainChain = new Set<string>();
  let cursor = leafId;
  while (cursor && !mainChain.has(cursor)) {
    mainChain.add(cursor);
    const record = recordById.get(cursor);
    if (!record) {
      warningCount += 1;
      break;
    }
    cursor = record.parentUuid;
  }
  const rows: WorkingRow[] = [];
  const toolRows = new Map<string, number>();
  for (const record of records) {
    if (
      !record.isSidechain &&
      record.uuid &&
      mainChain.has(record.uuid) &&
      (record.type === "user" || record.type === "assistant")
    ) {
      warningCount += parseClaudeMessage(record, rows, toolRows);
    }
  }
  return { rows: displayRows(rows), warningCount };
}

export function parseChatText(provider: ChatProvider, text: string) {
  const scanStartedAt = performance.now();
  const lines = text.split("\n").map((line) => line.endsWith("\r") ? line.slice(0, -1) : line)
    .filter(Boolean);
  const scanMs = performance.now() - scanStartedAt;
  const parseStartedAt = performance.now();
  const result = provider === "codex" ? parseCodex(lines) : parseClaude(lines);
  const parseMs = performance.now() - parseStartedAt;
  return { ...result, parseMs, recordCount: lines.length, scanMs };
}

function scanLineRanges(source: ByteSource) {
  if (source instanceof FileSource) return source.lineRanges();
  const ranges: number[] = [];
  let start = 0;
  for (let index = 0; index <= source.length; index += 1) {
    if (index !== source.length && source.at(index)! !== 10) {
      continue;
    }
    let end = index;
    if (end > start && source.at(end - 1)! === 13) {
      end -= 1;
    }
    if (end > start) {
      ranges.push(start, end);
    }
    start = index + 1;
  }
  return ranges;
}

function* decodeLines(source: ByteSource, ranges: number[]) {
  for (let index = 0; index < ranges.length; index += 2) {
    try {
      yield parseJsonRange(source, ranges[index], ranges[index + 1]);
    } catch {
      yield "!invalid";
    }
  }
}

export async function openChatFile(provider: ChatProvider, path: string): Promise<ChatDocument> {
  const startedAt = performance.now();
  const loadStartedAt = performance.now();
  const source = new FileSource(path);
  try {
    const loadMs = performance.now() - loadStartedAt;
    const scanStartedAt = performance.now();
    const ranges = scanLineRanges(source);
    const scanMs = performance.now() - scanStartedAt;
    const parseStartedAt = performance.now();
    const result = provider === "codex"
      ? parseCodex(decodeLines(source, ranges))
      : parseClaude(decodeLines(source, ranges));
    const parseMs = performance.now() - parseStartedAt;
    const document: ChatDocument = {
      path,
      provider,
      recordCount: ranges.length / 2,
      rows: result.rows,
      sourceBytes: source.byteLength,
      timing: {
        loadMs,
        nativeTotalMs: performance.now() - startedAt,
        parseMs,
        scanMs,
      },
      warningCount: result.warningCount,
    };
    sources.set(document, source);
    return document;
  } catch (error) {
    source.close();
    throw error;
  }
}

const sources = new WeakMap<ChatDocument, FileSource>();
export function closeChatDocument(document: ChatDocument) {
  sources.get(document)?.close();
  sources.delete(document);
}
