# Composer materials

Updated source audit: September 19, 2026. The retained screenshots are from the earlier macOS 26.6.1 capture run. This describes the floating composer, not the sidebar, titlebar, or window background.

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
| Compose Multiplatform | Skia `ImageFilter.makeBlur`, sigma 10 logical units, sampled Compose transcript layer | Yes | No |
| GPUI 0.2.2 | GPUI-rendered translucent fill, border, and labels | No | No |

## What is aligned

The composer has a shared maximum width of 860 logical units, 24-unit horizontal clearance, a 20-unit bottom gap, and a 26-unit corner radius. It overlays the scrolling transcript. The native glass implementations use the regular system style and matching custom tints: dark `#202124` at 40% opacity; light white at approximately 44%.

The conventional web and Flutter composer surfaces now use 40% dark tint (`#202124`) and 44% light tint (`#f5f5f7`), reduced from approximately 78%. Flutter's Gaussian sigma and the web blur length are both 10, reduced from 24. Web saturation is 1.2. These nominal values do not guarantee identical kernels or pixels across engines, but retain more visible background structure than the previous heavy blur and tint. Header materials are unchanged.

Liquid Glass is a system material with effects beyond an ordinary Gaussian blur. Its material opacity, highlights, and response to content are system-controlled; matching only a tint or blur radius cannot reproduce it. The screenshots therefore identify the implementation rather than asking readers to infer it from one still frame. See [Apple's glass style API](https://developer.apple.com/documentation/appkit/nsglasseffectview/style-swift.property).

## Framework-native rendering policy

The benchmark uses each framework's normal renderer and supported framework APIs.
App-specific AppKit visual overlays are not part of the GPUI or Flutter variants.
Native window controls, titlebar configuration, and non-UI platform services remain.

GPUI's custom Objective-C Liquid Glass overlay and build hook have been removed.
The composer is an ordinary GPUI element tree with a translucent fill (40% dark,
44% light), border, placeholder and send indicator. It remains an inert demo;
no new editing capability is implied. This pinned GPUI implementation uses
transparency rather than inventing a backdrop-filter capability.

Flutter's custom `NSVisualEffectView` behind its transparent surface has also been
removed. Its standard `FlutterViewController` is the window content controller,
and the Flutter theme supplies the scaffold background. The Flutter composer
retains its `BackdropFilter`; titlebar settings, window controls, and plugins remain.

Compose retains Compose/Skia blur and standard AWT window settings. Electron's
supported `BrowserWindow.vibrancy` option remains; its composer is CSS-rendered.
Tauri and Deno retain their WebView-rendered UI and CSS composer blur.

The existing GPUI and Flutter screenshots/bundle sizes predate this removal and
must be refreshed before being presented as the current build. No timing or
memory figures have been replaced by this source change. The old native-overlay
sizing test was removed with the component it tested.

## Screenshot protocol

The report uses a long synthetic chat, scrolled to the top so that real rendered text continues behind the composer. Each screenshot is extracted 600 ms after the app's top-viewport event, before the chat switch. The fixture contains prose, lists, and highlighted TypeScript. These screenshots are presentation evidence, not new performance measurements, and are not the private corpus used for the timing tables.

The retained GPUI captures show the removed native composer; the retained Flutter captures include the removed native window background. They are historical visual evidence, not screenshots of the current source.

Sources in this repository: [web CSS](../ChatHistory/apps/chat-history-electron/src/styles.css), [Flutter widgets](../ChatHistory/apps/chat-history-flutter/lib/main.dart), [GPUI renderer](../ChatHistory/apps/chat-history-gpui/src/main.rs), and [shared native glass view](../ChatHistory/packages/chat-history-swift/Sources/ChatHistoryMarkdown/TranscriptGlassView.swift). RN uses the sibling Legend Apps `glass-effect-view` package.

## Compose Multiplatform addition

The Compose chat app samples its rendered transcript layer with Skia `ImageFilter.makeBlur`, using Gaussian sigma 10 logical units (scaled to physical pixels), 40% dark / 44% light tint, and the shared dimensions. It previously passed radius 10 to Compose `BlurEffect`, which converts radius to a smaller sigma and produced weaker blur. The direct Skia filter now matches Flutter's sigma and the web CSS blur's nominal standard deviation. This is conventional backdrop blur, not Liquid Glass; matching sigma does not guarantee identical pixels across engines.

The AWT host now opts into the selected application appearance before window creation and uses a transparent, title-hidden native titlebar over the themed window background. Native window controls and dragging are retained. Dark and light release visual runs passed initial/top/switch phases on September 19, and report screenshots/provenance were refreshed. Existing Compose timing and memory numbers predate this stronger filter and must be rerun before reporting updated performance. See [Compose notes](COMPOSE_MULTIPLATFORM.md).
