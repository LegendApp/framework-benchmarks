# Native chat document implementations

AppKit and SwiftUI now default to a Swift implementation of the RN document algorithm. Catalog discovery remains in `Catalog.swift`, using Swift/Foundation; it was not replaced with RN's C++ catalog scanner.

`SwiftDocument.swift` owns the source through Foundation `Data(contentsOf:options: .mappedIfSafe)`. It scans newline offsets, selectively reads JSON fields, retains text ranges, follows Claude's selected parent chain, aggregates file changes by path, and groups tool activity. Known Codex timestamp/type/payload envelopes (with or without ordinal) use the same shallow fast path as RN. Reordered envelopes use the general member scan. Large non-string tool outputs are skipped without recursively reading their contents.

Only owned Data and integer offsets escape parsing. Unsafe JSON views stay inside `withUnsafeBytes`. Message text and collapsed tool previews are decoded on demand. `ChatRows` is a random-access collection with numeric identity; it caches metadata only for requested rows. Each requested row independently caches Markdown and preview text. Validation digests bypass the UI caches.

The former eager Swift implementation remains in `Parser.swift` as a test reference. The vendored C++ implementation remains an alternate backend:

```sh
CHAT_HISTORY_PARSER=swift bun run chat-history:appkit
CHAT_HISTORY_PARSER=cpp bun run chat-history:swiftui
CHAT_HISTORY_PARSER=cpp bun run benchmarks/chat-history/run.ts --app appkit,swiftui
```

Both backends use the same native UI code and lazy collection interface. The environment variable changes document parsing, not catalog discovery. Native content-ready events identify the selected backend, and benchmark JSON records `nativeParser`. Calling `openChatFile(..., parser: .swift)` or `.cpp` explicitly overrides the environment.

Tests compare Swift and C++ content digests, warnings, row identity, source lifetime, lazy metadata/text access, JSON escaping, reordered envelopes, non-string outputs, and the optional full pinned corpus:

```sh
CHAT_HISTORY_TEST_FIXTURES="$PWD/benchmarks/chat-history/fixtures.local.json" \
  swift test -c release --package-path packages/chat-history-swift
```

## UI comparison policy

The apps use the RN chat app's body/heading sizes and line heights, Menlo code font, default display colors, horizontal row padding, 82% user / 92% assistant maximum widths, user bubble padding, collapsed file count, and 64 KiB tool preview limit. Short user bubbles fit their content. Both include a local, unsaved composer demo with the same response text and stream delays, an 88-point composer footprint, and 112 points of trailing clearance. Performance metrics are opt-in so they do not remove transcript viewport space during benchmarks. The native benchmark sidebar occupies 260 points including macOS 26's eight-point floating-pane inset, matching RN's viewport; ordinary sidebars remain resizable.

AppKit measures wrapping labels at their current available width and remeasures after resizing. SwiftUI supplies the equivalent width through Layout, removes the default horizontal List margin, caches rendered Markdown, and declares row/text spacing explicitly instead of asking Text for default spacing. On macOS 26 it maps the paragraph line heights to SwiftUI’s own attributed line-height API; simply bridging NSParagraphStyle does not affect Text layout. Tools decode previews only after expansion. Both apps retain their native list implementations.

These are equivalent data and layout policies, not identical renderers. RN uses enriched Markdown, AppKit uses attributed text controls, and SwiftUI uses Text backed by swift-markdown output. Code-block chrome, tables, image presentation, platform controls, and text-layout details still differ. The native demo currently follows the end while streaming; it does not reproduce RN's special user-message anchoring experiment. That interactive demo is outside the startup/top/switch benchmark workload. A content digest proves normalized content parity, not pixel-identical rendering or identical amounts of layout work.
