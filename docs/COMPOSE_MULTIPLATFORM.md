# Compose Multiplatform benchmark apps

Two independently packaged Kotlin/JVM apps use Compose Multiplatform 1.10.3, Kotlin 2.3.10, Gradle 8.14.3, and ARM64 Temurin 21.0.8+9. They target the desktop JVM, the normal Compose desktop architecture. This repository does not yet provide Android, iOS, web, Windows or Linux benchmark exports.

## Reuse and implementation

The applications reuse the harness, fixtures, grammar installation/provenance, language/size policy, and expected normalized digests. Chat History implements the same normalization algorithm in Kotlin rather than calling a native parser or shipping another framework. Its catalog uses Java/Kotlin filesystem APIs and metadata indexes; missing benchmark targets use the same expanded catalog search as the other apps.

A document retains its UTF-8 byte array. Jackson Core 2.18.5 validates each JSON record with its streaming parser, including ignored values; JSON objects then index value ranges without decoding large string contents. Unescaped strings decode directly from UTF-8, with kotlinx.serialization handling escaped strings. Visible Markdown and expanded tool previews decode on demand; the post-readiness verification digest decodes uncached strings without populating every row cache. Parsing and discovery run on Dispatchers.IO. Selection cancels stale publication; the old document and rendering cache are released on switch.

Compose LazyColumn renders rows on demand, initially at the bottom. CommonMark 0.24.0 parses visible messages, with GFM tables, strikethrough, task items, headings, emphasis, links, quotes, lists, and fenced code. Parsed nodes and lazily requested code highlighting are cached per visited row for the selected document, surviving lazy-row disposal. LazyColumn uses row-kind content types for composition reuse. Compose text layout, native lazy-list preparation and Skia drawing remain measured framework work. Normal Compose prefetch is retained; equal offscreen row counts are not claimed.

The syntax pack uses Highlights 1.1.0 for programming languages and RSyntaxTextArea 3.6.0 lexers for CSS, JSON, XML, YAML and Markdown. These are actual language tokenizers, not precolored fixtures. The shared policy controls explicit aliases, 51,200-byte / 2,000-line limits, plain-text fallback, foreground-only styling and terminal-newline normalization. No automatic language detection or whole-history pre-highlighting runs. The external pack includes the engine dependencies as well as lexer definitions; all pack bytes count toward installed size.

The composer uses a Compose graphics layer with a 10-point Gaussian backdrop blur and the shared 40% dark / 44% light tint. It samples the rendered transcript, not a cached screenshot. It is conventional blur, not Liquid Glass. Sidebar is a plain 260-point panel. Tools and file details begin collapsed. Images remain placeholders: this candidate targets the shared text-only benchmark, not an image-enabled product comparison. The composer is inert, like the other benchmark composers.

## Release optimization

Both apps use Compose's `createReleaseDistributable` task: ProGuard shrinking/optimization plus a jlink runtime containing selected JDK modules, without debug data, headers or manual pages. No development Gradle process, debugger, system JDK or hot reload is needed at launch. Hello World has no dependency on the chat or syntax modules.

The JVM uses normal JIT and garbage collection settings. No forced GC, benchmark-only cached document, prewarmed class state, reduced parsing/highlighting policy, or prerecorded rendering is used. Chat preserves Kotlin/coroutine entry points needed by the external syntax classloader. Package sizes include the bundled JVM and Skia/Skiko assets. The pinned toolchain is installed locally with checksummed archives; packaging signs the local `.app` ad hoc like the other benchmark exports.

## Running and validation

```sh
bun run benchmark:build --app compose
bun run benchmark:run --app compose
scripts/with-local-compose.sh :chat:test
```

The standard build command previews the plan and asks for confirmation. Pass `--yes` for unattended builds. The runner never builds. Select one workload with `--suite hello-world` or `--suite chat-history`. Grammar packs are exported outside the bundle and installed into the shared verified runtime cache by the runner, using `BENCHMARK_GRAMMAR_ROOT`.

Tests compare both provider fixture digests to the established Rust/Swift normalization, test Unicode/deferred decoding, parse representative rich Markdown, exercise every shared syntax alias, and verify size/unknown-language fallback preserves source text. Single-launch smoke checks are validation, not a performance ranking. Existing published tables predate this candidate; publish new numbers only after a quiet full run with two warmups, ten measured iterations, external video evidence and separate memory launches.

## Validation on September 18, 2026

- Both ARM64 release bundles built and launched without a system Java installation. Bundled native libraries were checked for ARM64 architecture.
- Eight Kotlin tests and 15 selected harness/release tests passed; TypeScript checking passed.
- Both apps completed the standard one-iteration, zero-warmup video and separate-memory smoke protocol. These observations are validation only, not a stable performance ranking.
- Full-sized histories matched the existing digests: `3a290b9eb53fa834` initially and `c27e9dc5a848d7f6` after switching.
- Final synthetic dark/light captures verified top alignment, rich Markdown, highlighting and actual composer blur. The visual check caught and fixed a pre-layout scroll wait, reversed-list alignment for tall rows, and sharp content showing beneath a transparent blur layer.

| Workload | App MiB | External syntax pack MiB | Combined MiB |
| --- | ---: | ---: | ---: |
| Hello World | 113.3 | — | 113.3 |
| Chat History | 116.3 | 3.4 | 119.7 |

Uncompressed regular-file sizes, including bundled JVM, renderer and signatures: Hello World 118,827,892 bytes; Chat History 121,912,714 bytes; syntax pack 3,579,102 bytes. System frameworks and build caches are excluded, matching the existing size convention.

Local smoke evidence: `ChatHistory/benchmark/results/2026-09-18T19-38-46.335Z.json` and `HelloWorld/benchmark/results/2026-09-18T19-39-17.525Z/`. Videos accompany the reports. These ignored machine-local artifacts are not included in prebuilt releases.

Repeat the synthetic lifecycle/visual check after building and preparing the standard runner's capture helpers:

```sh
bun benchmarks/compose-visual.ts dark
bun benchmarks/compose-visual.ts light
```

The check uses synthetic cached histories, captures initial/top/switch phases, and saves recordings, events and window bounds under the ignored results directory. [Dark screenshot](report-assets/compose.png), [light screenshot](report-assets/compose-light.png), and [frame provenance](report-assets/screenshot-provenance.json) are included with the report.

## Optimization audit follow-up

The initial candidate had an avoidable cache disadvantage: its Markdown AST survived scrolling, but syntax spans only survived while the code composable remained mounted. The source now retains requested spans with each visited row, matching GPUI's retained parsed/highlighted blocks. Neither cache eagerly processes unseen messages or survives document replacement. Row-kind content types also allow normal Compose composition reuse.

These changes do not establish optimality. The existing release bundles, smoke timings and sizes above predate this follow-up. Before final comparative claims, rebuild and validate the updated candidate, profile startup/selection allocations (including JSON string decoding and JVM heap retention), and review measured viewports for equivalent Markdown/highlighting output. Keep normal JVM defaults until measurements justify a production-appropriate change; do not use forced collection or benchmark-only heap tuning to improve reported memory.

## Second optimization audit — September 18, 2026

Committed candidate `14d649a` was reviewed against the lazy-document and rendering contract, Rust/GPUI retained Markdown blocks, native Swift range parsing, and RN/Flutter viewport rendering. The follow-up closes these gaps:

- The initial delimiter-only JSON scan accepted malformed ignored values. Jackson Core now validates complete records without building full JSON trees, preserving lazy message decoding. Regression tests include invalid escapes, trailing commas, mismatched brackets, leading-zero numbers and multiple roots.
- Allocation sampling identified JSON decoder state for plain field names. Those strings now decode directly from UTF-8; escaped strings still use the library decoder. Digest hashing feeds prefix, contents and delimiter separately instead of copying concatenated buffers.
- Parsed Markdown and requested syntax spans stay cached per visited row, and lazy-list content types support normal composition reuse. Invisible task-list marker nodes no longer introduce empty layout blocks.

The rebuilt release passed ten Kotlin tests, fifteen harness/release tests and TypeScript checking. Full-sized initial/switch histories still match `3a290b9eb53fa834` and `c27e9dc5a848d7f6`. Release JAR inspection found no duplicate packaged class definitions; similarly named AndroidX/JetBrains artifacts are not evidence of duplicate implementation classes.

A separate JFR diagnostic launch used the release JARs with the full matching JDK (to provide profiling tools), not the packaged runtime. After switching, heap usage was 462,716 KiB; one diagnostic collection reduced it to 156,003 KiB. The resulting histogram contained about 150.8 MB of byte arrays, consistent with the current 148.1 MB source and runtime data, rather than both source documents. This supports collectible old-document memory, not a retained first-document buffer in this observed transition. This collection is **not** present in the app or benchmark runner. JVM heap, native renderer memory and process footprint are distinct quantities.

The short profile's main sampled CPU paths were line scanning, range indexing and streaming validation. It establishes no exact hotspot percentages or universal optimality. JVM/JIT startup, GC policy, Compose list preparation and Skia text/blur work remain measured stack costs. There is no current evidence justifying a special heap cap, forced GC, prewarming or changing libraries merely to improve ranking.

Unprofiled smoke evidence: Chat History `ChatHistory/benchmark/results/2026-09-18T19-54-57.727Z.json`; Hello World `HelloWorld/benchmark/results/2026-09-18T19-55-28.734Z/`. These launches include external video and separate memory measurements, but are not the two-warmup/ten-run publication protocol. The final task-marker layout correction follows those smoke runs and passed a separate synthetic initial/top/switch visual check in `ChatHistory/benchmark/results/compose-visual-1789761434428-dark/`; the final frame confirms inline task-marker alignment.

The audited chat package is approximately 116.5 MiB plus the unchanged 3.4 MiB external syntax pack; the earlier table describes the original candidate. The practical conclusion is a competent, normally optimized application-stack comparison, with the documented renderer/prefetch/material differences. This is not a claim that all apps perform identical internal work or that further optimization is impossible.
