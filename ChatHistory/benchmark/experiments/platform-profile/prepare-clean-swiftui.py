import os
from pathlib import Path
import shutil,json
repo=Path(__file__).resolve().parents[4];r=Path(os.environ.get("CHAT_PLATFORM_PROFILE_ROOT", "/tmp/chat-platform-profile"));p=r/'swiftui-clean';(p/'Sources/ChatHistorySwiftUI').mkdir(parents=True,exist_ok=True)
s=(repo/'apps/chat-history-swiftui/Sources/ChatHistorySwiftUI/main.swift').read_text()
a='''            TranscriptRow(
              loadImages: settings.loadImages, row: rows[index], markdownCache: markdownCache
            )'''
b='''            LazyTranscriptRow(
              loadImages: settings.loadImages, rows: rows, index: index, markdownCache: markdownCache
            )'''
assert a in s;s=s.replace(a,b)
s+='''
private struct LazyTranscriptRow: View {
 let loadImages: Bool
 let rows: ChatRows
 let index: Int
 let markdownCache: TranscriptMarkdownCache
 var body: some View {
   VStack(spacing: 0) {
     TranscriptRow(loadImages: loadImages, row: rows[index], markdownCache: markdownCache)
   }
 }
}
'''
(p/'Sources/ChatHistorySwiftUI/main.swift').write_text(s)
(p/'Package.swift').write_text('''// swift-tools-version: 6.2
import PackageDescription
let package=Package(name:"ChatHistorySwiftUI",platforms:[.macOS(.v14)],dependencies:[.package(path:'''+json.dumps(str(repo/'packages/chat-history-swift'))+''')],targets:[.executableTarget(name:"ChatHistorySwiftUI",dependencies:[.product(name:"ChatHistoryCore",package:"chat-history-swift"),.product(name:"ChatHistoryMarkdown",package:"chat-history-swift")])])
''')
shutil.copy2(repo/'.build/chat-history-benchmarks/Chat History — SwiftUI.app/Contents/MacOS/ChatHistorySwiftUI',r/'SwiftUI-clean-baseline')
s=(r/'video-pairs.py').read_text();s=s.replace("static=root/'source/apps/chat-history-swiftui/.build/release/ChatHistorySwiftUI';shutil.copy2(static,root/'SwiftUI-static-row')","static=root/'swiftui-clean/.build/release/ChatHistorySwiftUI';shutil.copy2(static,root/'SwiftUI-clean-static-row')")
s=s.replace("plan=[('appkit',v) for v in ['baseline','no-window-animation','no-window-animation','baseline','baseline','no-window-animation']]+",'plan=')
s=s.replace("'SwiftUI-baseline' if variant=='baseline' else 'SwiftUI-static-row'","'SwiftUI-clean-baseline' if variant=='baseline' else 'SwiftUI-clean-static-row'")
s=s.replace("video-pair-{i+1:02d}","video-clean-pair-{i+1:02d}").replace('results/video-pairs.json','results/video-clean-pairs.json')
(r/'video-clean-pairs.py').write_text(s)
