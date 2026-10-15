# Public chat samples

These eight transcripts are synthetic. Every prompt, response, code fragment, tool
result, identifier, path, and timestamp was authored for this dataset. No source
transcript text was copied or sanitized. The two measured sessions preserve only
aggregate byte counts, record counts, record-type frequencies, and approximate
line-size distributions from the previously pinned workload. Repeated synthetic
prose supplies large payloads; this models parsing volume rather than natural
language diversity within every payload.

The two large samples use ASCII message text so byte-limited native work previews
and character-limited JavaScript previews contain the same text. Smaller sessions
retain Unicode coverage.

The first two entries in `manifest.json` are the fixed first-content and switching
targets. All eight entries are added to the machine's discovered history. History
discovery still measures the real machine's files. Files ending in `.gz` expand to
ordinary JSONL in the benchmark's ignored working directory before app startup;
the apps receive identical uncompressed files. `sourceBytes` and `sha256` describe
the uncompressed bytes. Images and document attachments are placeholders; image
loading is disabled, so no external resource or private file is required.

| File (suffix `.jsonl`, optionally `.gz`) | Provider | Source bytes | Records |
| --- | --- | ---: | ---: |
| synthetic-codex-first | Codex | 239,115,823 | 8,226 |
| synthetic-codex-switch | Codex | 148,125,953 | 10,382 |
| synthetic-codex-brief | Codex | 4,527 | 11 |
| synthetic-codex-language-tour | Codex | 364,632 | 106 |
| synthetic-claude-brief | Claude | 3,379 | 6 |
| synthetic-claude-branches | Claude | 17,274 | 30 |
| synthetic-claude-language-tour | Claude | 672,872 | 126 |
| synthetic-claude-long-notebook | Claude | 2,340,196 | 240 |

The measured Codex samples have line-size p50/p90/p99 values of 840/6,572/404,359
and 840/6,514/375,190 bytes. Their largest records are 8,000,000 and 2,759,105 bytes.
They include user, assistant, developer, reasoning, custom and function tool calls
and outputs, completion events, token-count events, and compacted history.

The smaller sessions cover short exchanges, very long messages, headings, lists,
task lists, tables, quotes, inline formatting, HTML details, Unicode, shell output,
JSON, YAML, TOML, diffs, image/document placeholders, successful and failed tools,
Claude alternate branches and sidechains. Fenced code covers TypeScript,
JavaScript, Python, Rust, Go, Swift, Kotlin, Dart, C, C++, C#, Java, Ruby, SQL,
Bash, HTML, and CSS. The examples use neutral relative paths and fictional data.

To regenerate with Python's standard library, from the repository root:

```sh
python3 ChatHistory/fixtures/generate.py
```

Generation writes deterministic gzip headers and fixed timestamps. The two large
samples occupy approximately 2.25 MB compressed together, keeping individual Git
objects below hosting limits. The manifest, generator, and this document are
metadata, not additional chat threads. Regeneration should be followed by the
shared parser tests and a privacy scan of all decompressed samples and metadata.
