import AppKit
import SwiftUI
import MarkdownView
@main @MainActor enum Probe {
 static func main() throws {
  _ = NSApplication.shared
  let all = try JSONSerialization.jsonObject(with: Data(contentsOf:URL(fileURLWithPath:"/tmp/md-workload-messages.json"))) as! [[String:Any]]
  var inputs:[(String,String)] = [("heading", "# First\n\n## Second\n\nbody"),("nested-code", "1. step\n\n   ```swift\n   let x = 1\n   ```\n\n   after"),("table", "| A | B |\n|---|---|\n| one | two |"),("quote", "> **bold** and `code`\n>\n> - first\n> - second")]
  inputs.append(("list-start", "3. third\n4. fourth"))
  for (name,source) in inputs {
   for width in [886.0,400.0] {
    let view = MarkdownText(source).font(NSFont.systemFont(ofSize:15),for:.body).font(NSFont.boldSystemFont(ofSize:22),for:.h1).font(NSFont.boldSystemFont(ofSize:19),for:.h2)
    let host = NSHostingController(rootView:view)
    host.view.frame=NSRect(x:0,y:0,width:width,height:10000)
    host.view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until:Date(timeIntervalSinceNow:0.005))
    let size=host.sizeThatFits(in:NSSize(width:width,height:1000000))
    print(name, "width",width,"height",size.height,"finite",size.height.isFinite && size.height>0)
    func inspect(_ node:NSView) {
     if let text=node as? NSTextView { print("TEXT",name,text.string.replacingOccurrences(of:"\n",with:"|"));var fonts=Set<Double>();text.textStorage?.enumerateAttribute(.font,in:NSRange(location:0,length:text.string.utf16.count)) { value,_,_ in if let font=value as? NSFont { fonts.insert(font.pointSize) } };print("FONTS",name,fonts.sorted()) }
     for child in node.subviews {inspect(child)}
    }
    inspect(host.view)
   }
  }
 }
}
