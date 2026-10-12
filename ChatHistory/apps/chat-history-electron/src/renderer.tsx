import { LegendList, type LegendListRef, useRecyclingState } from "@legendapp/list/react";
import {
  Children,
  isValidElement,
  memo,
  type ReactNode,
  type RefObject,
  StrictMode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { createRoot } from "react-dom/client";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  type BenchmarkConfig,
  type BenchmarkEvent,
  type ChatDocument,
  type ChatHistorySettings,
  type ChatRow,
  type ChatSummary,
  defaultChatHistorySettings,
  normalizeChatHistorySettings,
  normalizedContentDigest,
  type OpenChatResult,
} from "./model";
import { RowLoader } from "./row-loader";
import "./styles.css";
import { codePaneSource, highlightCode } from "./syntax-highlighting";

const noLocalHistoriesMessage = "No local Codex or Claude transcripts found.";

const fallbackSettingsKey = "legend-chat-history-settings";

type SelectionState =
  | { status: "idle" }
  | { id: string; status: "loading" }
  | {
    discoveryMs?: number;
    id: string;
    openedAt: number;
    phase?: "initial" | "switch";
    result: OpenChatResult;
    status: "ready";
  }
  | { error: string; id: string; status: "error" };

function applyAppearance(appearance: ChatHistorySettings["appearance"]) {
  document.documentElement.dataset.appearance = appearance;
  document.documentElement.style.colorScheme = appearance === "system" ? "light dark" : appearance;
}

async function readSettings() {
  if (window.chatHistory.getSettings) {
    return normalizeChatHistorySettings(await window.chatHistory.getSettings());
  }
  try {
    return normalizeChatHistorySettings(
      JSON.parse(localStorage.getItem(fallbackSettingsKey) ?? "null"),
    );
  } catch {
    return { ...defaultChatHistorySettings };
  }
}

async function persistSettings(settings: ChatHistorySettings) {
  if (window.chatHistory.saveSettings) {
    await window.chatHistory.saveSettings(settings);
  } else {
    localStorage.setItem(fallbackSettingsKey, JSON.stringify(settings));
  }
}

function imageSource(source: string) {
  if (window.chatHistory.resolveImageSource) {
    return window.chatHistory.resolveImageSource(source);
  }
  return /^[a-z][a-z\d+.-]*:/i.test(source)
    ? source
    : `file://${source.split("/").map(encodeURIComponent).join("/")}`;
}

function markdownImageSource(source: string) {
  return window.chatHistory.resolveMarkdownImageSource?.(source) ?? source;
}

function relativeDate(timestamp: number) {
  const minutes = Math.floor(Math.max(0, Date.now() - timestamp) / 60_000);
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return days < 7
    ? `${days}d`
    : new Date(timestamp).toLocaleDateString(undefined, { day: "numeric", month: "short" });
}

function Timing({ firstPaintMs, result }: { firstPaintMs?: number; result: OpenChatResult }) {
  const { document, bridgeRoundTripMs } = result;
  const bridgeOverheadMs = Math.max(0, bridgeRoundTripMs - document.timing.nativeTotalMs);
  return (
    <div className="timing">
      <span>{(document.sourceBytes / 1_024).toFixed(1)} KB</span>
      <span>{document.recordCount} records</span>
      <span>{document.rows.length} rows</span>
      <span>load {document.timing.loadMs.toFixed(2)} ms</span>
      <span>scan {document.timing.scanMs.toFixed(2)} ms</span>
      <span>parse {document.timing.parseMs.toFixed(2)} ms</span>
      <span>bridge {bridgeRoundTripMs.toFixed(2)} ms</span>
      <span>bridge overhead {bridgeOverheadMs.toFixed(2)} ms</span>
      <span>
        {firstPaintMs === undefined ? "paint pending" : `paint ${firstPaintMs.toFixed(2)} ms`}
      </span>
    </div>
  );
}

function MessageImage({
  alt = "Attached image",
  resolveSource = imageSource,
  source,
}: {
  alt?: string;
  resolveSource?: (source: string) => string;
  source: string;
}) {
  const [failed, setFailed] = useRecyclingState(false);
  if (failed) {
    return <div className="attachment">Image or attachment unavailable</div>;
  }
  return (
    <img
      alt={alt}
      className="message-image"
      loading="lazy"
      onError={() => setFailed(true)}
      src={resolveSource(source)}
    />
  );
}

function CodePane({ children }: { children: ReactNode }) {
  const child = Children.toArray(children)[0];
  const props = isValidElement<{ className?: string; children?: ReactNode }>(child)
    ? child.props
    : undefined;
  const language = props?.className?.replace(/^language-/, "") ?? "Code";
  const text = codePaneSource(String(props?.children ?? ""));
  const highlighted = useMemo(() => highlightCode(text, language), [text, language]);
  return (
    <div className="code-pane">
      <header>
        <span>{language.charAt(0).toUpperCase() + language.slice(1)}</span>
        <button onClick={() => void navigator.clipboard.writeText(text)}>Copy</button>
      </header>
      <pre><code dangerouslySetInnerHTML={{ __html: highlighted }} /></pre>
    </div>
  );
}

const RichMarkdown = memo(function RichMarkdown({ children, loadImages }: { children: string; loadImages: boolean }) {
  return (
    <div className="markdown">
      <ReactMarkdown
        components={{
          pre: ({ children }) => <CodePane>{children}</CodePane>,
          table: ({ children }) => (
            <div className="table-scroll">
              <table>{children}</table>
            </div>
          ),
          td: ({ children, style, align }) => (
            <td style={{ ...style, textAlign: align === "center" || align === "right" ? align : style?.textAlign ?? "left" }}>
              <div className="table-cell">{children}</div>
            </td>
          ),
          th: ({ children, style, align }) => (
            <th style={{ ...style, textAlign: align === "center" || align === "right" ? align : style?.textAlign ?? "left" }}>
              <div className="table-cell">{children}</div>
            </th>
          ),
          a: ({ children, href }) => <a href={href} rel="noreferrer" target="_blank">{children}</a>,
          img: ({ alt, src }) =>
            loadImages && src
              ? (
                <MessageImage
                  alt={alt ?? "Embedded image"}
                  resolveSource={markdownImageSource}
                  source={src}
                />
              )
              : <span className="attachment">Image or attachment omitted</span>,
        }}
        remarkPlugins={[remarkGfm]}
      >
        {children}
      </ReactMarkdown>
    </div>
  );
});

function FileChanges({ row }: { row: ChatRow }) {
  const [expanded, setExpanded] = useRecyclingState(false);
  const additions = row.fileChanges.reduce((total, file) => total + file.additions, 0);
  const deletions = row.fileChanges.reduce((total, file) => total + file.deletions, 0);
  const visibleFiles = expanded ? row.fileChanges : row.fileChanges.slice(0, 3);
  const hiddenCount = row.fileChanges.length - 3;
  return (
    <article className="row files-row">
      <header>
        <div className="file-icon">+</div>
        <div>
          <strong>
            Edited {row.fileChanges.length} {row.fileChanges.length === 1 ? "file" : "files"}
          </strong>
          <div>
            <span className="additions">+{additions}</span>{" "}
            <span className="deletions">−{deletions}</span>
          </div>
        </div>
      </header>
      <div className="file-list">
        {visibleFiles.map((file) => (
          <div className="file-change" key={file.path}>
            <span title={file.path}>{file.path}</span>
            <span>
              <b className="additions">+{file.additions}</b>{" "}
              <b className="deletions">−{file.deletions}</b>
            </span>
          </div>
        ))}
      </div>
      {hiddenCount > 0
        ? (
          <button className="expand-files" onClick={() => setExpanded(!expanded)} type="button">
            {expanded ? "Show less" : `Show ${hiddenCount} more files`}
          </button>
        )
        : null}
    </article>
  );
}

function ToolRow({ row, loadPreview }: { row: ChatRow; loadPreview?: () => Promise<string> }) {
  const [preview, setPreview] = useRecyclingState<string | undefined>(undefined);
  const [previewError, setPreviewError] = useRecyclingState<string | undefined>(undefined);
  const [expanded, setExpanded] = useRecyclingState(false);
  useEffect(() => {
    if (!expanded || preview !== undefined || !loadPreview) return;
    let active = true;
    void loadPreview().then((text) => {
      if (active) setPreview(text);
    }, (error) => {
      if (active) setPreviewError(String(error));
    });
    return () => {
      active = false;
    };
  }, [expanded, loadPreview, preview, setPreview, setPreviewError]);
  return (
    <details
      className="row tool-row"
      onToggle={(event) => {
        const open = event.currentTarget.open;
        setExpanded(open);
      }}
      open={expanded}
    >
      <summary>{row.toolName}</summary>
      {expanded ? <pre>{previewError ?? preview ?? row.toolPreview}</pre> : null}
    </details>
  );
}

function TranscriptRow(
  { loadImages, row, loadPreview }: {
    loadImages: boolean;
    row: ChatRow;
    loadPreview?: () => Promise<string>;
  },
) {
  if (row.kind === "files") {
    return <FileChanges row={row} />;
  }
  if (row.kind === "tool") {
    return <ToolRow row={row} loadPreview={loadPreview} />;
  }
  return (
    <article
      className={row.kind === "user" ? "row message-row user-row" : "row message-row assistant-row"}
    >
      <div className="message-content">
        {loadImages
          ? row.imageSources.map((source) => <MessageImage key={source} source={source} />)
          : null}
        {row.markdown ? <RichMarkdown loadImages={loadImages}>{row.markdown}</RichMarkdown> : null}
        {row.hasImagePlaceholder || (!loadImages && row.imageSources.length > 0)
          ? <div className="attachment">Image or attachment omitted</div>
          : null}
      </div>
    </article>
  );
}

function DeferredTranscriptRow({ index, loader, loadImages, row }: {
  index: number;
  loader: RowLoader;
  loadImages: boolean;
  row: ChatRow;
}) {
  const [loaded, setLoaded] = useRecyclingState<ChatRow | undefined>(undefined);
  const [error, setError] = useRecyclingState<string | undefined>(undefined);
  useEffect(() => {
    let active = true;
    void loader.get(index).then((value) => {
      if (active) setLoaded(value);
    }, (reason) => {
      if (active) setError(String(reason));
    });
    return () => {
      active = false;
    };
  }, [index, loader, setLoaded, setError]);
  const loadPreview = useCallback(() => loader.preview(index), [index, loader]);
  if (error) return <div className="row error" data-row-error>{error}</div>;
  if (row.deferred && (!loaded || loaded.id !== row.id)) {
    return <div className="row pending-row" data-row-pending aria-busy="true" />;
  }
  return <TranscriptRow loadImages={loadImages} row={loaded ?? row} loadPreview={loadPreview} />;
}

const transcriptStyle = { height: "100%" } as const;
const transcriptContentStyle = { paddingTop: 64, paddingBottom: 112 } as const;
const chatRowKey = (row: ChatRow) => row.id;
const chatRowType = (row: ChatRow) => row.kind;

function Transcript({
  document,
  listRef,
  loadImages,
  onLoad,
}: {
  document: ChatDocument;
  listRef: RefObject<LegendListRef | null>;
  loadImages: boolean;
  onLoad: () => void;
}) {
  const loader = useMemo(
    () =>
      new RowLoader(
        document,
        (id, indices, includeToolPreview) =>
          window.chatHistory.getRows(id, indices, includeToolPreview),
      ),
    [document],
  );
  const renderItem = useCallback(
    ({ item, index }: { item: ChatRow; index: number }) => (
      <DeferredTranscriptRow index={index} loader={loader} loadImages={loadImages} row={item} />
    ),
    [loadImages, loader],
  );
  return (
    <LegendList
      contentContainerStyle={transcriptContentStyle}
      dataKey={document.path}
      data={document.rows}
      estimatedItemSize={500}
      drawDistance={250}
      getItemType={chatRowType}
      initialScrollAtEnd
      maintainScrollAtEnd
      keyExtractor={chatRowKey}
      onLoad={onLoad}
      ref={listRef}
      recycleItems
      renderItem={renderItem}
      style={transcriptStyle}
    />
  );
}

async function waitForVisibleContent(useAnimationFrames = true) {
  await document.fonts?.ready;
  // Row height alone can be a deferred placeholder. Wait for the actual viewport content.
  for (let attempt = 0;; attempt++) {
    await new Promise<void>((resolve) => window.setTimeout(resolve, 16));
    if (document.querySelector(".transcript [data-row-error]")) {
      throw new Error("Viewport row loading failed");
    }
    if (!document.querySelector(".transcript [data-row-pending]")) break;
    if (attempt >= 1875) throw new Error("Viewport rows did not finish loading");
  }
  const images = [...document.querySelectorAll<HTMLImageElement>(".transcript img")];
  await Promise.all(
    images.map((image) =>
      image.complete ? undefined : new Promise<void>((resolve) => {
        image.addEventListener("load", () => resolve(), { once: true });
        image.addEventListener("error", () => resolve(), { once: true });
      })
    ),
  );
  if (useAnimationFrames) {
    await new Promise<void>((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
    );
  } else {
    await new Promise<void>((resolve) => window.setTimeout(resolve, 32));
  }
}

function usesWebKitLayoutPolling() {
  return window.chatHistory.implementationName === "Tauri" ||
    window.chatHistory.implementationName === "Deno WebView";
}

function ReadyTranscript(
  { benchmarkConfig, discoveryMs, onBenchmarkEvent, openedAt, phase, result, settings }: {
    benchmarkConfig?: BenchmarkConfig;
    discoveryMs?: number;
    onBenchmarkEvent?: (event: BenchmarkEvent) => Promise<void>;
    openedAt: number;
    phase?: "initial" | "switch";
    result: OpenChatResult;
    settings: ChatHistorySettings;
  },
) {
  const [firstPaintMs, setFirstPaintMs] = useState<number>();
  const [readinessError, setReadinessError] = useState<string>();
  const reported = useRef(false);
  const listRef = useRef<LegendListRef>(null);
  const handleLoad = useCallback(() => {
    if (reported.current) {
      return;
    }
    reported.current = true;
    const settleInitialTail = async () => {
      const deadline = performance.now() + 30_000;
      for (;;) {
        await waitForVisibleContent(!usesWebKitLayoutPolling());
        const state = listRef.current?.getState();
        if (!state) return false; // This document was unmounted while rows were loading.
        if (state.end === result.document.rows.length - 1 && state.isAtEnd) return true;
        if (performance.now() > deadline) throw new Error("Initial transcript tail did not settle");
        // Deferred rows can grow after the list's initial placement. Let the list
        // resolve its end target again; verify the measured result before ready.
        void listRef.current?.scrollToEnd({ animated: false });
      }
    };
    void settleInitialTail().then((settled) => {
      if (!settled) return;
      const durationMs = performance.now() - openedAt;
      setFirstPaintMs(durationMs);
      if (phase) {
        void onBenchmarkEvent?.({
          discoveryMs: phase === "initial" ? discoveryMs : undefined,
          durationMs,
          name: "contentReady",
          path: result.document.path,
          phase,
          recordCount: result.document.recordCount,
          rowCount: result.document.rows.length,
          sourceBytes: result.document.sourceBytes,
          timing: result.document.timing,
        }).then(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0))).then(
          async () => (
            onBenchmarkEvent?.({
              contentDigest: result.document.documentId
                ? await window.chatHistory.getContentDigest(result.document.documentId)
                : normalizedContentDigest(result.document.rows),
              name: "contentDigest",
              path: result.document.path,
              phase,
            })
          ),
        );
      }
    }).catch((error) => setReadinessError(String(error)));
  }, [discoveryMs, onBenchmarkEvent, openedAt, phase, result.document]);
  useEffect(() => {
    let timeout = 0;
    const waitForLaidOutRow = () => {
      const row = document.querySelector<HTMLElement>(".transcript .row");
      if (row?.getBoundingClientRect().height) {
        handleLoad();
      } else {
        timeout = window.setTimeout(waitForLaidOutRow, 16);
      }
    };
    timeout = window.setTimeout(waitForLaidOutRow, 0);
    return () => window.clearTimeout(timeout);
  }, [handleLoad]);
  useEffect(() => {
    if (phase !== "initial" || !benchmarkConfig || firstPaintMs === undefined) {
      return;
    }
    const timeout = window.setTimeout(() => {
      const startedAt = performance.now();
      listRef.current?.scrollToOffset({ animated: false, offset: 0 });
      void waitForVisibleContent(!usesWebKitLayoutPolling()).then(() =>
        onBenchmarkEvent?.({
          durationMs: performance.now() - startedAt,
          name: "viewportReady",
          path: result.document.path,
          phase: "top",
        })
      );
    }, benchmarkConfig.topDelayMs);
    return () => window.clearTimeout(timeout);
  }, [benchmarkConfig, firstPaintMs, onBenchmarkEvent, phase, result.document.path]);
  return (
    <div className="transcript-shell">
      {readinessError ? <div role="alert" className="error">{readinessError}</div> : null}
      {settings.showPerformanceMetrics
        ? <Timing firstPaintMs={firstPaintMs} result={result} />
        : null}
      <div className="transcript">
        <Transcript
          document={result.document}
          listRef={listRef}
          loadImages={settings.loadImages}
          onLoad={handleLoad}
        />
      </div>
    </div>
  );
}

function Sidebar({ onSelect, selectedId, summaries }: {
  onSelect: (summary: ChatSummary) => void;
  selectedId?: string;
  summaries: ChatSummary[];
}) {
  return (
    <aside className="sidebar">
      {(["codex", "claude"] as const).map((provider) => (
        <section key={provider}>
          <h2>{provider === "codex" ? "Codex" : "Claude"}</h2>
          {summaries.filter((summary) => summary.provider === provider).map((summary) => (
            <button
              className={summary.id === selectedId ? "selected" : ""}
              key={summary.id}
              onClick={() => onSelect(summary)}
              type="button"
            >
              <span>{summary.title}</span>
              <time>{relativeDate(summary.updatedAt)}</time>
            </button>
          ))}
        </section>
      ))}
    </aside>
  );
}

function SettingsModal({ onCancel, onSave, settings }: {
  onCancel: () => void;
  onSave: (settings: ChatHistorySettings) => void;
  settings: ChatHistorySettings;
}) {
  const [draft, setDraft] = useState(settings);
  return (
    <div aria-modal="true" className="modal-backdrop" role="dialog">
      <form
        className="settings-modal"
        onSubmit={(event) => {
          event.preventDefault();
          onSave(draft);
        }}
      >
        <header>
          <h2>Settings</h2>
          <button aria-label="Close settings" onClick={onCancel} type="button">×</button>
        </header>
        <label>
          <span>Appearance</span>
          <select
            onChange={(event) =>
              setDraft({
                ...draft,
                appearance: event.target.value as ChatHistorySettings["appearance"],
              })}
            value={draft.appearance}
          >
            <option value="system">System</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </label>
        <label>
          <span>Recent chats</span>
          <select
            onChange={(event) =>
              setDraft({ ...draft, recentChatLimit: Number(event.target.value) as 20 | 50 | 100 })}
            value={draft.recentChatLimit}
          >
            <option value={20}>20</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
          </select>
        </label>
        <label className="toggle">
          <input
            checked={draft.restoreSelection}
            onChange={(event) => setDraft({ ...draft, restoreSelection: event.target.checked })}
            type="checkbox"
          />
          <span>Restore the last selected chat</span>
        </label>
        <label className="toggle">
          <input
            checked={draft.loadImages}
            onChange={(event) => setDraft({ ...draft, loadImages: event.target.checked })}
            type="checkbox"
          />
          <span>Load attached images</span>
        </label>
        <label className="toggle">
          <input
            checked={draft.showPerformanceMetrics}
            onChange={(event) =>
              setDraft({ ...draft, showPerformanceMetrics: event.target.checked })}
            type="checkbox"
          />
          <span>Show performance metrics</span>
        </label>
        <footer>
          <button onClick={onCancel} type="button">Cancel</button>
          <button className="primary" type="submit">Save</button>
        </footer>
      </form>
    </div>
  );
}

function App() {
  const [benchmarkConfig, setBenchmarkConfig] = useState<BenchmarkConfig>();
  const [summaries, setSummaries] = useState<ChatSummary[]>([]);
  const [catalogMs, setCatalogMs] = useState<number>();
  const [selection, setSelection] = useState<SelectionState>({ status: "idle" });
  const [settings, setSettings] = useState(defaultChatHistorySettings);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [catalogError, setCatalogError] = useState<string>();
  const selectionGenerationRef = useRef(0);

  async function select(
    summary: ChatSummary,
    activeSettings = settings,
    phase?: "initial" | "switch",
    discoveryMs?: number,
  ) {
    const generation = ++selectionGenerationRef.current;
    const startedAt = performance.now();
    setSelection({ id: summary.id, status: "loading" });
    const nextSettings = {
      ...activeSettings,
      selectedId: activeSettings.restoreSelection ? summary.id : undefined,
    };
    setSettings(nextSettings);
    if (!phase) {
      void persistSettings(nextSettings);
    }
    try {
      const result = await window.chatHistory.openChat(summary.provider, summary.path);
      if (generation === selectionGenerationRef.current) {
        setSelection({
          discoveryMs,
          id: summary.id,
          openedAt: startedAt,
          phase,
          result,
          status: "ready",
        });
      }
    } catch (error) {
      if (generation === selectionGenerationRef.current) {
        setSelection({
          error: error instanceof Error ? error.message : String(error),
          id: summary.id,
          status: "error",
        });
      }
    }
  }

  async function refreshCatalog(activeSettings: ChatHistorySettings, preferredId?: string) {
    try {
      const result = await window.chatHistory.getRecentChats(activeSettings.recentChatLimit);
      setSummaries(result.summaries);
      setCatalogMs(result.nativeTotalMs);
      setCatalogError(undefined);
      const initialId = activeSettings.restoreSelection
        ? preferredId ?? activeSettings.selectedId
        : undefined;
      const initial = result.summaries.find((summary) => summary.id === initialId) ??
        result.summaries[0];
      if (initial) {
        await select(initial, activeSettings);
      } else {
        selectionGenerationRef.current += 1;
        setSelection({ status: "idle" });
      }
    } catch (error) {
      setCatalogError(error instanceof Error ? error.message : String(error));
    }
  }

  useEffect(() => {
    let active = true;
    void Promise.all([readSettings(), window.chatHistory.getBenchmarkConfig?.()]).then(
      async ([loadedSettings, benchmark]) => {
        if (!active) return;
        if (benchmark) {
          const benchmarkSettings: ChatHistorySettings = {
            ...defaultChatHistorySettings,
            appearance: benchmark.appearance ?? "system",
            loadImages: benchmark.loadImages,
            restoreSelection: false,
          };
          setBenchmarkConfig(benchmark);
          setSettings(benchmarkSettings);
          applyAppearance(benchmarkSettings.appearance);
          const discoveryStartedAt = performance.now();
          const result = await window.chatHistory.getRecentChats(Number.MAX_SAFE_INTEGER);
          const discoveryMs = performance.now() - discoveryStartedAt;
          const targets = benchmark.targets.map((target) =>
            result.summaries.find(
              (summary) => summary.id === target.id && summary.provider === target.provider,
            )
          );
          if (targets.some((target) => !target)) {
            throw new Error(
              "A pinned benchmark chat was not found during native history discovery",
            );
          }
          const resolvedTargets = targets as [ChatSummary, ChatSummary];
          const visibleSummaries = result.summaries.slice(
            0,
            defaultChatHistorySettings.recentChatLimit,
          );
          for (const target of resolvedTargets) {
            if (!visibleSummaries.some((summary) => summary.id === target.id)) {
              visibleSummaries.push(target);
            }
          }
          setSummaries(visibleSummaries);
          setCatalogMs(result.nativeTotalMs);
          await select(resolvedTargets[0], benchmarkSettings, "initial", discoveryMs);
          return;
        }
        setSettings(loadedSettings);
        applyAppearance(loadedSettings.appearance);
        await refreshCatalog(loadedSettings);
      },
    ).catch((error) => {
      if (active) {
        setCatalogError(error instanceof Error ? error.message : String(error));
        setCatalogMs(0);
      }
    });
    return () => {
      active = false;
    };
  }, []);

  async function saveSettings(nextValue: ChatHistorySettings) {
    const nextSettings = normalizeChatHistorySettings({
      ...nextValue,
      selectedId: nextValue.restoreSelection ? nextValue.selectedId : undefined,
    });
    const limitChanged = nextSettings.recentChatLimit !== settings.recentChatLimit;
    setSettings(nextSettings);
    applyAppearance(nextSettings.appearance);
    await persistSettings(nextSettings);
    setSettingsOpen(false);
    if (limitChanged) {
      await refreshCatalog(nextSettings, selection.status === "idle" ? undefined : selection.id);
    }
  }

  const selectedId = selection.status === "idle" ? undefined : selection.id;
  const selectedTitle = summaries.find((summary) => summary.id === selectedId)?.title ??
    "Legend Chat History";
  const implementationName = window.chatHistory.implementationName;
  const idleMessage = catalogMs === undefined
    ? "Scanning recent chats…"
    : summaries.length === 0
    ? noLocalHistoriesMessage
    : "Select a conversation";

  async function handleBenchmarkEvent(event: BenchmarkEvent) {
    await window.chatHistory.emitBenchmarkEvent?.(event);
    if (event.name === "viewportReady" && event.phase === "top" && benchmarkConfig) {
      const secondary = summaries.find((summary) => summary.id === benchmarkConfig.targets[1].id);
      if (!secondary) {
        return;
      }
      window.setTimeout(() => {
        void select(secondary, settings, "switch");
      }, benchmarkConfig.switchDelayMs);
    }
  }

  useEffect(() => {
    document.title = `${selectedTitle} — ${implementationName}`;
  }, [implementationName, selectedTitle]);

  return (
    <main>
      <Sidebar
        onSelect={(summary) => void select(summary)}
        selectedId={selectedId}
        summaries={summaries}
      />
      <section className="content">
        <header>
          <strong>{selectedTitle}</strong>
          <div>
            {settings.showPerformanceMetrics
              ? (
                <span>
                  {catalogMs === undefined
                    ? "Loading catalog…"
                    : `catalog ${catalogMs.toFixed(2)} ms`}
                </span>
              )
              : null}
            <button
              aria-label="Open settings"
              className="settings-button"
              onClick={() => setSettingsOpen(true)}
              type="button"
            >
              ⚙
            </button>
          </div>
        </header>
        {catalogError ? <div className="empty error">{catalogError}</div> : null}
        {!catalogError && selection.status === "idle"
          ? <div className="empty">{idleMessage}</div>
          : null}
        {!catalogError && selection.status === "loading"
          ? <div className="empty">Loading and parsing natively…</div>
          : null}
        {!catalogError && selection.status === "error"
          ? <div className="empty error">{selection.error}</div>
          : null}
        {!catalogError && selection.status === "ready"
          ? (
            <ReadyTranscript
              key={`${selection.id}:${selection.openedAt}`}
              benchmarkConfig={benchmarkConfig}
              discoveryMs={selection.discoveryMs}
              onBenchmarkEvent={selection.phase ? handleBenchmarkEvent : undefined}
              openedAt={selection.openedAt}
              phase={selection.phase}
              result={selection.result}
              settings={settings}
            />
          )
          : null}
        <div className="composer">
          <span>Send a test message that doesn't actually do anything</span>
          <button disabled aria-label="Send message">↑</button>
        </div>
      </section>
      {settingsOpen
        ? (
          <SettingsModal
            onCancel={() => setSettingsOpen(false)}
            onSave={(value) => void saveSettings(value)}
            settings={settings}
          />
        )
        : null}
    </main>
  );
}

export function mountChatHistory() {
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}
