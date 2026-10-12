# Benchmark command reference

## Setup

Use a Mac with an active display. Install Bun and run `bun install` from this repository. Benchmarking requires Xcode command-line tools (for the measurement helpers), `ffmpeg`, and `ffprobe`. Grant Screen Recording permission to **Chat History Benchmark Capture** when requested; a first run may need to be restarted after granting access.

Building additionally requires the selected frameworks' toolchains: full Xcode and CocoaPods for React Native, Rust for Tauri/GPUI, Flutter for Flutter, and a Deno Desktop-capable toolchain for Deno. The scripts prefer repository-scoped tools in `.toolchains`, then `PATH`; they do not modify shell startup files. Dependencies may be downloaded during builds.

The chat-history React Native app and Hello World **Legend Shell** app come from the sibling `../legend-apps` checkout. Install that repository's dependencies too. Override its location with `LEGEND_APPS_REPO` or `--legend-apps-repo /absolute/path`; the unified builder uses that exact checkout, without switching to another worktree. Standalone Hello World React Native lives here and does not need the sibling.

## Build, then benchmark

```sh
bun install

# Preview all release builds, then confirm [y/N] before starting.
bun run benchmark:build

# Chat history only: select and pin local input files once.
bun run benchmark:fixtures

# Measure all existing builds; does not rebuild apps.
bun run benchmark:run
```

With no arguments, both commands select **all 20 apps across both workloads**, sequentially. Building replaces selected bundles under `.build/chat-history-benchmarks/` and `.build/hello-world-benchmarks/` and writes provenance manifests there. There is no implicit build during benchmarking. `bun run benchmark` is an alias for `benchmark:run`; unlike the old command, it no longer builds or selects only chat history.

The fixture selector uses your local Codex/Claude histories, choosing two large histories inactive for at least eight days. Paths and hashes stay in ignored `ChatHistory/benchmark/fixtures.local.json`. The runner verifies those files before measurement. Do not repin between comparative runs. Another person's corpus may produce different results. Hello World needs no history files; use `--suite hello-world` if you do not have a suitable corpus.

Keep the Mac **unlocked and otherwise idle** throughout measurement. The runner holds the display awake. Close other copies of these apps, particularly Deno apps using port 8000. The full default run can take over an hour, plus build time. Warmups exercise caches: these are fresh-process launches, not cold-machine or first-install measurements.

```sh
# Build and measure one technology in both workloads.
bun run benchmark:build --app gpui
bun run benchmark:run --app gpui

# Only the chat-history native apps.
bun run benchmark:build --suite chat-history --app appkit,swiftui
bun run benchmark:run --suite chat-history --app appkit,swiftui

# Short pipeline check, not publishable performance numbers.
bun run benchmark:run --suite hello-world --app electron --warmups 0 --iterations 1

# Inspect without starting work; explicitly bypass confirmation for automation.
bun run benchmark:build --dry-run
bun run benchmark:build --yes
bun run benchmark:run --dry-run
```

## Arguments and defaults

Both scripts accept `--name value` or `--name=value`. Unknown options and invalid values fail before execution. Use `--help` on either command.

| Argument | Commands | Default / behavior |
| --- | --- | --- |
| `--suite all\|chat-history\|hello-world` | Both | `all` |
| `--app all\|<comma-separated names>` | Both | `all`; names below |
| `--dry-run` | Both | Print selected apps, bundle directories, and underlying commands without executing |
| `--help` | Both | Show usage |
| `--yes` | Build | Skip confirmation; required without an interactive terminal |
| `--legend-apps-repo <path>` | Build | `LEGEND_APPS_REPO`, otherwise sibling `../legend-apps` |
| `--warmups <N>` | Run | `2` discarded rounds per app; minimum `0` |
| `--iterations <N>` | Run | `10` measured rounds per app; minimum `1` |
| `--settle-ms <N>` | Run | Hello World only: `5000` ms reference wait; minimum `1000`. With both suites, applies only to Hello World |

App names: `react-native`, `electron`, `tauri`, `deno-webview`, `deno-cef`, `flutter`, `gpui`, `compose`, `swiftui`, `appkit`. `deno` selects both backends. Selecting a technology without `--suite` selects its apps in both workloads. The chat-history Deno exporter always builds **both backends**, even when only one is requested; the preview shows this. Benchmarking still runs only the requested backend.

Suite-specific aliases are available: `benchmark:chat-history:build`, `benchmark:chat-history:run`, `benchmark:hello-world:build`, and `benchmark:hello-world:run`. Build aliases have the same confirmation. `benchmark:chat-history` and `benchmark:hello-world` are run-only aliases. Lower-level suite scripts are implementation/diagnostic entry points; use the commands above for normal builds and measurements.

Flutter release builds target ARM64 in both workloads, including the bundled engine and Dart code. These benchmark exports require Apple Silicon.

## Prebuilt releases

The release tooling packages all 20 apps and lets benchmark users download either the complete set or selected apps. A release must be published before downloads can work; setting up these scripts does not itself create one.

Install the GitHub CLI (`gh`), authenticate with `gh auth login`, and have Python 3 available alongside the measurement prerequisites above. You do **not** need Flutter, Rust, Deno, CocoaPods, or the sibling repository to benchmark downloaded apps. Xcode command-line tools are still required for measurement helpers. Download into a clean checkout of this repository at the release's tag; the downloader checks the exact source commit.

```sh
# From a checkout at the published release tag:
bun install
bun run benchmark:download --repo OWNER/REPO
bun run benchmark:fixtures  # Once, only when measuring chat history
bun run benchmark:run

# Pin a release and download only a subset.
bun run benchmark:download --repo OWNER/REPO --release bench-v1 --suite hello-world --app gpui
bun run benchmark:run --suite hello-world --app gpui
```

`--repo` defaults to `BENCHMARK_RELEASE_REPO`, then this checkout's GitHub `origin`. The release defaults to `latest`; it is resolved once, and the exact tag, manifest checksum, archive checksums, and bundle hashes are retained in the build manifests and benchmark JSON. `--suite` and `--app` have the same defaults and names as the builder. Chat-history Deno downloads include both backends because they share a build provenance record.

The downloader verifies GitHub's SHA-256 asset digests, manifest checksums, extracted file contents/permissions/symlinks, and code signatures. It stages all selected apps before replacing local bundles, and attempts rollback on installation errors. It preserves unselected apps. The benchmark runner rejects comparisons mixing local and release builds, different releases, or modified release bundles; download a matched set or rebuild all selected apps. The harness must remain clean at the release commit. Do not download or rebuild apps while a benchmark is running.

Each release currently targets one CPU architecture and conservatively requires the packaging Mac's macOS version or newer. This is a declared support floor, not a measurement of the oldest OS every framework could support. Current exports use ad-hoc signatures; these scripts verify code integrity but do not sign with a distribution identity or notarize apps. Gatekeeper approval and capture permission may still be needed on a new machine. No script disables Gatekeeper or removes quarantine.

### Publish a release

This is an explicit local publishing workflow, suitable for the configured Mac with all framework toolchains. It does not introduce a CI runner dependency. Commit the intended changes in **both** repositories and install their locked dependencies before building. All selected build records must be from those clean commits and include the build-time toolchain metadata. Existing dirty or stale builds are rejected rather than relabeled.

```sh
# On the release build Mac, from clean source checkouts:
bun run benchmark:build
bun run benchmark:release:package --tag bench-v1

# Push this exact comparison source commit/tag to the destination repository.
git tag bench-v1
git push origin HEAD
git push origin bench-v1

# Use the output directory printed by the packager (arm64 shown here).
bun run benchmark:release:publish \
  --repo OWNER/REPO \
  --directory .build/releases/bench-v1-macos-arm64
```

Packaging never builds or publishes. It requires all 20 apps and writes one `.tar.gz` per app, `benchmark-release.json`, and `SHA256SUMS`. Archives preserve executables and framework symlinks and exclude filesystem owner names and extended attributes. The manifest includes both source commits, per-app build-time tool versions, packaging-host tool versions, rendering policy, architecture, and signing limitations. Personal histories, local fixture manifests, videos, credentials, and source checkout paths are not added as release assets. Matching harness source is available through the release tag.

Publishing verifies the package checksums and requires the existing remote tag to point to the packaged comparison commit. It creates a draft, uploads the entire set, then publishes it as latest. Use `--draft` to leave the completed release unpublished for review. Existing releases are never overwritten. If uploading fails, the incomplete draft remains unpublished; inspect and remove that draft before retrying the command. Ensure the pinned `legend-apps` commit is also retained in its source repository.

| Command | Additional arguments |
| --- | --- |
| `benchmark:download` | `--repo OWNER/REPO`, `--release latest\|TAG`, `--suite`, `--app` |
| `benchmark:release:package` | Required `--tag TAG`; optional `--output NEW_DIRECTORY`, `--legend-apps-repo PATH` |
| `benchmark:release:publish` | Required `--directory PACKAGE_DIRECTORY`; optional `--repo OWNER/REPO`, `--draft` |

Every command supports `--help`. Package output defaults to `.build/releases/<tag>-macos-<arch>` and must not already exist. Custom output directories must be gitignored or outside the source checkout so packaging does not dirty the release source. Release names use letters, digits, dots, underscores, or hyphens. For normal user runs, downloading all individual archives with one command provides the complete set without maintaining a second, duplicate all-app archive.

Enable [GitHub release immutability](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes) in the destination repository before publishing. This prevents later replacement of published assets and tags. The tools verify digests even without that setting, but do not enable it automatically. Before advertising a release, validate launch behavior on a second Mac and run the default benchmark suite; publishing itself does not perform performance or visual validation.

Release regression checks: `bun test shared/benchmark/releases/releases.test.ts` and `python3 shared/benchmark/releases/archive_test.py`.

## Verification

```sh
bun run typecheck
bun test shared/benchmark ChatHistory/benchmark/*.test.ts HelloWorld/benchmark/benchmark.test.ts
python3 shared/benchmark/releases/archive_test.py
```

Harness details: [Chat History](../ChatHistory/benchmark/README.md), [Hello World](../HelloWorld/benchmark/README.md), and the [fairness standard](../ChatHistory/benchmark/FAIRNESS_STANDARD.md).
