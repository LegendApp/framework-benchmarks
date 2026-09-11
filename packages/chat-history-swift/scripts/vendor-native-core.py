"""Vendor the benchmark RN core without its JavaScript/registry adapters.

Run with the path to a legend-apps git repository. The pinned source is the
September 11 RN source, including output-kind and ordinal-envelope fast paths.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

revision = '89561d1ac6f39c8402797abbdbdd221fe1135ce8'
repo = sys.argv[1]
target = Path(__file__).resolve().parents[1] / 'Sources/ChatHistoryNative/core'
target.mkdir(parents=True, exist_ok=True)
provenance = {}
def source(path):
    value = subprocess.check_output(['git', '-C', repo, 'show', f'{revision}:{path}']).decode()
    provenance[path] = hashlib.sha256(value.encode()).hexdigest()
    return value

for name in ['ChatJson.hpp', 'ChatJson.cpp', 'ChatTime.hpp', 'ChatTime.cpp', 'ChatTranscriptParser.cpp']:
    (target / name).write_text(source('packages/chat-history/cpp/' + name))
(target / 'NativeTextSource.hpp').write_text(source('packages/native-text-source/cpp/NativeTextSource.hpp'))
# Keep the generated plain value structs; exclude all JSI conversion code.
values = '#pragma once\n#include <string>\n#include <optional>\n'
for name in ['ChatDocumentTiming', 'ChatRowMetadata', 'ChatFileChange']:
    raw = source(f'packages/chat-history/nitrogen/generated/shared/c++/{name}.hpp')
    start = raw.index('namespace margelo::nitro::legendapps::chathistory {')
    end = raw.index('} // namespace margelo::nitro::legendapps::chathistory', start)
    values += raw[start:end] + '}\n'
values = values.replace('SWIFT_PRIVATE', '')
(target / 'DocumentValues.hpp').write_text(values)
raw = source('packages/chat-history/cpp/ChatDocument.hpp')
raw = raw.replace('#include "../nitrogen/generated/shared/c++/ChatDocumentTiming.hpp"', '#include "DocumentValues.hpp"')
raw = raw[:raw.index('std::string makeChatDocumentId();')] + '} // namespace margelo::nitro::legendapps::chathistory\n'
(target / 'ChatDocument.hpp').write_text(raw)
for extension in ['hpp', 'cpp']:
    raw = source('packages/chat-history/cpp/HybridChatDocument.' + extension)
    raw = raw.replace('HybridChatDocument', 'NativeDocument')
    raw = raw.replace('#include "ChatImageDimensions.hpp"\n', '')
    # Native Swift image rendering already owns image metadata and decoding.
    raw = re.sub(r'  ChatImageMetadata getImageMetadata[^\n]*\n', '', raw)
    raw = re.sub(r'ChatImageMetadata NativeDocument::getImageMetadata\(.*?\n}\n', '', raw, flags=re.S)
    raw = raw.replace('#include "../nitrogen/generated/shared/c++/NativeDocumentSpec.hpp"', '')
    raw = raw.replace(' : public NativeDocumentSpec', '').replace(' override', '')
    raw = raw.replace(': HybridObject(TAG),\n      documentId_', ': documentId_')
    raw = raw.replace('  ChatDocumentRegistry::shared().unregisterDocument(documentId_);\n', '')
    raw = raw.replace('markdownBlockId(documentId_, displayIndex)', 'documentId_ + ":" + std::to_string(displayIndex)')
    (target / ('NativeDocument.' + extension)).write_text(raw)
(target.parent / 'PROVENANCE.json').write_text(json.dumps({'repository': 'legend-apps', 'revision': revision, 'sourceSHA256': provenance}, indent=2) + '\n')
