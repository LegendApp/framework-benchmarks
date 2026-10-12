import { initializeGrammarPack } from "../../chat-history-electron/src/syntax-highlighting";
import type {
  BenchmarkConfig,
  BenchmarkEvent,
  CatalogResult,
  ChatDocument,
  ChatHistoryApi,
  ChatHistorySettings,
  ChatProvider,
  ChatRow,
} from "../../chat-history-electron/src/model";
import { mountChatHistory } from "../../chat-history-electron/src/renderer";

type DenoBindings = {
  fitInitialContent(width: number, height: number): Promise<[number, number]>;
  emitBenchmarkEvent(event: BenchmarkEvent): Promise<void>;
  getBenchmarkConfig(): Promise<BenchmarkConfig | undefined>;
  getImplementationName(): Promise<ChatHistoryApi["implementationName"]>;
  getRecentChats(limit: number): Promise<CatalogResult>;
  getSettings(): Promise<ChatHistorySettings>;
  openChat(provider: ChatProvider, path: string): Promise<ChatDocument>;
  getRows(documentId: string, indices: number[], includeToolPreview?: boolean): Promise<ChatRow[]>;
  getContentDigest(documentId: string): Promise<string>;
  openExternal(url: string): Promise<void>;
  saveSettings(settings: ChatHistorySettings): Promise<void>;
  setWindowTitle(title: string): Promise<void>;
};

declare const bindings: DenoBindings;

function localFileSource(source: string) {
  if (/^[a-z][a-z\d+.-]*:/i.test(source) && !source.startsWith("file://")) {
    return source;
  }
  const path = source.startsWith("file://") ? decodeURIComponent(new URL(source).pathname) : source;
  return `/__local_file?path=${encodeURIComponent(path)}`;
}

const implementationName = await bindings.getImplementationName();

window.chatHistory = {
  async getGrammarSource() {
    const response = await fetch("/__grammar_pack");
    if (!response.ok) throw new Error("External grammar pack unavailable");
    return response.text();
  },
  implementationName,
  emitBenchmarkEvent(event) {
    return bindings.emitBenchmarkEvent(event);
  },
  getBenchmarkConfig() {
    return bindings.getBenchmarkConfig();
  },
  getRecentChats(limit = 20) {
    return bindings.getRecentChats(limit);
  },
  getSettings() {
    return bindings.getSettings();
  },
  getRows(documentId, indices, includeToolPreview = false) {
    return bindings.getRows(documentId, indices, includeToolPreview);
  },
  getContentDigest(documentId) {
    return bindings.getContentDigest(documentId);
  },
  async openChat(provider: ChatProvider, path: string) {
    const startedAt = performance.now();
    const document = await bindings.openChat(provider, path);
    return {
      bridgeRoundTripMs: performance.now() - startedAt,
      document,
    };
  },
  resolveImageSource(source: string) {
    return localFileSource(source);
  },
  resolveMarkdownImageSource(source: string) {
    return localFileSource(source);
  },
  saveSettings(settings: ChatHistorySettings) {
    return bindings.saveSettings(settings);
  },
};

document.addEventListener("click", (event) => {
  const link = event.target instanceof Element ? event.target.closest("a") : null;
  const url = link?.getAttribute("href");
  if (url && /^(?:https?|mailto):/i.test(url)) {
    event.preventDefault();
    void bindings.openExternal(url);
  }
});

const windowTitle = document.querySelector("title");
if (windowTitle) {
  const syncWindowTitle = () => void bindings.setWindowTitle(document.title);
  new MutationObserver(syncWindowTitle).observe(windowTitle, {
    characterData: true,
    childList: true,
    subtree: true,
  });
  syncWindowTitle();
}

const [contentWidth, contentHeight] = await bindings.fitInitialContent(window.innerWidth, window.innerHeight);
const layoutDeadline = performance.now() + 3_000;
while (window.innerWidth !== contentWidth || window.innerHeight !== contentHeight) {
  if (performance.now() > layoutDeadline) throw new Error("Window client bounds did not settle");
  await new Promise((resolve) => setTimeout(resolve, 16));
}
await initializeGrammarPack(await window.chatHistory.getGrammarSource());
mountChatHistory();
