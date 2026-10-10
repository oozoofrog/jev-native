import AppKit

@MainActor final class QueryFixture: NSObject {
    let window: NSWindow
    let status=NSTextField(labelWithString:"result=idle")
    let logPath: String
    var sheet: NSWindow?
    var timer: Timer?
    init(window:NSWindow,scenario:String,logPath:String) {
        self.window=window;self.logPath=logPath;super.init()
        let content=NSView(frame:NSRect(x:0,y:0,width:640,height:440))
        status.frame=NSRect(x:20,y:400,width:590,height:24);status.setAccessibilityLabel("Fixture result");content.addSubview(status)
        window.setContentSize(NSSize(width:640,height:440));window.contentView=content
        func button(_ title:String,_ id:String,_ frame:NSRect,_ parent:NSView) -> NSButton {
            let b=NSButton(title:title,target:self,action:#selector(press(_:)));b.identifier=NSUserInterfaceItemIdentifier(id);b.frame=frame;parent.addSubview(b);return b
        }
        if scenario == "changing" {
            timer=Timer.scheduledTimer(withTimeInterval:0.7,repeats:true) { [weak self] _ in
                guard let self else { return }; self.status.stringValue="result=changed";self.status.setAccessibilityValue(self.status.stringValue);NSAccessibility.post(element:self.status,notification:.valueChanged)
            }
        } else if scenario == "large" {
            let scroll=NSScrollView(frame:NSRect(x:20,y:20,width:600,height:365));scroll.hasVerticalScroller=true
            let document=NSView(frame:NSRect(x:0,y:0,width:570,height:24*720));document.setAccessibilityElement(true);document.setAccessibilityRole(.group);document.setAccessibilityLabel("All 720 exposed rows")
            var groups:[NSView]=[]
            for groupIndex in 0..<8 {
                let start=groupIndex*100,end=min(719,start+99)
                let group=NSView(frame:NSRect(x:0,y:start*24,width:570,height:(end-start+1)*24));group.setAccessibilityElement(true);group.setAccessibilityRole(.group);group.setAccessibilityLabel("Rows \(start) through \(end)")
                var buttons:[NSButton]=[]
                for index in start...end { buttons.append(button("Row \(index)","row-\(index)",NSRect(x:10,y:(index-start)*24,width:230,height:23),group)) }
                group.setAccessibilityChildren(buttons);document.addSubview(group);groups.append(group)
            }
            document.setAccessibilityChildren(groups);scroll.documentView=document;content.addSubview(scroll)
        } else if scenario == "long" {
            let scroll=NSScrollView(frame:NSRect(x:20,y:65,width:600,height:320));scroll.hasVerticalScroller=true
            let text=NSTextView(frame:NSRect(x:0,y:0,width:575,height:10000));text.isEditable=false
            text.string=String(repeating:"Owned text line: 😀 한글 UTF16.\n",count:2000)+"END-MARKER-731"
            text.setAccessibilityLabel("Owned long text");scroll.documentView=text;content.addSubview(scroll)
            _=button("Confirm document","confirm",NSRect(x:20,y:20,width:200,height:32),content)
        } else if scenario == "duplicates" {
            for (index,title) in ["Left controls","Right controls"].enumerated() {
                let group=NSView(frame:NSRect(x:20+index*290,y:80,width:270,height:220));group.setAccessibilityElement(true);group.setAccessibilityRole(.group);group.setAccessibilityLabel(title)
                let b=button("Apply",index==0 ? "left" : "right",NSRect(x:20,y:80,width:220,height:35),group);group.setAccessibilityChildren([b]);content.addSubview(group)
            }
        } else if scenario == "dialog" { _=button("Open details","open-dialog",NSRect(x:20,y:80,width:220,height:35),content) }
        else { _=button("Confirm small task","small",NSRect(x:20,y:80,width:220,height:35),content) }
        window.title="JEV Owned AX Fixture · \(scenario)";window.orderFrontRegardless()
    }
    @objc func press(_ sender:NSButton) {
        let id=sender.identifier?.rawValue ?? "unknown"
        if id == "open-dialog" {
            let dialog=NSWindow(contentRect:NSRect(x:0,y:0,width:350,height:150),styleMask:[.titled],backing:.buffered,defer:false);dialog.title="Owned details"
            let button=NSButton(title:"Confirm details",target:self,action:#selector(press(_:)));button.identifier=NSUserInterfaceItemIdentifier("confirmed-dialog");button.frame=NSRect(x:30,y:45,width:260,height:35);dialog.contentView?.addSubview(button);sheet=dialog;window.beginSheet(dialog);return
        }
        status.stringValue="result=\(id)";status.setAccessibilityValue(status.stringValue)
        if let sheet { window.endSheet(sheet);self.sheet=nil }
        let data=try! JSONSerialization.data(withJSONObject:["result":id,"source":"native NSButton action","time":Date().timeIntervalSince1970])
        if !FileManager.default.fileExists(atPath:logPath) { FileManager.default.createFile(atPath:logPath,contents:nil) }
        if let h=FileHandle(forWritingAtPath:logPath) { h.seekToEndOfFile();h.write(data);h.write(Data([10]));try? h.close() }
    }
}
