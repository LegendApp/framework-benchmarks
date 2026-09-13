import type { DocumentRequest } from "./document-registry";
import { appendFile, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { app, BrowserWindow, ipcMain, type IpcMainInvokeEvent, shell } from "electron";
import { getRecentChats } from "./catalog";
import type { BenchmarkConfig, BenchmarkEvent, ChatDocument, ChatProvider } from "./model";
import { validateChatPath } from "./path-validation";
import { readSettings, writeSettings } from "./settings";

const bundleRoot = fileURLToPath(new URL(".", import.meta.url));
const rendererPath = join(bundleRoot, "index.html");
const benchmarkConfigPath = process.env.CHAT_HISTORY_BENCHMARK_CONFIG;
const benchmarkEventsPath = process.env.CHAT_HISTORY_BENCHMARK_EVENTS;
let parserWorker: Worker | undefined;
let parserRequestId = 0;
const parserRequests = new Map<number, {
  reject(error: Error): void;
  resolve(result: unknown): void;
}>();

type ParseResponse = {
  error?: string;
  id: number;
  result?: unknown;
};

function rejectParserRequests(error: Error) {
  for (const request of parserRequests.values()) {
    request.reject(error);
  }
  parserRequests.clear();
}

function getParserWorker() {
  if (parserWorker) {
    return parserWorker;
  }
  const worker = new Worker(new URL("./parser-worker.js", import.meta.url));
  worker.on("message", (response: ParseResponse) => {
    const request = parserRequests.get(response.id);
    if (!request) {
      return;
    }
    parserRequests.delete(response.id);
    if (response.result) {
      request.resolve(response.result);
    } else {
      request.reject(new Error(response.error ?? "Transcript parser worker failed"));
    }
  });
  worker.on("error", (error) => {
    if (parserWorker === worker) {
      parserWorker = undefined;
      rejectParserRequests(error);
    }
  });
  worker.on("exit", (code) => {
    if (parserWorker === worker) {
      parserWorker = undefined;
      rejectParserRequests(new Error(`Transcript parser worker exited with code ${code}`));
    }
  });
  parserWorker = worker;
  return worker;
}

function requestDocument<T>(request: DocumentRequest) {
  return new Promise<T>((resolve, reject) => {
    const id = ++parserRequestId;
    parserRequests.set(id, { reject, resolve: (value) => resolve(value as T) });
    getParserWorker().postMessage({ ...request, id });
  });
}

function assertTrustedSender(event: IpcMainInvokeEvent) {
  const frame = event.senderFrame;
  if (!frame || frame !== event.sender.mainFrame || frame.url.length === 0) {
    throw new Error("Rejected IPC from an untrusted frame");
  }
  try {
    if (fileURLToPath(frame.url) !== rendererPath) {
      throw new Error("Unexpected renderer path");
    }
  } catch {
    throw new Error("Rejected IPC from an untrusted frame");
  }
}

async function getBenchmarkConfig(): Promise<BenchmarkConfig | undefined> {
  if (!benchmarkConfigPath) {
    return undefined;
  }
  const config = JSON.parse(await readFile(benchmarkConfigPath, "utf8")) as BenchmarkConfig;
  if (config.version !== 2 || config.targets.length !== 2) {
    throw new Error("Unsupported chat history benchmark manifest");
  }
  return config;
}

async function emitBenchmarkEvent(event: BenchmarkEvent | { name: "windowShown" }) {
  if (!benchmarkEventsPath) {
    return;
  }
  await appendFile(
    benchmarkEventsPath,
    `${JSON.stringify({ ...event, timestampMs: Date.now() })}\n`,
  );
}

function createWindow() {
  const window = new BrowserWindow({
    backgroundColor: "#00000000",
    titleBarStyle: "hiddenInset",
    vibrancy: "sidebar",
    visualEffectState: "active",
    height: 720,
    minHeight: 460,
    minWidth: 640,
    show: true,
    title: "Chat History — Electron",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: join(bundleRoot, "preload.cjs"),
      sandbox: true,
    },
    width: Number(process.env.CHAT_HISTORY_QA_WIDTH) || 1_280,
  });
  // Present the shell immediately, matching the native benchmark apps.
  void emitBenchmarkEvent({ name: "windowShown" });
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (/^(?:https?|mailto):/i.test(url)) {
      void shell.openExternal(url);
    }
    return { action: "deny" };
  });
  void window.loadFile(rendererPath);
}

ipcMain.handle("chat-history:get-recent", (event, limit: number) => {
  assertTrustedSender(event);
  return getRecentChats(limit);
});
ipcMain.handle("chat-history:open", async (event, provider: ChatProvider, sourcePath: string) => {
  assertTrustedSender(event);
  const path = await validateChatPath(provider, sourcePath);
  return requestDocument<ChatDocument>({ op: "open", provider, path });
});
ipcMain.handle(
  "chat-history:get-rows",
  (event, documentId: string, indices: number[], includeToolPreview = false) => {
    assertTrustedSender(event);
    return requestDocument({ op: "rows", documentId, indices, includeToolPreview });
  },
);
ipcMain.handle("chat-history:get-digest", (event, documentId: string) => {
  assertTrustedSender(event);
  return requestDocument({ op: "digest", documentId });
});
ipcMain.handle("chat-history:get-benchmark-config", (event) => {
  assertTrustedSender(event);
  return getBenchmarkConfig();
});
ipcMain.handle("chat-history:emit-benchmark-event", (event, benchmarkEvent: BenchmarkEvent) => {
  assertTrustedSender(event);
  return emitBenchmarkEvent(benchmarkEvent);
});
ipcMain.handle("chat-history:get-settings", (event) => {
  assertTrustedSender(event);
  return readSettings(app.getPath("userData"));
});
ipcMain.handle("chat-history:save-settings", (event, settings) => {
  assertTrustedSender(event);
  return writeSettings(app.getPath("userData"), settings);
});

void app.whenReady().then(() => {
  getParserWorker();
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("before-quit", () => {
  const worker = parserWorker;
  parserWorker = undefined;
  rejectParserRequests(new Error("Application is quitting"));
  void worker?.terminate();
});
