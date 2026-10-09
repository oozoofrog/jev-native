import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ n:String)->CFTypeRef? { var v:CFTypeRef?; AXUIElementCopyAttributeValue(e,n as CFString,&v); return v }
let dock=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.dock").first!
let root=AXUIElementCreateApplication(dock.processIdentifier)
var result:[[String:String]]=[]
func walk(_ e:AXUIElement) {
 let title=attr(e,kAXTitleAttribute) as? String ?? ""
 if title=="JevNative" {
  let url=String(describing:attr(e,kAXURLAttribute))
  let code=AXUIElementPerformAction(e,kAXPressAction as CFString)
  result.append(["title":title,"url":url,"AXPress":String(code.rawValue)])
  return
 }
 for c in attr(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] { walk(c) }
}
walk(root)
print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted]),encoding:.utf8)!)
