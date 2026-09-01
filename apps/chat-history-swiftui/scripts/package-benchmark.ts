import { chmodSync, copyFileSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const appRoot = resolve(import.meta.dir, "..");
const repositoryRoot = resolve(appRoot, "../..");
const sourceExecutable = resolve(appRoot, ".build/release/ChatHistorySwiftUI");
const outputApp = resolve(repositoryRoot, ".build/chat-history-benchmarks/Chat History — SwiftUI.app");
const outputExecutable = resolve(outputApp, "Contents/MacOS/ChatHistorySwiftUI");

rmSync(outputApp, { force: true, recursive: true });
mkdirSync(dirname(outputExecutable), { recursive: true });
copyFileSync(sourceExecutable, outputExecutable);
chmodSync(outputExecutable, 0o755);
writeFileSync(resolve(outputApp, "Contents/Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Chat History — SwiftUI</string>
<key>CFBundleExecutable</key><string>ChatHistorySwiftUI</string>
<key>CFBundleIdentifier</key><string>so.legend.chathistory.swiftui</string>
<key>CFBundleName</key><string>Chat History — SwiftUI</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
</dict></plist>
`);
execFileSync("codesign", ["--force", "--deep", "--sign", "-", outputApp]);
console.log(outputApp);
