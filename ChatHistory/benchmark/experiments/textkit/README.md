# Built-in TextKit validation

Both production native apps use ChatHistoryMarkdown.TranscriptTextView. It owns one NSTextStorage, NSLayoutManager, and NSTextContainer for measurement and display. AppKit embeds it directly; SwiftUI uses NSViewRepresentable and retains SwiftUI list/state/layout. Markdown parsing and attribution still use the existing swift-markdown renderer. No external rendering library was added.

Run validation from the repository root:

```
swift test --package-path packages/chat-history-swift --no-parallel
python3 benchmarks/chat-history/experiments/verify-appkit-layout.py
python3 benchmarks/chat-history/experiments/verify-swiftui-textkit.py
```

The unit suite passed 16 tests. The AppKit harness covers 12 resize/top/tail configurations plus the real 1280-point window and 260-point sidebar. The SwiftUI harness builds the production source with an alternate entry point, checks wide/narrow/wide text preservation and bounds, and verifies a short user message stays compact inside MessageLayout. Logs are retained here.

The first parallel unit-suite attempt hit an existing wall-clock-sensitive demo-stream test while compilation and a main-actor text test were competing. The complete suite passed with test parallelism disabled. An initial wrapping fixture also needed a longer paragraph to exercise narrow-width wrapping; the current test does so.

`provenance.json` records production source/binary hashes and excluded exploratory batches. Do not mix those batches with the final run. Benchmark recordings and JSON stay under the ignored results directory; the tracked TextKit results report links the final batch.

This change preserves the existing Markdown styling and content model. It does not certify every Markdown feature equivalent to RN. In particular, the existing native table renderer remains text rows rather than RN's independent table cells, and window/list/scheduling policies were not changed by this patch.
