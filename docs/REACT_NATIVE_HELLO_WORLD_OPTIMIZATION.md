# React Native Hello World optimization audit

September 18, 2026 · Apple M4 · macOS 26.6.1 · ARM64

## Scope and baseline

This audit follows the removal of the duplicate Legend Shell benchmark entry.
Both original binaries were ARM64-only. The large size difference came from
retained executable and Hermes symbol tables, not a second architecture.

Commit `0674954` aligns release packaging: explicit ARM64, deployment
postprocessing, and Hermes local-symbol stripping before signing. The corrected
standalone app measures **8,970,970 bytes (8.56 MiB)**. The old 16.3 MiB snapshot
was not an optimized distribution size.

The first corrected-baseline run used two discarded warmups and ten measured
rounds. It reported 233.8 ms median first content, 244.4 ms p90, and 23.4 MiB
settled physical footprint. This is a new RN-only run, not a replacement for the
older cross-framework ranking. Evidence:
`benchmarks/hello-world/results/2026-09-18T08-41-10.352Z/`.

## Effective native compiler settings

The effective Release configuration—not just the project source—had:

- ARM64, Hermes, Fabric, and assertions disabled.
- `-Os` in app, React-Core, React-Fabric, and Yoga compiler response files.
- `DEAD_CODE_STRIPPING=NO` in app and React-Core build settings.
- No LTO compiler flag.
- After the packaging correction: `STRIP_INSTALLED_PRODUCT=YES`,
  `STRIP_STYLE=all`, `DEPLOYMENT_POSTPROCESSING=YES`.

Three native variants retain the same source and original JS bytecode:

| Variant | Additional settings | Installed bytes before experiment identity normalization |
| --- | --- | ---: |
| Dead stripping | `DEAD_CODE_STRIPPING=YES` | 8,333,525 |
| ThinLTO | dead stripping + `LLVM_LTO=YES_THIN` | 8,098,997 |
| Size-oriented | above + `GCC_OPTIMIZATION_LEVEL=z` (`-Oz`) | 7,499,845 |

All variants reuse one native build tree. Commands and logs are under
`.build/rn-optimization-audit/`. Framework binaries are ARM64 and release-signed
ad hoc. Prebuilt Hermes is not rebuilt with LTO or `-Oz`; those flags apply to
app/Pod compilation, not retroactively to a prebuilt framework.

## Native module/component pruning

Generated `RCTModuleProviders.mm` and `RCTThirdPartyComponentsProvider.mm` both
contain empty third-party registries. There are no unrelated application-native
libraries to remove from this baseline.

The dead-strip link map attributes roughly 705 KB to React-Fabric, 652 KB to
React-Core, 437 KB to React-RCTFabric, and 190 KB to FabricComponents. Smaller
retained archives include text (143 KB), image (104 KB), animation (95 KB),
SocketRocket (52 KB), and network (50 KB). These are sums of live symbol bytes,
not standalone app-size savings; archives have dependencies and metadata.

`-ObjC` and generated/core providers retain classes used through dynamic lookup.
Blindly removing `-ObjC`, individual archives, or registrations can break RN
capabilities even if this greeting still renders. The factory lazily registers
requested components; linked code is not evidence that every component executes
at startup. No RN core module was removed from the recommended candidate.

## JavaScript bundle investigation

The original entry is already minimal: React, AppRegistry, StyleSheet, Text,
and View. No application state, effects, list, navigation, or third-party UI.

Metro's resolved default enables `inlineRequires`. The release Xcode script
compiles Hermes bytecode with `-O` and deliberately passes `--minify false`.
Its unminified JavaScript is intermediate output; it is not the shipped payload.

A source map contains **498 modules**, including both the production Fabric and
legacy renderers, ScrollView, lists, TextInput, and other RN exports. The shipped
bytecode is **1,503,767 bytes**. Static dependency inclusion does not prove
startup execution: imports/exports may be lazy.

Controlled bundle-only experiments on the corrected native baseline:

| JS variant | Modules | Hermes bytecode bytes | Interpretation |
| --- | ---: | ---: | --- |
| Public imports, defaults | 498 | 1,503,767 | Normal baseline |
| Extra Metro minification | 498 | 1,458,695 | Saves 45,072 bytes, about 3% of bytecode |
| Direct RN internal imports | 286 | 932,136 | Saves 571,631 bytes; private-API diagnostic |

The direct-import variant keeps AppRegistry, StyleSheet, Text, and View but
imports their internal files. It is not proposed for the public baseline: the
paths are implementation details, and this removes much of the public export
graph for this one greeting. It is evidence of bundle-pruning potential, not
proof of a generally safe RN optimization.

## Measurement design and provenance

The candidate comparison reuses the existing video/OCR and separate-memory
launch procedure. Six variants rotate order each round, with one discarded
warmup per variant and five measured rounds per variant. It is an exploratory
A/B comparison, not a full rerun of the nine-framework suite.

Experiment copies have unique bundle identifiers. The launcher reports the
actual executable URL and rejects any launch that resolves to another app.
This matters because Instruments launch mode resolved two early capture attempts
to an older same-named build; those captures are excluded from findings.

The executable and bytecode SHA-256 hashes and exact copied bundle sizes are in
`.build/rn-optimization-audit/variant-manifest.json`. Native compilation and
profiling are not run concurrently with the timed comparison.

## Runtime comparison results

One warmup and five measured rounds per variant, with rotating order and
actual executable-path validation. All greeting OCR checks passed.

| Variant | First content p50 / p90, ms | Settled memory, MiB | Installed size, MiB |
| --- | ---: | ---: | ---: |
| baseline | 237.1 / 274.3 | 23.34 | 8.555 |
| dead-strip | 234.3 / 244.8 | 23.28 | 7.947 |
| lto | 233.5 / 326.6 | 23.24 | 7.724 |
| oz | 245.4 / 250.5 | 23.30 | 7.152 |
| minified | 233.2 / 245.1 | 23.34 | 8.512 |
| direct | 233.6 / 234.9 | 23.25 | 8.010 |

Evidence: `benchmarks/hello-world/results/2026-09-18T08-50-49.775Z/`.

The size changes are deterministic. The timing differences do not establish a
startup improvement: most medians are within roughly one recording frame, and
the LTO run has a larger tail outlier. Early minification samples looked faster,
but that advantage disappeared over the completed run. Memory stays near
23.3 MiB. This is an exploratory shared-machine run, not a quiet-machine release
qualification or a new cross-framework ranking.

## Native startup profile

A directly spawned, initially suspended `oz` process was attached by PID, then
resumed under Time Profiler for five seconds. Both the executable path and
Mach-O UUID `97B14D70-52EF-3D41-BFE8-A832994BB019` match the intended build.
The matching link map resolved 86 otherwise unnamed app frames.

The trace contains 100 weighted 1 ms samples: 77 on the main thread, 6 on the
React JavaScript thread, and 17 on other threads. Inclusive stacks contain
`AppDelegate applicationDidFinishLaunching:` in 33 samples, the upstream
`RCTAppDelegate` window-loading path in 31, and AppKit window initialization in
20. These counts overlap; they must not be added together. Loader/Objective-C
initialization and AppKit behavior dominate the named stacks.

This short, instrumented, direct-process profile locates CPU work; it is not
a measurement of LaunchServices-to-visible-content latency. Sampling and
profiler overhead limit attribution. It does not expose a large application
task worth removing or support speculative React memoization changes.

Evidence: `.build/rn-optimization-audit/exact-startup.trace`,
`exact-samples.xml`, `profile-summary.json`, and `summarize-profile.py`.
The earlier `startup.trace` and `verified-startup.trace` hit an older binary
and are explicitly excluded.

## Recommendation and applied state

- **Applied before this audit:** ARM64 enforcement and release symbol stripping.
  Corrected public baseline: 8.56 MiB.
- **Promoted native settings:** dead-code stripping, ThinLTO, and `-Oz`.
  Dead-code stripping alone removes
  about 0.61 MiB without removing RN capabilities.
- **For a stronger size target:** ThinLTO plus `-Oz` reached 7.15 MiB, about
  16.4% smaller than the corrected baseline, with the original public imports.
  Keep the CPU/latency tradeoff in mind for workloads beyond Hello World.
- **Do not prioritize extra JS minification:** 45 KB saved and no demonstrated
  startup/memory gain in the completed comparison.
- **Do not promote private imports or blind native-module removal:** they
  change the supported API surface or rely on internal implementation details.
- **No startup rewrite justified:** the app is minimal; the profile points
  primarily to platform/runtime startup, not removable application work.

The public Hello World build now explicitly enables `DEAD_CODE_STRIPPING=YES`,
`LLVM_LTO=YES_THIN`, and `GCC_OPTIMIZATION_LEVEL=z`, in addition to the earlier
packaging fix. Its verified canonical bundle is **7,499,962 bytes (7.15 MiB)**,
16.4% smaller than the symbol-stripped baseline. Both executable and Hermes are
ARM64-only and the deep code-signature verification passes. The slight size
difference from the experimental copy reflects packaging identity/signature.
Public RN imports and default Hermes bundling remain unchanged. Original
cross-framework timing/memory numbers remain historical, not candidate results.

## Shared Legend Apps rollout

The shared `legend-apps/scripts/build-app.ts` macOS release path now enables
all three native settings for every app, including the Chat History benchmark
exporter. Debug, iOS, and Android builds are unchanged. Source-built Pods receive
the flags; prebuilt Hermes and the separately built grammar pack do not.

Chat History's app bundle changed from 20,614,246 to **18,629,704 bytes** (9.6%
smaller). With its unchanged 23,617,711-byte grammar pack, total installed size
is **42,247,415 bytes (40.3 MiB)**. ARM64 and deep code-signature checks pass.

One warmup and three measured runs on each side passed visible phase checks,
with matching normalized transcript digests and no discarded attempts:

| Metric | Existing build | Optimized rebuild |
| --- | ---: | ---: |
| First content p50 / p90, ms | 386.2 / 1518.5 | 416.7 / 461.2 |
| Jump to top p50, ms | 43.2 | 35.9 |
| Conversation switch p50, ms | 181.4 | 189.4 |
| Initial native work p50, ms | 44.2 | 35.1 |
| Switch native work p50, ms | 26.7 | 28.4 |
| Initial footprint, MiB | 52.4 | 52.8 |
| Switched footprint, MiB | 65.2 | 65.3 |

These are regression smoke checks on a shared machine, not a controlled
same-source compiler A/B: the baseline was the existing exported build, while
the optimized binary was rebuilt from the current working tree. Startup has
substantial variance. The data establish smaller artifacts and functional
parity, not a speed gain or proof that small regressions are absent. Retain
`-Oz` as the requested size-oriented release default; qualify CPU-heavy app
workloads before interpreting it as a performance improvement.

Evidence: `benchmarks/chat-history/results/2026-09-18T09-10-00.961Z.{json,md}`
and `2026-09-18T09-15-55.170Z.{json,md}`, with their companion video directories.
All-app configuration verification, workspace typecheck, and six release-profile
and signing tests pass in Legend Apps. Test Kitchen Sink also builds with these
settings; ARM64 and deep signing checks pass. Its exact release executable
remained alive for a 15-second launch smoke check before being terminated.
App-scoped UI snapshot automation timed out, so full native-feature interaction
coverage is not claimed. Compiler response files confirm `-Oz` and ThinLTO for
audio, Markdown parsing, and window management. The additional Kitchen Sink
build tree occupies about 3.6 GiB and is retained locally.

## Validation and retained artifacts

- Corrected baseline and all three native compiler variants built successfully.
- The promoted official build passed one warmup and three measured greeting OCR
  checks, with separate memory launches: 218.9 / 275.7 ms first-content p50 / p90
  and 23.3 MiB settled footprint. This is smoke validation, not evidence of a
  speed improvement. Evidence: `benchmarks/hello-world/results/2026-09-18T09-07-10.584Z/`.
- Eight focused benchmark CLI/configuration tests and TypeScript checking pass.
- Six variants passed repeated visible-content OCR checks and separate memory
  launches; native artifact paths were checked on each launch.
- The `oz` greeting screenshot was inspected.
- ARM64 was verified for each variant executable and its Hermes framework.
- A disk guard checked free space every five seconds during guarded builds,
  profiling, and the variant run. No disk-reserve stop was needed.

Investigation binaries, traces, link maps, source maps, logs, and temporary
runner sources are retained under `.build/rn-optimization-audit/`. Recorded
benchmark evidence remains in the two result directories above. They are
disposable local evidence, not files to publish with the talk.

## Reproduction

From this repository root, rebuild the optimized public baseline with:

```sh
bun benchmarks/hello-world/build.ts --app react-native
```

The native experiments use the same workspace, scheme, Release configuration,
and DerivedData directory. Base arguments:

```sh
xcodebuild \
  -workspace apps/hello-world-react-native/macos/HelloWorld.xcworkspace \
  -scheme HelloWorld-macOS -configuration Release \
  -derivedDataPath apps/hello-world-react-native/build \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO DEPLOYMENT_POSTPROCESSING=YES \
  CODE_SIGNING_ALLOWED=NO DEAD_CODE_STRIPPING=YES \
  LLVM_LTO=YES_THIN GCC_OPTIMIZATION_LEVEL=z build
```

Omit `LLVM_LTO`/`GCC_OPTIMIZATION_LEVEL` for the dead-strip-only experiment;
omit `GCC_OPTIMIZATION_LEVEL` for ThinLTO at the existing `-Os`. Package with
`ditto`, strip Hermes with `strip -S -x`, and ad-hoc sign before launching.
A link map can be requested with `LD_GENERATE_MAP_FILE=YES` and an absolute
`LD_MAP_FILE_PATH`. `file RCTBridge.o` verifies the ThinLTO object is LLVM bitcode;
compiler response files verify `-Oz` in the size-oriented variant.

For JS experiments, use the existing RN CLI `bundle` command with `--platform
macos --entry-file index.js --dev false`, request a source map, and compare
`--minify false` with `--minify true`. Compile each output using the installed
Hermes `hermesc -O -emit-binary -max-diagnostic-width=80`, replace only the JS
bytecode in a copied corrected-baseline app, and re-sign. The direct-import
entry is retained as an experimental artifact, not a public entry-point change.
