# Composer materials

Audit: September 17, 2026, macOS 26.6.1. This describes the floating composer, not the sidebar, titlebar, or window background.

| App | Actual composer treatment | Blurs the transcript behind it? | Native Liquid Glass? |
| --- | --- | --- | --- |
| React Native macOS | `NSGlassEffectView`, regular style, through `GlassSurface` | Yes | Yes |
| AppKit | `NSGlassEffectView`, regular style | Yes | Yes |
| SwiftUI | Shared `TranscriptGlassView` wrapping `NSGlassEffectView`, regular style | Yes | Yes |
| Electron | Chromium CSS `backdrop-filter: blur(24px) saturate(1.4)` | Yes | No |
| Tauri | WebKit CSS `backdrop-filter: blur(24px) saturate(1.4)` | Yes | No |
| Deno WebView | WebKit CSS `backdrop-filter: blur(24px) saturate(1.4)` | Yes | No |
| Deno CEF | Chromium CSS `backdrop-filter: blur(24px) saturate(1.4)` | Yes | No |
| Flutter | Clipped `BackdropFilter` with `ImageFilter.blur(sigmaX: 24, sigmaY: 24)` | Yes | No |
| GPUI 0.2.2 | Alpha-blended rounded panel | **No** | No |

## What is aligned

The composer has a shared maximum width of 860 logical units, 24-unit horizontal clearance, a 20-unit bottom gap, and a 26-unit corner radius. It overlays the scrolling transcript. The native glass implementations use the regular system style and matching custom tints: dark `#202124` at 40% opacity; light white at approximately 44%.

The conventional fallback surfaces use approximately 78% tint opacity, dark `#252528` and light `#f5f5f7`. Flutter's composer tint and horizontal clearance now match that fallback. Its Gaussian sigma is 24; the web blur length is 24 CSS pixels. These nominal values do not guarantee identical kernels or pixels across engines. The web effect also increases saturation by 1.4; Flutter's current filter only blurs. GPUI uses the matching tint without blur.

Liquid Glass is a system material with effects beyond an ordinary Gaussian blur. Its material opacity, highlights, and response to content are system-controlled; matching only a tint or blur radius cannot reproduce it. The screenshots therefore identify the implementation rather than asking readers to infer it from one still frame. See [Apple's glass style API](https://developer.apple.com/documentation/appkit/nsglasseffectview/style-swift.property).

## The GPUI limitation

The pinned GPUI 0.2.2 style API has no per-element backdrop-filter operation. Its macOS window implementation supports a native visual-effect view for the window background; that does not sample transcript pixels rendered above it in the same GPU surface. A translucent composer must not be described as a blur. The upstream [backdrop-blur discussion](https://github.com/zed-industries/zed/discussions/47429) describes this distinction and the renderer work needed.

A closer GPUI implementation would require a custom render-to-texture blur pass or a macOS-native overlay integration, with its own composition and input handling. This change does not add either. The current result uses the available ordinary surface treatment, but **GPUI still performs less compositor work than the apps with backdrop blur**. That remains a qualification on visual/workload equivalence, not proof of an overall timing advantage attributable to blur alone.

## Native interoperability versus framework rendering

The web/canvas apps could acquire additional macOS-specific native integration, but none currently hosts a native glass composer. Flutter's native window background material is not its composer blur, and GPUI's whole-window blur is not per-element blur. We retain each framework's existing content renderer and identify its limits rather than substitute a screenshot effect or call transparency Liquid Glass.

On older macOS versions AppKit and SwiftUI fall back to an `NSVisualEffectView`; RN's native glass view has a different fallback. The table above is specifically for the measured macOS 26 environment.

## Screenshot protocol

The report uses a long synthetic chat, scrolled to the top so that real rendered text continues behind the composer. Each screenshot is extracted 600 ms after the app's top-viewport event, before the chat switch. The fixture contains prose, lists, and highlighted TypeScript. These screenshots are presentation evidence, not new performance measurements, and are not the private corpus used for the timing tables.

Sources in this repository: [web CSS](../apps/chat-history-electron/src/styles.css), [Flutter widgets](../apps/chat-history-flutter/lib/main.dart), [GPUI renderer](../apps/chat-history-gpui/src/main.rs), and [shared native glass view](../packages/chat-history-swift/Sources/ChatHistoryMarkdown/TranscriptGlassView.swift). RN uses the sibling Legend Apps `glass-effect-view` package.
