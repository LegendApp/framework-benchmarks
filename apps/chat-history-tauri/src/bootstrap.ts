import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { openUrl } from "@tauri-apps/plugin-opener";
import { mountChatHistory } from "../../chat-history-electron/src/renderer";
import type {
  CatalogResult,
  ChatDocument,
  ChatHistorySettings,
  ChatProvider,
} from "../../chat-history-electron/src/model";

function imageSource(source: string) {
  if (source.startsWith("file://")) {
    return convertFileSrc(decodeURIComponent(new URL(source).pathname));
  }
  return /^[a-z][a-z\d+.-]*:/i.test(source) ? source : convertFileSrc(source);
}

window.chatHistory = {
  implementationName: "Tauri",
  emitBenchmarkEvent(event) {
    return invoke<void>("emit_benchmark_event", { event });
  },
  getBenchmarkConfig() {
    return invoke("get_benchmark_config");
  },
  getRecentChats(limit = 20) {
    return invoke<CatalogResult>("get_recent_chats", { limit });
  },
  getSettings() {
    return invoke<ChatHistorySettings>("get_settings");
  },
  async openChat(provider: ChatProvider, path: string) {
    const startedAt = performance.now();
    const document = await invoke<ChatDocument>("open_chat", { path, provider });
    return {
      bridgeRoundTripMs: performance.now() - startedAt,
      document,
    };
  },
  resolveImageSource(source: string) {
    return imageSource(source);
  },
  resolveMarkdownImageSource(source: string) {
    return imageSource(source);
  },
  saveSettings(settings: ChatHistorySettings) {
    return invoke<void>("save_settings", { settings });
  },
};

document.addEventListener("click", (event) => {
  const link = event.target instanceof Element ? event.target.closest("a") : null;
  const url = link?.getAttribute("href");
  if (url && /^(?:https?|mailto):/i.test(url)) {
    event.preventDefault();
    void openUrl(url);
  }
});

const windowTitle = document.querySelector("title");
if (windowTitle) {
  const appWindow = getCurrentWindow();
  const syncWindowTitle = () => void appWindow.setTitle(document.title);
  new MutationObserver(syncWindowTitle).observe(windowTitle, {
    characterData: true,
    childList: true,
    subtree: true,
  });
  syncWindowTitle();
}

mountChatHistory();
