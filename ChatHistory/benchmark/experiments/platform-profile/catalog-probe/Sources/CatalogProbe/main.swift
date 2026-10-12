import Foundation
import ChatHistoryCore
for round in 0..<6 {
 PlatformTrace.phase("round-\(round)")
 let t=PlatformTrace.now()
 let result=getRecentChats(limit:Int.max)
 PlatformTrace.end("catalog.total",t,String(result.summaries.count))
}
PlatformTrace.flushSoon()
Thread.sleep(forTimeInterval:1.5)
