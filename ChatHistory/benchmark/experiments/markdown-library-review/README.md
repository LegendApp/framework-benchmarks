# Markdown candidate checks

September 12, 2026. Source revisions are in revisions.json. No production app or dependency was changed.

workload-probe.swift imports ChatHistoryCore from the comparison repository and Markdown from swift-markdown. Its argument is the local fixture manifest. It prints AST counts and exports private message strings to /tmp/md-workload-messages.json for local probes. Do not commit that export.

The two renderer probes were added as temporary executable targets in disposable upstream checkouts. Each target depends on its checkout's library product. They use NSHostingController without presenting a window. LiYanan uses MarkdownText, public NSFont overrides for body/H1/H2, and the default TextKit 1 engine. Microsoft uses a pre-parsed RenderableDocument, DocumentView, and disabled animations. These are DEBUG compatibility/sizing checks, not performance benchmarks or final matched styles.

liyanan-synthetic-probe.swift reproduces the final synthetic checks, including a list starting at 3 and inspection of NSTextView text/fonts. For the corpus run, replace its input construction with all exported messages whose Markdown does not contain `![`, plus the first four synthetic cases; omit the list-start case and text/font inspection. Four synthetic cases plus 236 message strings, each at 886 and 400 points, produced 480 finite positive heights. One message containing image syntax was excluded to avoid image loading. The checks do not prove attachment contents, final pixel parity, asynchronous highlighting completion, list integration, or startup/memory equivalence.

microsoft-probe.swift checks four synthetic cases and three long fixture rows at both widths. It is a smoke test, not a corpus-wide test.

No screenshots, videos, launch benchmarks, or memory measurements were taken. Upstream source-only findings for other candidates are identified in the review rather than presented as runtime results.
