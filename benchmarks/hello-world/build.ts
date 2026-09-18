import { buildEnvironment, type BuildEnvironment } from "../build-environment";
import { execFileSync, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { buildRoot, bundlePath, labels, repositoryRoot, selectedApps, option, type AppName } from "./config";

const legendAppsRepository = resolve(option("--legend-apps-repo") ?? process.env.LEGEND_APPS_REPO ?? resolve(repositoryRoot, "../legend-apps"));

function run(command: string, args: string[], cwd = repositoryRoot, env = process.env) {
  console.log(`$ ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { cwd, env, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.signal})`);
}

function web(appRoot: string) {
  mkdirSync(join(appRoot, "dist"), { recursive: true });
  run("bun", ["build", "packages/hello-world-web/renderer.tsx", "--outdir", join(appRoot, "dist"),
    "--target", "browser", "--format", "esm", "--production"]);
  cpSync(resolve(repositoryRoot, "packages/hello-world-web/index.html"), join(appRoot, "dist/index.html"));
}

function copyApp(source: string, app: AppName) {
  if (!existsSync(source)) throw new Error(`Build did not produce ${source}`);
  const output = bundlePath(app);
  rmSync(output, { recursive: true, force: true });
  // ditto preserves framework symlinks and executable modes.
  run("ditto", [source, output]);
}

function nativeBundle(executable: string, app: AppName) {
  const output = bundlePath(app);
  rmSync(output, { recursive: true, force: true });
  mkdirSync(join(output, "Contents/MacOS"), { recursive: true });
  cpSync(executable, join(output, "Contents/MacOS/HelloWorld"));
  writeFileSync(join(output, "Contents/Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HelloWorld</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>\n`);
}

function sign(app: AppName) {
  const info = join(bundlePath(app), "Contents/Info.plist");
  for (const [key, value] of Object.entries({
    CFBundleDisplayName: `Hello World — ${labels[app]}`,
    CFBundleName: `Hello World — ${labels[app]}`,
    CFBundleIdentifier: `so.legend.helloworld.${app.replaceAll("-", ".")}`,
  })) run("plutil", ["-replace", key, "-string", value, info]);
  run("codesign", ["--force", "--deep", "--sign", "-", bundlePath(app)]);
}

async function build(app: AppName) {
  const appRoot = resolve(repositoryRoot, `apps/hello-world-${app.startsWith("deno-") ? "deno" : app}`);
  switch (app) {
    case "legend-shell": {
      run("bun", ["run", "hello-world:benchmark:export", "--output", bundlePath(app)], legendAppsRepository);
      break;
    }
    case "electron": {
      web(appRoot);
      run("bun", ["build", join(appRoot, "src/main.ts"), "--outdir", join(appRoot, "dist"),
        "--target", "node", "--format", "esm", "--external", "electron", "--minify"]);
      const electronRoot = dirname(require.resolve("electron/package.json", { paths: [appRoot] }));
      copyApp(join(electronRoot, "dist/Electron.app"), app);
      const resources = join(bundlePath(app), "Contents/Resources");
      rmSync(join(resources, "default_app.asar"), { force: true });
      cpSync(join(appRoot, "dist"), join(resources, "app/dist"), { recursive: true });
      writeFileSync(join(resources, "app/package.json"), JSON.stringify({ name: "hello-world", version: "0.0.1", main: "dist/main.js", type: "module" }));
      break;
    }
    case "appkit":
    case "swiftui": {
      run("swift", ["build", "-c", "release", "--package-path", appRoot]);
      nativeBundle(join(appRoot, `.build/release/HelloWorld${labels[app]}`), app);
      break;
    }
    case "gpui": {
      run(resolve(repositoryRoot, "scripts/with-local-rust.sh"), ["cargo", "build", "--release", "--locked", "--manifest-path", join(appRoot, "Cargo.toml")]);
      nativeBundle(join(appRoot, "target/release/hello-world-gpui"), app);
      break;
    }
    case "tauri": {
      web(appRoot);
      run(resolve(repositoryRoot, "scripts/with-local-rust.sh"), ["bun", "x", "--no-install", "tauri", "build", "--bundles", "app", "--", "--locked"], appRoot);
      copyApp(join(appRoot, "src-tauri/target/release/bundle/macos/Hello World — Tauri.app"), app);
      break;
    }
    case "deno-webview":
    case "deno-cef": {
      web(appRoot);
      const backend = app === "deno-webview" ? "webview" : "cef";
      run(resolve(repositoryRoot, "scripts/with-local-deno.sh"), ["deno", "desktop", "--no-npm", "--allow-read", "--allow-net=127.0.0.1:8000",
        "--include", "./dist", "--backend", backend, "--icon", "../chat-history-tauri/src-tauri/icons/icon.icns",
        "--output", `./build/Hello World - ${labels[app]}`, "src/main.ts"], appRoot);
      copyApp(join(appRoot, `build/Hello World - ${labels[app]}.app`), app);
      break;
    }
    case "flutter": {
      run(resolve(repositoryRoot, "scripts/with-local-flutter.sh"), ["flutter", "build", "macos", "--release"], appRoot);
      copyApp(join(appRoot, "build/macos/Build/Products/Release/Hello World - Flutter.app"), app);
      break;
    }
    case "react-native": {
      const env = { ...process.env, RCT_NEW_ARCH_ENABLED: "1", RCT_NO_LAUNCH_PACKAGER: "1" };
      run("pod", ["install"], join(appRoot, "macos"), env);
      const derived = join(appRoot, "build");
      run("xcodebuild", ["-workspace", "macos/HelloWorld.xcworkspace", "-scheme", "HelloWorld-macOS", "-configuration", "Release",
        "-derivedDataPath", derived, "-destination", "platform=macOS,arch=arm64", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "DEPLOYMENT_POSTPROCESSING=YES", "CODE_SIGNING_ALLOWED=NO", "build"], appRoot, env);
      copyApp(join(derived, "Build/Products/Release/HelloWorld.app"), app);
      // Match the product release packaging: strip local Hermes symbols before signing.
      run("strip", ["-S", "-x", join(bundlePath(app), "Contents/Frameworks/hermes.framework/Versions/Current/hermes")]);
      break;
    }
  }
  sign(app);
}

const targets = selectedApps();
if (process.argv.includes("--launch") && targets.length !== 1) throw new Error("--launch requires one --app");
mkdirSync(buildRoot, { recursive: true });
const manifestPath = join(buildRoot, "build-manifest.json");
type BuildRecord = { environment?: BuildEnvironment; builtAt: string; gitCommit: string; gitDirty: boolean; bundle: string; repositoryPath: string };
const manifest: { version: 1; workload: "hello-world"; builds: Partial<Record<AppName, BuildRecord>> } = existsSync(manifestPath)
  ? JSON.parse(readFileSync(manifestPath, "utf8")) : { version: 1, workload: "hello-world", builds: {} };
for (const app of targets) {
  // Invalidate provenance before building, including if a rebuild fails halfway through.
  delete manifest.builds[app];
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  const environment = buildEnvironment(repositoryRoot, app);
  await build(app);
  const sourceRepository = app === "legend-shell" ? legendAppsRepository : repositoryRoot;
  const git = (...args: string[]) => execFileSync("git", args, { cwd: sourceRepository, encoding: "utf8" }).trim();
  Object.assign(manifest, JSON.parse(readFileSync(manifestPath, "utf8")));
  manifest.builds[app] = { environment, builtAt: new Date().toISOString(), gitCommit: git("rev-parse", "HEAD"), gitDirty: !!git("status", "--porcelain"), bundle: bundlePath(app), repositoryPath: sourceRepository };
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}
if (process.argv.includes("--launch")) run("open", ["-n", bundlePath(targets[0])]);
console.log(`Build manifest: ${manifestPath}`);
