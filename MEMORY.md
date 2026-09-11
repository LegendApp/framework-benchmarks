# Project Environment

Argent environment inspection (2026-09-09): this is a Bun macOS desktop comparison repository, not an iOS/Android React Native project. Product React Native macOS is exported from sibling `legend-apps`. Local toolchain wrappers live in `scripts/with-local-{rust,flutter,deno}.sh`. Use `bun run typecheck` for TypeScript and each app's build command for native validation. Existing product suite: `bun run benchmark:build` / `bun run benchmark:run`; requires pinned transcripts and Screen Recording permission. Hello World apps and their independent suite live in `apps/hello-world-*` and `benchmarks/hello-world`.

```json
{"is_react_native":false,"is_native_ios":false,"is_native_android":false,"platform_support":["macOS"],"package_manager":"bun","technologies":["react-native","electron","tauri","deno-webview","deno-cef","flutter","gpui","swiftui","appkit"],"toolchains":{"rust":"scripts/with-local-rust.sh","flutter":"scripts/with-local-flutter.sh","deno":"scripts/with-local-deno.sh","swift":"Swift Package Manager"},"argent_available":true}
```
