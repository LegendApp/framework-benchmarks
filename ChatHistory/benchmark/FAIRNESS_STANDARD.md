# Fair comparison standard

## Decision

Compare competent, idiomatic applications delivering the same visible workload. Retain each platform's normal text renderer, Markdown/highlighting libraries, and virtualized list. Do not replace them with a shared renderer or force an identical offscreen row count: layout, list preparation and caching are part of the application stack being measured.

This is an application-stack comparison, not a measurement of framework overhead with all other implementation work held constant.

## Common work

- Identical pinned input histories, selected conversations, normalized visible rows, collapsed tool/file policy, and image-disabled mode.
- Rich paragraphs, headings, emphasis, links, lists/tasks, quotes, tables and fenced code. Highlight declared languages under the shared language/size limits; no language auto-detection or eager whole-history highlighting.
- Same code-pane source normalization, window/content dimensions and comparable typography. Pixel identity and full Markdown-extension equivalence are not claimed.
- Lazy document access, viewport-driven Markdown work, and normal per-row caches. Do not preload rendered histories across launches.
- Match shared dependency versions and configurable policies: RN/web use the same Legend List snapshot and 500-point initial estimate; RN/web/GPUI request a 250-point buffer. Flutter retains its indexed-list two-viewport minimum; AppKit/SwiftUI retain native preparation. This difference must be disclosed, not hidden or labeled equal work.

## Reporting requirements

- Build-time rendering inputs are captured in the build manifest. The runner rejects missing or inconsistent policy provenance and mismatched shared list artifacts before starting warmups.
- The result embeds the rendering contract and input identities. Source changes after export do not retroactively change a build's provenance.
- Record every discarded attempt and its reason, including warmups and companion memory launches. Aggregate only completed observations, and disclose retry counts.
- Use the established two-warmup, ten-measurement rotating protocol for published rankings. Keep single-launch validation separate.
- Require an unlocked console for the foreground comparison, external video-based content detection, and separate unrecorded settled-memory launches.
- Check screenshots as well as normalized digests. Digests establish parsed content, not rendered feature parity. A known missing feature or wrong viewport invalidates a claim of equivalent visible work.
- Preserve raw observations, videos, percentile tables and build identities. Label uncontrolled background work. Do not claim intrinsic framework superiority or cold-boot performance from this warm-filesystem workload.

## Remaining limits

The existing visual checks cover the measured view transitions and representative Markdown, not every Markdown extension or every possible row. Spoilers and other parser-specific extensions are outside the certified feature set. If they affect a measured viewport, align that feature or explicitly classify the workload as non-equivalent before publishing a ranking.

The remaining native prefetch, syntax-tokenization and text-layout differences are intentional properties of the chosen stacks. Further tuning requires evidence of avoidable application work and the same standard of review for every app; a desired ranking is not a reason to optimize or disable a feature.

The September 15 ten-run table predates the latest shared-list/code-pane alignment and is retained as a historical measurement. The six subsequent validation launches are not its replacement. A new published ranking requires a fresh complete run of the final frozen builds.

## Validation of enforcement

All nine production apps rebuilt with rendering provenance; the actual exported records pass the policy/shared-list compatibility check. Three regression tests cover artifact drift, absent provenance and policy mismatch; TypeScript checking passes. An end-to-end foreground check was attempted but correctly refused before measurement because the console had locked. No new performance ranking was produced.

## Sidebar presentation

Use native split-view presentation in the native UI stacks. The current Electron, Tauri, Deno, Flutter, and GPUI implementations use a plain, full-height sidebar with a solid background and one divider. They retain a 260-point sidebar allocation, without imitating native glass through outer insets or rounded panels. Adding a native split-view host to these implementations would require a separate platform integration; it is not part of the existing renderer. Markdown, highlighting, and document-loading policies are unchanged by this presentation choice.

## Composer materials

The [composer audit](../../docs/COMPOSER_MATERIALS.md) distinguishes native Liquid Glass and conventional backdrop blur. RN/AppKit/SwiftUI use native glass on macOS 26; GPUI now uses a macOS-native glass overlay above its rendered transcript. The web apps and Flutter use reduced-strength backdrop blur and lighter tint. All composers now blur underlying content, but their algorithms and compositor work are not identical. Earlier performance numbers predate GPUI's native overlay and must not be presented as measurements of the new build.

## Compose Multiplatform candidate

The Kotlin/JVM implementation follows the same lazy document and normalized-row policy, uses CommonMark with GFM extensions, and highlights explicit languages from the shared policy through an external JVM syntax pack. It retains Compose LazyColumn's default prefetch rather than forcing a synthetic row count. Its composer performs a conventional 10-point backdrop blur; it is not native Liquid Glass. Images are placeholders under the text-only benchmark contract. See [implementation and validation notes](../../docs/COMPOSE_MULTIPLATFORM.md). Existing nine-framework published tables do not include this candidate.
