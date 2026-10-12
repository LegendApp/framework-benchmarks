import Foundation
import ChatHistoryCore
import Markdown
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var reports:[[String:Any]]=[];var texts:[[String:Any]]=[]
for (f,fixture) in (manifest["fixtures"] as! [[String:Any]]).enumerated() {
 let doc=try openChatFile(provider:.codex,path:fixture["path"] as! String)
 var counts:[String:Int]=[:]; var rows=0;var chars=0
 func walk(_ node:any Markup, quote:Bool=false,list:Bool=false) {
  let name=String(describing:type(of:node)); counts[name,default:0]+=1
  if let heading=node as? Heading { counts["headingLevel.\(heading.level)",default:0]+=1 }
  if let ordered=node as? OrderedList, ordered.startIndex != 1 { counts["orderedStartNonOne",default:0]+=1 }
  if quote && ["Strong","Emphasis","InlineCode","Link"].contains(name) { counts["quoteInline."+name,default:0]+=1 }
  if quote && ["CodeBlock","OrderedList","UnorderedList","BlockQuote","Heading","Table"].contains(name) { counts["insideQuote."+name,default:0]+=1 }
  if list && ["CodeBlock","BlockQuote","Heading","Table"].contains(name) { counts["insideList."+name,default:0]+=1 }
  for child in node.children { walk(child,quote:quote || node is BlockQuote,list:list || node is OrderedList || node is UnorderedList) }
 }
 for (i,row) in doc.rows.enumerated() where row.kind == .user || row.kind == .assistant {
  let text=row.markdown; if text.isEmpty {continue};rows+=1; chars+=text.utf8.count
  walk(Document(parsing:text));texts.append(["fixture":f,"row":i,"markdown":text])
 }
 reports.append(["fixture":f,"messageRows":rows,"markdownBytes":chars,"nodes":counts])
}
try JSONSerialization.data(withJSONObject:texts).write(to:URL(fileURLWithPath:"/tmp/md-workload-messages.json"))
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]))
