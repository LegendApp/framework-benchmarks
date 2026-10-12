# Composer materials

Audit: September 17, 2026, macOS 26.6.1. This describes the floating composer, not the sidebar, titlebar, or window background.

| App | Actual composer treatment | Blurs the transcript behind it? | Native Liquid Glass? |
| --- | --- | --- | --- |
| React Native macOS | `NSGlassEffectView`, regular style, through `GlassSurface` | Yes | Yes |
| AppKit | `NSGlassEffectView`, regular style | Yes | Yes |
| SwiftUI | Shared `TranscriptGlassView` wrapping `NSGlassEffectView`, regular style | Yes | Yes |
| Electron | Chromium CSS `backdrop-filter: blur(10px) saturate(1.2)` | Yes | No |
| Tauri | WebKit CSS `backdrop-filter: blur(10px) saturate(1.2)` | Yes | No |
| Deno WebView | WebKit CSS `backdrop-filter: blur(10px) saturate(1.2)` | Yes | No |
| Deno CEF | Chromium CSS `backdrop-filter: blur(10px) saturate(1.2)` | Yes | No |
| Flutter | Clipped `BackdropFilter` with `ImageFilter.blur(sigmaX: 10, sigmaY: 10)` | Yes | No |
| GPUI 0.2.2 | App-owned macOS `NSGlassEffectView` overlay, regular style | Yes | Yes |

## What is aligned

The composer has a shared maximum width of 860 logical units, 24-unit horizontal clearance, a 20-unit bottom gap, and a 26-unit corner radius. It overlays the scrolling transcript. The native glass implementations use the regular system style and matching custom tints: dark `#202124` at 40% opacity; light white at approximately 44%.

The conventional web and Flutter composer surfaces now use 40% dark tint (`#202124`) and 44% light tint (`#f5f5f7`), reduced from approximately 78%. Flutter's Gaussian sigma and the web blur length are both 10, reduced from 24. Web saturation is 1.2. These nominal values do not guarantee identical kernels or pixels across engines, but retain more visible background structure than the previous heavy blur and tint. Header materials are unchanged.

Liquid Glass is a system material with effects beyond an ordinary Gaussian blur. Its material opacity, highlights, and response to content are system-controlled; matching only a tint or blur radius cannot reproduce it. The screenshots therefore identify the implementation rather than asking readers to infer it from one still frame. See [Apple's glass style API](https://developer.apple.com/documentation/appkit/nsglasseffectview/style-swift.property).

## GPUI native overlay

GPUI 0.2.2 still has no per-element backdrop-filter operation. Instead, this macOS app now installs a native Liquid Glass composer above its GPU-rendered transcript, using the same regular system material and tint as the native-view apps. Its previous transparency-only composer is removed. On older macOS versions the overlay uses `NSVisualEffectView` with within-window blending.

The host owns one overlay for the lifetime of the view. It follows window resizing without constraining the GPUI window's size, updates with the selected appearance, and hides when settings are open. The placeholder and send indicator remain an inert demo, as before. Transcript and sidebar rendering remain GPUI; the composer is now a native AppKit component. This is a macOS-specific integration, not a new capability of GPUI itself.

The rebuilt app was recorded over a long chat in dark and light modes. A focused native check verified placement at 900, 1280, and 1600-point window widths, a single overlay after repeated updates, appearance changes, and settings visibility. Full timing/memory benchmarks have not been rerun; the old GPUI figures predate this additional compositor work.

## Native interoperability versus framework rendering

The web apps and Flutter retain their renderer's conventional backdrop blur. GPUI now uses native interoperability for the composer. The native material has additional effects and system-controlled behavior, so the result is closer in purpose and appearance but not pixel-identical across all engines. Flutter's native window background material is separate from its composer blur.

On older macOS versions AppKit and SwiftUI fall back to an `NSVisualEffectView`; RN's native glass view has a different fallback. The table above is specifically for the measured macOS 26 environment.

## Screenshot protocol

The report uses a long synthetic chat, scrolled to the top so that real rendered text continues behind the composer. Each screenshot is extracted 600 ms after the app's top-viewport event, before the chat switch. The fixture contains prose, lists, and highlighted TypeScript. These screenshots are presentation evidence, not new performance measurements, and are not the private corpus used for the timing tables.

The native sizing/lifecycle regression check is [composer_glass_test.m](../ChatHistory/apps/chat-history-gpui/tests/composer_glass_test.m); its header includes the command to run it.

Sources in this repository: [web CSS](../ChatHistory/apps/chat-history-electron/src/styles.css), [Flutter widgets](../ChatHistory/apps/chat-history-flutter/lib/main.dart), [GPUI renderer](../ChatHistory/apps/chat-history-gpui/src/main.rs), and [shared native glass view](../ChatHistory/packages/chat-history-swift/Sources/ChatHistoryMarkdown/TranscriptGlassView.swift). RN uses the sibling Legend Apps `glass-effect-view` package.

## Compose Multiplatform addition

The Compose chat app uses its own Skia graphics layer to sample the transcript behind the composer, with a 10-point Gaussian blur, 40% dark / 44% light tint, and the shared dimensions. This is conventional backdrop blur, not Liquid Glass. The existing report screenshots and historical measurements predate this candidate. See [Compose notes](COMPOSE_MULTIPLATFORM.md).
