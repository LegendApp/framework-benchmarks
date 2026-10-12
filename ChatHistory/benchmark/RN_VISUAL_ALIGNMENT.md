# Native alignment to the React Native reference

Status: **initial/top/switched dark-mode captures inspected at 1280×720**; light-mode and narrow-window live acceptance remain pending. This pass covers AppKit and SwiftUI. React Native is the reference and was not changed. Earlier timing tables describe the previous native executables and must not be presented as results for these changes.

## Changes

- Both native apps use `NSGlassEffectView` on macOS 26 for the 52-point titlebar and 60-point composer, matching the RN native wrapper. Titlebar glass uses rectangular edges, 48-point overscan and the reference light-mode overlay. The composer uses the reference tint, 26-point corners, border, shadow, 860-point maximum width, 20-point bottom clearance and blue send button. Older macOS versions retain a material fallback.
- Transcript content can extend behind the titlebar, with 64 points of initial top clearance and 112 points of bottom clearance. Settings moved to the app menu; framework subtitles and diagnostic toolbar controls no longer add chrome absent from RN. AppKit no longer scrolls the sidebar to an initially selected old conversation.
- SwiftUI retains native `List` virtualization. An attempted `ScrollView`/`LazyVStack` replacement passed static sizing checks but left the second pinned transcript blank in unattended launches. Returning to `List` fixed the regression; its eight-point horizontal cell gutter is compensated so rows retain the intended width. The lazy outer row, document model, cache and background parser scheduling remain. Each document has its own view identity, and bottom clearance belongs to the final message row. Framework lookahead behavior remains framework-dependent.
- Both native apps render the same shared Markdown model. Paragraph spacing is 16 points rather than an extra 22-point blank line; heading margins, inline code styling, list marker geometry, nested indentation, task checkboxes, quote backgrounds/borders and geometric rules follow the reference styles.
- Code blocks contain a fixed language header, rounded border, divider, copy button and horizontally scrolling unwrapped code document. Header/body measurement follows RN's `ENRMCodeBlockContainerView`. Copy retains complete source, including overflowing text. Syntax highlighting remains disabled on both sides.
- Tables use the same content-driven column algorithm as RN: 60-point minimum, 300-point text measurement cap plus 16-point horizontal padding, 6-point vertical padding, formatted/aligned cells and horizontal scrolling at narrow widths. They no longer squeeze columns to fit the viewport. Alternating row colors and rounded borders follow the theme.
- File-card colors, fonts and spacing were brought closer to the reference. The measured benchmark still disables images; this pass does not certify image-loading behavior or exhaustive Markdown extension conformance.

The SwiftUI bridge lives in the SwiftUI executable, not the shared AppKit module. This avoids adding a SwiftUI dependency to the AppKit app merely to share a glass view.

## Validation and limitations

- Release builds of both native executables.
- 21 serialized Swift tests: parser/settings/demo regressions, rich Markdown, width-dependent prose, unwrapped scrolling code and tables, reuse, nested quotes/blocks, and copying complete embedded content.
- AppKit production-source resize harness: 12 configurations and 1280-point window / x=260, width=1020 transcript geometry.
- SwiftUI production-source sizing harness: text/heading/code heights, compact user bubbles, and responsive text wrapping. Its old code-height expectation was updated to include the reference header and padding.
- Diagnostic window geometry confirms both apps' titlebar glass at `(260, 668, 1020, 52)` and composer at `(340, 20, 860, 60)` in a 1280×720 window. The SwiftUI list-gutter correction gives the same 901.5-point assistant text measurement width as AppKit. The tool-row divider now occupies one point of layout in both.
- Wide/narrow offscreen Markdown renders were inspected. These verify text and embedded controls, **not WindowServer's live glass composition**.

Evidence and logs are in the ignored `results/2026-09-12-rn-visual-alignment/` directory. The display was locked. A standalone window screenshot timed out; the recording path captured the lock screen and could not find the app window. That recording is failed diagnostic evidence, not an app video or benchmark result. Whole-window offscreen caches likewise cannot validate system glass and are not accepted screenshots.

Before claiming visual parity or publishing new timings: unlock the Mac, capture RN/AppKit/SwiftUI initial, top and switched viewports at the same size and appearance, inspect narrow-window overflow and light/dark chrome, resolve any remaining discrepancies, then rerun benchmarks on a quiet machine. No fresh timing ranking was produced by this pass.

## Reference sources

In sibling `legend-apps`: `apps/chat-history/src/TranscriptRow.tsx`, `ChatComposer.tsx`, `App.tsx`; `packages/theme/src/index.ts` and `generatedThemes.ts`; `packages/glass-effect-view/ios/GlassEffectView.swift`; `packages/appkit-split-view/ios/RNSidebarSplitViewComponent.mm`; and the installed enriched-markdown `ENRMCodeBlockContainerView`, `TableContainerView`, `CodeBackground`, `ListMarkerDrawer` and normalized styles. Source hashes are recorded with the local evidence.

## September 13 unlocked verification

[Side-by-side screenshot/video gallery](results/2026-09-13-rn-visual-alignment-phases/index.html) · [Verification and hashes](results/2026-09-13-rn-visual-alignment-phases/verification.json)

After the Documents permission was accepted, an unrelated unsupported-link alert was dismissed and RN's saved-window recovery prompt was cleared. The diagnostic capture script was corrected to use the same encoded RN benchmark launch argument and process-local persistence setting as the real harness. Earlier obstructed or unconfigured captures are not acceptance evidence.

All three apps now have inspected, unobstructed 1280×720 dark initial, top and switched captures. The same text and broad geometry appear in each viewport; native glass is visibly composited, including text behind the composer in the top view. This is close visual alignment, not pixel identity: small vertical text offsets, list-marker/color differences and native toolbar details remain. Light-mode and narrow-window live checks remain outstanding.

Two corrections were made during this check:

- AppKit sidebar uses plain table style because automatic sidebar style added an extra 16-point inset on top of the cell's own padding. The corrected text begins at the reference sidebar position.
- SwiftUI's lazy-stack transcript could show a blank second document indefinitely without reporting ready. Opening that document directly also reproduced it. View identity changes and delayed scrolling alone did not fix it; accessibility inspection could cause message realization and therefore was not accepted as unattended validation. The final native `List` implementation passed two consecutive unattended initial/top/switch checks, one quick event check and one recorded check. The final recording visibly contains the switched tail. Failed recordings are retained with diagnostic prefixes. This identifies the working correction; it does not establish a general SwiftUI framework defect.

Fresh initial/switch digests match across RN, AppKit and SwiftUI (`3a290b9eb53fa834`, `c27e9dc5a848d7f6`). All three final videos have matching decoded-frame/timestamp counts and strictly increasing timestamps. Both modified native executables built in Release. These are diagnostic launches, not scored performance trials; no new startup ranking is claimed. No temporary view-dump instrumentation remains in application source.
