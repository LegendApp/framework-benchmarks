import { chmodSync, copyFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../..");
const sourceExecutable = resolve(appRoot, "target/release/legend-chat-history-gpui");
const sourceIcon = resolve(repositoryRoot, "apps/chat-history-tauri/src-tauri/icons/icon.icns");
const outputApp = resolve(
  repositoryRoot,
  ".build/chat-history-benchmarks/Chat History — GPUI.app",
);
const outputExecutable = resolve(outputApp, "Contents/MacOS/legend-chat-history-gpui");
const outputIcon = resolve(outputApp, "Contents/Resources/AppIcon.icns");

rmSync(outputApp, { force: true, recursive: true });
mkdirSync(dirname(outputExecutable), { recursive: true });
mkdirSync(dirname(outputIcon), { recursive: true });
copyFileSync(sourceExecutable, outputExecutable);
copyFileSync(sourceIcon, outputIcon);
chmodSync(outputExecutable, 0o755);
writeFileSync(
  resolve(outputApp, "Contents/Info.plist"),
  `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Chat History — GPUI</string>
<key>CFBundleExecutable</key><string>legend-chat-history-gpui</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>so.legend.chathistory.gpui</string>
<key>CFBundleName</key><string>Chat History — GPUI</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
`,
);
execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
console.log(outputApp);
