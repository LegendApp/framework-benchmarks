#!/usr/bin/env python3
"""Build the actual AppKit UI with a temporary entry point and verify resizing."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[3]
source = (repo / 'apps/chat-history-appkit/Sources/ChatHistoryAppKit/main.swift').read_text()
start = source.index('    let app = NSApplication.shared')
end = source.index('\n  }\n}', start)
source = source[:start] + '    _ = NSApplication.shared\n    runLayoutQA()\n    runWindowGeometryQA()\n' + source[end:]
source += '\n' + Path(__file__).with_name('appkit-layout-check.swift').read_text()
fixtures = json.loads((repo / 'ChatHistory/benchmark/fixtures.local.json').read_text())
with tempfile.TemporaryDirectory(prefix='chat-appkit-layout-check-') as directory:
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
    config = package / 'benchmark.json'
    config.write_text(json.dumps({'version': 2, 'loadImages': False, 'topDelayMs': 100000,
        'switchDelayMs': 100000, 'targets': [{'id': item['id'], 'provider': item['provider']} for item in fixtures['fixtures'][:2]],
        'samples': fixtures['fixtures']}))
    subprocess.run([str(package / '.build/release/LayoutQA'), fixtures['fixtures'][1]['path']], check=True,
        env={**os.environ, 'CHAT_HISTORY_BENCHMARK_CONFIG': str(config)})
