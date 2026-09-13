import type { DocumentRequest } from "../../chat-history-electron/src/document-registry.ts";
import { extname, join } from "jsr:@std/path@1.1.2";
import { getRecentChats } from "../../chat-history-electron/src/catalog.ts";
import {
  type BenchmarkConfig,
  type BenchmarkEvent,
  type ChatDocument,
  type ChatHistoryApi,
  type ChatHistorySettings,
  type ChatProvider,
} from "../../chat-history-electron/src/model.ts";
import { readSettings, writeSettings } from "../../chat-history-electron/src/settings.ts";

type BindingHandler = (...arguments_: unknown[]) => unknown | Promise<unknown>;

type DesktopWindow = {
  bind(name: string, handler: BindingHandler): void;
  focus(): void;
  getSize(): [number, number];
  setSize(width: number, height: number): void;
  hide(): void;
  setTitle(title: string): void;
  show(): void;
};

type DesktopDeno = typeof Deno & {
  BrowserWindow?: new (options: {
    height: number;
    transparentTitlebar?: boolean;
    title: string;
    width: number;
  }) => DesktopWindow;
};

type ParseResponse = {
  error?: string;
  id: number;
  result?: unknown;
};

class TranscriptParserWorker {
  private nextId = 0;
  private readonly pending = new Map<number, {
    reject(error: Error): void;
    resolve(result: unknown): void;
  }>();
  private readonly worker = new Worker(
    new URL("./parser_worker.ts", import.meta.url).href,
    { name: "chat-history-parser", type: "module" },
  );

  constructor() {
    this.worker.addEventListener("message", (event: MessageEvent<ParseResponse>) => {
      const response = event.data;
      const request = this.pending.get(response.id);
      if (!request) {
        return;
      }
      this.pending.delete(response.id);
      if (response.result) {
        request.resolve(response.result);
      } else {
        request.reject(new Error(response.error ?? "Transcript parser worker failed"));
      }
    });
    this.worker.addEventListener("error", (event) => {
      const error = new Error(event.message || "Transcript parser worker failed");
      for (const request of this.pending.values()) {
        request.reject(error);
      }
      this.pending.clear();
    });
  }

  request<T>(request: DocumentRequest) {
    return new Promise<T>((resolve, reject) => {
      const id = ++this.nextId;
      this.pending.set(id, { reject, resolve: (value) => resolve(value as T) });
      this.worker.postMessage({ ...request, id });
    });
  }
}

const contentTypes: Record<string, string> = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
};

function homeDirectory() {
  return (Deno.env.get("CHAT_HISTORY_BENCHMARK_CONFIG") && Deno.env.get("CHAT_HISTORY_BENCHMARK_HOME")) || (Deno.env.get("HOME") ?? Deno.env.get("USERPROFILE") ?? ".");
}

function settingsDirectory() {
  return join(
    homeDirectory(),
    "Library",
    "Application Support",
    "Legend Chat History Deno",
  );
}

async function benchmarkConfig(): Promise<BenchmarkConfig | undefined> {
  const path = Deno.env.get("CHAT_HISTORY_BENCHMARK_CONFIG");
  if (!path) {
    return undefined;
  }
  const config = JSON.parse(await Deno.readTextFile(path)) as BenchmarkConfig;
  if (config.version !== 2 || config.targets.length !== 2) {
    throw new Error("Unsupported chat history benchmark manifest");
  }
  return config;
}

async function emitBenchmarkEvent(
  event: BenchmarkEvent | { name: "windowShown" },
) {
  const path = Deno.env.get("CHAT_HISTORY_BENCHMARK_EVENTS");
  if (path) {
    await Deno.writeTextFile(
      path,
      `${JSON.stringify({ ...event, timestampMs: Date.now() })}\n`,
      { append: true, create: true },
    );
  }
}

async function validatedChatPath(provider: ChatProvider, sourcePath: string) {
  const path = await Deno.realPath(sourcePath);
  const home = homeDirectory();
  const roots = provider === "codex"
    ? [
      join(home, ".codex", "sessions"),
      join(home, ".codex", "archived_sessions"),
    ]
    : [join(home, ".claude", "projects")];
  if (
    extname(path) !== ".jsonl" ||
    !roots.some((root) => path.startsWith(`${root}/`))
  ) {
    throw new Error(
      "Transcript path is outside the provider history directory",
    );
  }
  return path;
}

async function serveStatic(pathname: string) {
  const relativePath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  try {
    const path = new URL(`../dist/${relativePath}`, import.meta.url);
    const data = await Deno.readFile(path);
    return new Response(data, {
      headers: {
        "content-type": contentTypes[extname(relativePath)] ??
          "application/octet-stream",
      },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}

async function serveLocalFile(url: URL) {
  const sourcePath = url.searchParams.get("path");
  if (!sourcePath) {
    return new Response("Bad request", { status: 400 });
  }
  try {
    const path = await Deno.realPath(sourcePath);
    if (!path.startsWith(`${homeDirectory()}/`)) {
      return new Response("Forbidden", { status: 403 });
    }
    return new Response(await Deno.readFile(path), {
      headers: {
        "content-type": contentTypes[extname(path).toLowerCase()] ??
          "application/octet-stream",
      },
    });
  } catch {
    return new Response("Not found", { status: 404 });
  }
}

export async function runDesktop(
  implementationName: ChatHistoryApi["implementationName"],
) {
  const BrowserWindow = (Deno as DesktopDeno).BrowserWindow;
  if (!BrowserWindow) {
    throw new Error("This entrypoint must run through deno desktop");
  }
  const contentWidth = Number(Deno.env.get("CHAT_HISTORY_QA_WIDTH")) || 1_280;
  const window = new BrowserWindow({
    transparentTitlebar: true,
    height: 720,
    title: `Legend Chat History — ${implementationName}`,
    width: contentWidth,
  });
  const parserWorker = new TranscriptParserWorker();
  window.hide();

  let fittedInitialContent = false;
  window.bind("fitInitialContent", (width, height) => {
    // CEF and WebView differ in whether constructor height includes the titlebar.
    // Correct the measured client area once, before mounting the transcript.
    if (!fittedInitialContent) {
      const clientWidth = Number(width), clientHeight = Number(height);
      if (!(clientWidth > 0 && clientHeight > 0)) throw new Error("Invalid client bounds");
      fittedInitialContent = true;
      const [outerWidth, outerHeight] = window.getSize();
      if (clientWidth !== contentWidth || clientHeight !== 720) {
        window.setSize(outerWidth + contentWidth - clientWidth, outerHeight + 720 - clientHeight);
      }
    }
    return [contentWidth, 720];
  });
  window.bind("getImplementationName", () => implementationName);
  window.bind("getBenchmarkConfig", () => benchmarkConfig());
  window.bind(
    "emitBenchmarkEvent",
    (event) => emitBenchmarkEvent(event as BenchmarkEvent),
  );
  window.bind(
    "getRecentChats",
    (limit) => getRecentChats(Number(limit ?? 20), homeDirectory()),
  );
  window.bind("openChat", async (provider, sourcePath) => {
    const chatProvider = provider as ChatProvider;
    const path = await validatedChatPath(chatProvider, String(sourcePath));
    return parserWorker.request<ChatDocument>({ op: "open", provider: chatProvider, path });
  });
  window.bind(
    "getRows",
    (documentId, indices, includeToolPreview) =>
      parserWorker.request({
        op: "rows",
        documentId: String(documentId),
        indices: indices as number[],
        includeToolPreview: includeToolPreview === true,
      }),
  );
  window.bind(
    "getContentDigest",
    (documentId) => parserWorker.request({ op: "digest", documentId: String(documentId) }),
  );
  window.bind("getSettings", () => readSettings(settingsDirectory()));
  window.bind("saveSettings", (settings) => (
    writeSettings(settingsDirectory(), settings as ChatHistorySettings)
  ));
  window.bind("setWindowTitle", (title) => window.setTitle(String(title)));
  window.bind("openExternal", async (url) => {
    const value = String(url);
    if (/^(?:https?|mailto):/i.test(value)) {
      await new Deno.Command("/usr/bin/open", { args: [value] }).output();
    }
  });

  Deno.serve({ hostname: "127.0.0.1", port: 8000 }, (request) => {
    const url = new URL(request.url);
    return url.pathname === "/__local_file" ? serveLocalFile(url) : serveStatic(url.pathname);
  });

  window.show();
  window.focus();
  await emitBenchmarkEvent({ name: "windowShown" });
}
