import Foundation
import AppKit
import SwiftUI
import ChatHistoryCore
import ChatHistoryMarkdown
@main @MainActor enum TextProbe {
 static func main() throws {
  _ = NSApplication.shared
  let fixtures = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
  let paths=(fixtures["fixtures"] as! [[String:Any]]).map { $0["path"] as! String }
  var output:[[String:Any]]=[]
  for (file,index) in [(0,0),(0,7),(1,166)] {
   let document=try openChatFile(provider:.codex,path:paths[file]);let row=document.rows[index]
   let source=RichMarkdownRenderer.render(row.markdown,imagePolicy:.omit)
   var value=AttributedString(source)
   if #available(macOS 26,*) {
    value.swiftUI.lineHeight = .exact(points:22)
    source.enumerateAttribute(.paragraphStyle,in:NSRange(location:0,length:source.length)) { style,range,_ in
     if let style=style as? NSParagraphStyle,style.minimumLineHeight>0,let range=Range(range,in:value) { value[range].swiftUI.lineHeight = .exact(points:style.minimumLineHeight) }
    }
   }
   let width:CGFloat = row.kind == .user ? 757.66 : 885.96
   for round in 0..<6 {
    for method in ["NSTextField","TextKit","SwiftUI"] {
     let t=ProcessInfo.processInfo.systemUptime;let size:NSSize
     switch method {
     case "NSTextField":
      let label=NSTextField(wrappingLabelWithString:"");label.isSelectable=true;label.allowsEditingTextAttributes=true;label.maximumNumberOfLines=0;label.lineBreakMode = .byWordWrapping;label.attributedStringValue=source;label.preferredMaxLayoutWidth=width
      size=label.intrinsicContentSize
     case "TextKit":
      let container=NSTextContainer(containerSize:NSSize(width:width,height:.greatestFiniteMagnitude));container.lineFragmentPadding=0
      let manager=NSLayoutManager();manager.allowsNonContiguousLayout=false;manager.usesFontLeading=false;manager.addTextContainer(container)
      let storage=NSTextStorage(attributedString:source);storage.addLayoutManager(manager);manager.ensureLayout(for:container);size=manager.usedRect(for:container).size
     default:
      let controller=NSHostingController(rootView:Text(value).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading))
      size=controller.sizeThatFits(in:NSSize(width:width,height:1000000))
     }
     output.append(["fixture":file,"row":index,"characters":source.length,"method":method,"round":round,"ms":(ProcessInfo.processInfo.systemUptime-t)*1000,"width":size.width,"height":size.height])
    }
   }
  }
  let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]);FileHandle.standardOutput.write(data)
 }
}
