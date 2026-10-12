#!/usr/bin/env python3
"""Make the existing detector use disposable app bundles and timing-only launches."""
from pathlib import Path
import json
import os
repo = Path(__file__).resolve().parents[4]
root = Path(os.environ.get('CHAT_PLATFORM_PROFILE_ROOT', '/tmp/chat-platform-profile'))
runner = Path('/tmp/chat-native-benchmark-runner')
runner.mkdir(exist_ok=True)
benchmark = repo / 'benchmarks/chat-history'
s = (benchmark / 'run.ts').read_text().replace('import.meta.dir', json.dumps(str(benchmark)))
for platform, executable in [('AppKit', 'ChatHistoryAppKit'), ('SwiftUI', 'ChatHistorySwiftUI')]:
    bundle = f'Chat History — {platform}.app'
    s = s.replace(f'bundle: resolve(buildRoot, "{bundle}"),', f'bundle: {json.dumps(str(root / bundle))},')
    s = s.replace(f'executable: resolve(buildRoot, "{bundle}/Contents/MacOS/{executable}"),', f'executable: {json.dumps(str(root / bundle / "Contents/MacOS" / executable))},')
s = s.replace('if (recordVideo) {\n        console.log(`${app}: settled-memory', 'if (false) {\n        console.log(`${app}: settled-memory')
s = s.replace('    nativeParser:', '    diagnosticVariant: process.env.CHAT_PLATFORM_VARIANT ?? "baseline",\n    diagnosticMemory: "not measured",\n    nativeParser:')
(runner / 'platform-ablation.ts').write_text(s)
(runner / 'video.ts').write_text((benchmark / 'video.ts').read_text().replace('import.meta.dir', json.dumps(str(benchmark))))
print(runner / 'platform-ablation.ts')
