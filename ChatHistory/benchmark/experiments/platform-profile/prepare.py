#!/usr/bin/env python3
"""Prepare a disposable source tree; never modify production sources or bundles."""
from pathlib import Path
import os
import shutil
import subprocess

repo = Path(__file__).resolve().parents[4]
root = Path(os.environ.get('CHAT_PLATFORM_PROFILE_ROOT', '/tmp/chat-platform-profile'))
source = root / 'source'
if source.exists():
    raise SystemExit(f'{source} already exists; use a fresh CHAT_PLATFORM_PROFILE_ROOT')
for relative in ['apps/chat-history-appkit', 'apps/chat-history-swiftui', 'packages/chat-history-swift']:
    shutil.copytree(repo / relative, source / relative, ignore=shutil.ignore_patterns('.build'))
subprocess.run(['git', 'apply', str(Path(__file__).with_name('instrumentation.patch'))], cwd=source, check=True)
print(source)
