import AppKit
import SwiftUI
import SwiftStreamingMarkdown
@main @MainActor enum Probe {
 static func main() async throws {
  _ = NSApplication.shared
  let all = try JSONSerialization.jsonObject(with: Data(contentsOf:URL(fileURLWithPath:"/tmp/md-workload-messages.json"))) as! [[String:Any]]
  var inputs:[(String,String)] = [("heading", "# First\n\n## Second\n\nbody"),("nested-code", "1. step\n\n   ```swift\n   let x = 1\n   ```\n\n   after"),("table", "| A | B |\n|---|---|\n| one | two |"),("quote", "> **bold** and `code`\n>\n> - first\n> - second")]
  for (f,r) in [(0,0),(0,7),(1,166)] { if let item=all.first(where: { ($0["fixture"] as? Int)==f && ($0["row"] as? Int)==r }) { inputs.append(("fixture-\(f)-row-\(r)",item["markdown"] as! String)) } }
  let config=MarkdownRenderConfig.default.withShouldAnimateText(value:false)
  for (name,source) in inputs {
   let document=await MarkdownParserImpl().parse(text:source,config:config)
   for width in [886.0,400.0] {
    let host=NSHostingController(rootView:DocumentView(renderableDocument:document,config:config))
    host.view.frame=NSRect(x:0,y:0,width:width,height:10000);host.view.layoutSubtreeIfNeeded()
    let size=host.sizeThatFits(in:NSSize(width:width,height:1000000))
    print(name,"width",width,"height",size.height,"finite",size.height.isFinite && size.height>0)
   }
  }
 }
}
