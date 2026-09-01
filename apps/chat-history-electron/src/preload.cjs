const { contextBridge, ipcRenderer } = require("electron");

function imageSource(source) {
  return /^[a-z][a-z\d+.-]*:/i.test(source)
    ? source
    : `file://${source.split("/").map(encodeURIComponent).join("/")}`;
}

contextBridge.exposeInMainWorld("chatHistory", {
  implementationName: "Electron",
  emitBenchmarkEvent(event) {
    return ipcRenderer.invoke("chat-history:emit-benchmark-event", event);
  },
  getBenchmarkConfig() {
    return ipcRenderer.invoke("chat-history:get-benchmark-config");
  },
  getRecentChats(limit = 20) {
    return ipcRenderer.invoke("chat-history:get-recent", limit);
  },
  getSettings() {
    return ipcRenderer.invoke("chat-history:get-settings");
  },
  async openChat(provider, path) {
    const startedAt = performance.now();
    const document = await ipcRenderer.invoke("chat-history:open", provider, path);
    return {
      bridgeRoundTripMs: performance.now() - startedAt,
      document,
    };
  },
  resolveImageSource(source) {
    return imageSource(source);
  },
  resolveMarkdownImageSource(source) {
    return imageSource(source);
  },
  saveSettings(settings) {
    return ipcRenderer.invoke("chat-history:save-settings", settings);
  },
});
