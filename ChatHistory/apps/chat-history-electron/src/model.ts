export type ChatProvider = "claude" | "codex";

export type ChatAppearance = "dark" | "light" | "system";

export type ChatHistorySettings = {
  appearance: ChatAppearance;
  loadImages: boolean;
  recentChatLimit: 20 | 50 | 100;
  restoreSelection: boolean;
  selectedId?: string;
  showPerformanceMetrics: boolean;
};

export const defaultChatHistorySettings: ChatHistorySettings = {
  appearance: "system",
  loadImages: true,
  recentChatLimit: 20,
  restoreSelection: true,
  showPerformanceMetrics: false,
};

export function normalizeChatHistorySettings(value: unknown): ChatHistorySettings {
  const source = value !== null && typeof value === "object"
    ? value as Partial<ChatHistorySettings>
    : {};
  const appearance = source.appearance === "dark" || source.appearance === "light"
    ? source.appearance
    : "system";
  const recentChatLimit = source.recentChatLimit === 50 || source.recentChatLimit === 100
    ? source.recentChatLimit
    : 20;
  return {
    appearance,
    loadImages: typeof source.loadImages === "boolean"
      ? source.loadImages
      : defaultChatHistorySettings.loadImages,
    recentChatLimit,
    restoreSelection: typeof source.restoreSelection === "boolean"
      ? source.restoreSelection
      : defaultChatHistorySettings.restoreSelection,
    selectedId: typeof source.selectedId === "string" ? source.selectedId : undefined,
    showPerformanceMetrics: typeof source.showPerformanceMetrics === "boolean"
      ? source.showPerformanceMetrics
      : defaultChatHistorySettings.showPerformanceMetrics,
  };
}

export type ChatSummary = {
  id: string;
  path: string;
  provider: ChatProvider;
  title: string;
  updatedAt: number;
};

export type ChatFileChange = {
  additions: number;
  deletions: number;
  path: string;
};

export type ChatRow = {
  deferred?: boolean;
  fileChanges: ChatFileChange[];
  hasImagePlaceholder: boolean;
  id: string;
  imageSources: string[];
  kind: "assistant" | "files" | "tool" | "user";
  markdown: string;
  toolName: string;
  toolPreview: string;
  toolStatus: "completed" | "failed" | "unknown" | "";
};

export type NativeTiming = {
  loadMs: number;
  nativeTotalMs: number;
  parseMs: number;
  scanMs: number;
};

export type ChatDocument = {
  documentId?: string;
  path: string;
  provider: ChatProvider;
  recordCount: number;
  rows: ChatRow[];
  sourceBytes: number;
  timing: NativeTiming;
  warningCount: number;
};

export type CatalogResult = {
  nativeTotalMs: number;
  summaries: ChatSummary[];
};

export type OpenChatResult = {
  bridgeRoundTripMs: number;
  document: ChatDocument;
};

export type BenchmarkFixture = ChatSummary & {
  lastActivityAt: number;
  modifiedAt: number;
  sha256: string;
  sourceBytes: number;
};

export type BenchmarkTarget = Pick<ChatSummary, "id" | "provider">;

export type BenchmarkConfig = {
  appearance?: ChatAppearance;
  loadImages: boolean;
  switchDelayMs: number;
  topDelayMs: number;
  targets: [BenchmarkTarget, BenchmarkTarget];
  version: 2;
};

export type BenchmarkFixtureManifest = {
  fixtures: [BenchmarkFixture, BenchmarkFixture];
  loadImages: boolean;
  switchDelayMs: number;
  version: 2;
};

export type BenchmarkContentReadyEvent = {
  discoveryMs?: number;
  durationMs: number;
  name: "contentReady";
  path: string;
  phase: "initial" | "switch";
  recordCount: number;
  rowCount: number;
  sourceBytes: number;
  timing: NativeTiming & { documentMs?: number };
};

export type BenchmarkContentDigestEvent = {
  contentDigest: string;
  name: "contentDigest";
  path: string;
  phase: "initial" | "switch";
};

export type BenchmarkViewportReadyEvent = {
  durationMs: number;
  name: "viewportReady";
  path: string;
  phase: "top";
};

const fnvOffset = 0xcbf29ce484222325n;
const fnvPrime = 0x100000001b3n;
const uint64Mask = 0xffffffffffffffffn;

export function normalizedContentDigest(rows: readonly ChatRow[]) {
  let digest = fnvOffset;
  const encoder = new TextEncoder();
  const updateBytes = (bytes: Uint8Array) => {
    for (const byte of bytes) {
      digest = ((digest ^ BigInt(byte)) * fnvPrime) & uint64Mask;
    }
  };
  const update = (value: string) => updateBytes(encoder.encode(value));
  const field = (value: string | number) => {
    const text = String(value);
    const bytes = encoder.encode(text);
    update(String(bytes.byteLength));
    update(":");
    updateBytes(bytes);
    update(";");
  };
  field(rows.length);
  for (const row of rows) {
    field(row.kind);
    field(row.markdown);
    field(row.toolName);
    field(row.toolPreview);
    field(row.toolStatus);
    field(row.hasImagePlaceholder ? 1 : 0);
    field(row.imageSources.length);
    for (const source of row.imageSources) {
      field(source);
    }
    field(row.fileChanges.length);
    for (const change of row.fileChanges) {
      field(change.path);
      field(change.additions);
      field(change.deletions);
    }
  }
  return digest.toString(16).padStart(16, "0");
}

export type BenchmarkEvent =
  | BenchmarkContentDigestEvent
  | BenchmarkContentReadyEvent
  | BenchmarkViewportReadyEvent;

export type ChatHistoryApi = {
  getGrammarSource(): Promise<string>;
  implementationName:
    | "Deno CEF"
    | "Deno WebView"
    | "Electron"
    | "Tauri";
  emitBenchmarkEvent?(event: BenchmarkEvent): Promise<void>;
  getBenchmarkConfig?(): Promise<BenchmarkConfig | undefined>;
  getRecentChats(limit?: number): Promise<CatalogResult>;
  openChat(provider: ChatProvider, path: string): Promise<OpenChatResult>;
  getRows(documentId: string, indices: number[], includeToolPreview?: boolean): Promise<ChatRow[]>;
  getContentDigest(documentId: string): Promise<string>;
  getSettings?(): Promise<ChatHistorySettings>;
  resolveMarkdownImageSource?(source: string): string;
  resolveImageSource?(source: string): string;
  saveSettings?(settings: ChatHistorySettings): Promise<void>;
};
