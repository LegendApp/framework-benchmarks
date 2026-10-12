# Shared native document core

AppKit and SwiftUI use the same selective C++ JSONL parser and lazy document
implementation as the React Native app in `legend-apps`. Source provenance and
SHA-256 hashes are recorded in `PROVENANCE.json`. Regenerate the vendored source
from its pinned Git revision with:

```sh
python3 packages/chat-history-swift/scripts/vendor-native-core.py /path/to/legend-apps
```

The importer copies the parser, JSON reader, timestamp reader, and mapped text
source unchanged. It removes the document's Nitro inheritance, JSI converters,
React Native Markdown registry integration, and native image-size adapter.
Normalization, display grouping, selective traversal, deferred text decoding,
and the content digest remain upstream code. Swift's existing renderer owns
images. This package has no runtime dependency on the sibling checkout.

`CHNativeDocument` is an Objective-C++ ownership adapter. `NativeDocumentStorage`
retains it, and each Swift row retains that storage through a synchronized text
cache. Reading IDs or metadata does not decode message bodies. Releasing the
last document/row releases the file mapping. Body and preview decoding occurs
on first access and is cached separately. Both UIs retain their existing native
lists and Markdown rendering.

The native timing includes the Swift metadata adapter as well as mapping,
scanning, parsing, and display-row construction. Digest validation traverses the
native document after readiness, without populating the Swift UI's text caches.
The original Swift parser remains a test/reference API; production file opening
uses the native core.

Run small-fixture, lazy-access, lifetime, serialization, and error checks with:

```sh
swift test -c release --package-path packages/chat-history-swift
```

For full-corpus parity, also supply `CHAT_HISTORY_TEST_FIXTURES` pointing to the
local benchmark manifest. This verifies both the native digest and the complete
Swift row adapter against the original Swift parser.
