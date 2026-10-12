import { copySwiftResources } from "../../../../scripts/package-swift-resources";
import { execFileSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../../..");
const sourceExecutable = resolve(appRoot, ".build/release/ChatHistoryAppKit");
const outputApp = resolve(repositoryRoot, ".build/chat-history-benchmarks/Chat History — AppKit.app");
const outputExecutable = resolve(outputApp, "Contents/MacOS/ChatHistoryAppKit");

rmSync(outputApp, { force: true, recursive: true });
mkdirSync(dirname(outputExecutable), { recursive: true });
copyFileSync(sourceExecutable, outputExecutable);
chmodSync(outputExecutable, 0o755);
copySwiftResources(appRoot, outputApp);
writeFileSync(resolve(outputApp, "Contents/Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Chat History — AppKit</string>
<key>CFBundleExecutable</key><string>ChatHistoryAppKit</string>
<key>CFBundleIdentifier</key><string>so.legend.chathistory.appkit</string>
<key>CFBundleName</key><string>Chat History — AppKit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
</dict></plist>
`);
execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
console.log(outputApp);
