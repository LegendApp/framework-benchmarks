# File-backed transcript storage — September 19, 2026

The initial benchmark transcript is 228.0 MiB. Earlier implementations decoded messages lazily but several retained the entire UTF-8 file in private memory. That made memory results partly a source-storage comparison, rather than solely a comparison of UI/runtime costs.

## Current implementations

| Apps | Source storage | Integration |
| --- | --- | --- |
| RN | Existing read-only file mapping | Existing custom native C++ document module; not a built-in RN feature |
| AppKit / SwiftUI | Existing Foundation `.mappedIfSafe` | Standard Foundation API |
| GPUI / Tauri | Read-only `memmap2` mapping shared by deferred ranges | Established Rust crate; common Rust parser |
| Compose | Read-only `FileChannel.map` / `ByteBuffer` | Standard JVM API; Jackson validates through a bounded input stream |
| Electron / Deno WebView / Deno CEF | File offsets and positional reads; 64 KiB blocks, at most eight cached blocks | Standard Node-compatible filesystem APIs in the existing parser worker |
| Flutter | File offsets and positional reads; same block/cache bounds | Standard Dart `RandomAccessFile` in the existing parser isolate |

The bounded readers are ordinary application-level buffered I/O. They add no native addon, FFI bridge, shared C++ parser, or dependency for mapping. JSON validation and property scanning use temporary contiguous record buffers to avoid per-byte file-reader overhead; deferred ranges retain file offsets, not those buffers. Requested strings and temporary records can exceed 512 KiB. That limit applies only to cached raw file blocks, not peak or total document memory. Parsed metadata, row descriptors, decoded visible content, syntax spans and renderer allocations still count.

The whole file is still scanned, and JSON records are validated with the existing parser policies. No fixture-specific path, precomputed index, skipped validation, or prelaunch work was introduced. Load-stage timing now measures opening/mapping; buffered I/O can move into scan, parse, row materialization and verification. End-to-end timing remains the comparison metric.

## Ownership

Node/Deno and Dart close the previous active source explicitly before replacement. Failed parsing closes the newly opened handle; superseded JavaScript opens also close their source. Node/Deno additionally use a finalizer as a fallback. The UI receives descriptors and requested rows, not a copy of the file. Existing deferred text and rendering caches retain their normal policy.

Rust mappings are released when their final owning reference is dropped. JVM mappings follow normal garbage collection; no forced collection or unsupported explicit unmapping is used. Mapped input must remain stable while the document is open, matching the native source assumption and immutable benchmark fixtures. Live-file mutation handling is not added by this benchmark change.

## Completed full-suite rerun — September 23–24

The earlier build-tool blocker is resolved. All ten chat apps were rebuilt, including the final JavaScript and Dart readers. The full run completed ten measured timing/memory pairs per app and validated all 100 videos, matching content digests, and unchanged bundle hashes. See the [updated table and conditions](../benchmarks/chat-refresh-2026-09-23/RESULTS.md). The partial September 19 checks below are historical.

## September 19 validation

Rust mapped and owned parsers match both provider fixtures. Kotlin mapping tests pass both expected fixture digests. JavaScript and Dart tests cover Unicode/escape decoding across read blocks, cache eviction/re-reading, empty input, truncated unread ranges, and access after close, alongside the existing parsing/rendering tests. TypeScript checking passes.

An initial version was built in release mode for all seven affected apps. Exploratory runs completed for GPUI, Tauri, Electron and both Deno variants, with one discarded warmup, one recorded measurement and companion unrecorded memory launches. They passed the full transcript content digests. The JavaScript runs exposed excessive per-byte reader overhead, so JavaScript and Dart scanning were subsequently revised to use temporary contiguous record buffers.

The final Rust implementation has passing tests and release/runtime checks. Compose has passing tests and a release build, but its runtime check remains pending. The revised Dart implementation passes all 16 tests. The revised JavaScript implementation passes TypeScript checking and Node checks of both provider fixtures, both full benchmark transcript digests, Unicode and CRLF boundaries, and closed-source behavior. Final JavaScript/Dart release rebuilds and remaining app runs are blocked by stalled build tools; the original JavaScript timings do not represent the revised source. The stalled jobs were cancelled.

| Verified implementation | Initial physical footprint | After switching |
| --- | ---: | ---: |
| GPUI | 76.2 MiB | 96.7 MiB |
| Tauri | 136.2 MiB | 166.7 MiB |

Raw reports: `benchmarks/chat-history/results/2026-09-19T22-55-03.534Z.json` (GPUI) and `2026-09-19T22-55-55.543Z.json` (Tauri). These are single exploratory measurements, not replacements for the published ten-run benchmark. Some current builds include independent window/composer changes; comparisons to older reports cannot isolate storage alone.
