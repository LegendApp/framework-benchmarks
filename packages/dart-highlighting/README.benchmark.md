# External grammar support

Vendored from `highlighting` 0.9.0+11.8.0 (see LICENSE). The parser, compiler,
callbacks and original language definitions are unchanged. Two adaptations:

- `lib/src/highlightv2.dart` no longer imports the builtin language registry.
- `lib/src/grammar_pack.dart` encodes/decodes uncompiled language graphs, including
  shared mode identity, explicit references, raw null markers and known callbacks.

The export tool imports the original definitions only at build time, selects the
benchmark languages and their embedded-language dependencies, and writes JSON.
The app imports only the engine/decoder and reads that file on first highlighting.
Regex compilation, tokenization and foreground-span rendering remain runtime work.
Unknown callback types or compiler extensions fail export; they are never dropped.
The Flutter grammar-pack test compares complete token trees with original rules
for every shared language fixture. The supported Dart SDK range was updated for
this repository's toolchain. This is a repository-local dependency, not a release
of the upstream package.
