#!/usr/bin/env python3
"""Measure actual SwiftUI text and row layout using the production source."""
from pathlib import Path
import json
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
source = (repo / 'apps/chat-history-swiftui/Sources/ChatHistorySwiftUI/main.swift').read_text()
source = source.replace('@main\n', '', 1)
source += '\n' + Path(__file__).with_name('swiftui-layout-check.swift').read_text()
with tempfile.TemporaryDirectory(prefix='chat-swiftui-layout-check-') as directory:
    package = Path(directory)
    target = package / 'Sources/LayoutQA'
    target.mkdir(parents=True)
    (target / 'main.swift').write_text(source)
    dependency = json.dumps(str(repo / 'packages/chat-history-swift'))
    (package / 'Package.swift').write_text(f'''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "LayoutQA", platforms: [.macOS(.v14)], dependencies: [.package(path: {dependency})], targets: [.executableTarget(name: "LayoutQA", dependencies: [.product(name: "ChatHistoryCore", package: "chat-history-swift"), .product(name: "ChatHistoryMarkdown", package: "chat-history-swift")])])
''')
    subprocess.run(['swift', 'build', '-c', 'release', '-debug-info-format', 'none', '--package-path', directory], check=True)
    subprocess.run([str(package / '.build/release/LayoutQA')], check=True)
