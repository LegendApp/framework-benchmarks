# HighlighterSwift 3.1.0

Vendored from https://github.com/smittytone/HighlighterSwift at tag 3.1.0,
commit fe7aae9c9b31d3b296fd3d2dd575e1a207bb29e0. MIT license in LICENCE.md;
highlight.js notices in Sources/Assets/LICENCE and its JavaScript header.

The six upstream Swift source files are retained. The only source patch lets
Highlighter.init find SwiftPM resources inside a signed macOS app's
Contents/Resources, before falling back to Bundle.module for tests and CLI use.
The upstream accessor otherwise points to the original build directory.

The upstream package manifest and entire resource inventory are retained,
including highlight.js 11.11.1 and all themes. Only upstream examples and tests
are omitted. No tokenizer changes.
