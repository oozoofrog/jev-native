import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

@MainActor final class Native {
    var elements: [String: AXUIElement] = [:]
    var virtualPointer = VirtualPointer()
    var showVirtualPointer = false
    private var cursorPanel: NSPanel?
    var sessionApp: String?
    var sessionWindowID: UInt32?
    var preview: PreviewController?
    let windowEvents = WindowEvents()
    func app(_ identifier: String) -> NSRunningApplication? {
        if identifier.hasPrefix("pid:"), let pid = Int32(identifier.dropFirst(4)) { return NSRunningApplication(processIdentifier:pid) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier:identifier)
        return running.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) ?? running.first
    }
    func updateVirtualPointer(_ p: CGPoint, pid: Int32, button: String? = nil) {
        virtualPointer = VirtualPointer(x: p.x, y: p.y, buttons: button.map { [$0] } ?? [], targetPID: pid)
        preview?.pointer(p)
        guard showVirtualPointer else { return }
        if cursorPanel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true; panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hasShadow = false
            let dot = NSView(frame: NSRect(x: 0,y: 0,width: 18,height: 18)); dot.wantsLayer = true; dot.layer?.cornerRadius = 9; dot.layer?.borderWidth = 3; dot.layer?.borderColor = NSColor.systemPink.cgColor; dot.layer?.backgroundColor = NSColor.systemPink.withAlphaComponent(0.2).cgColor; panel.contentView = dot; cursorPanel = panel
        }
        // AppKit is bottom-left based; AX/CGEvent global coordinates are top-left based.
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        cursorPanel?.setFrame(NSRect(x: p.x-9,y: mainHeight-p.y-9,width: 18,height: 18), display: true); cursorPanel?.orderFrontRegardless()
    }
    func pointer() -> Rect { let p = CGEvent(source: nil)?.location ?? .zero; return Rect(x: p.x, y: p.y, width: 0, height: 0) }
    func permissions() -> [String: Bool] { ["accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess(), "inputPosting": CGPreflightPostEventAccess()] }
    func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, name as CFString, &v); return v }
    func str(_ e: AXUIElement, _ name: String) -> String { guard let v = attr(e, name) else { return "" }; return (v as? String) ?? ((v as? NSNumber)?.stringValue ?? "") }
    func frame(_ e: AXUIElement) -> Rect? {
        guard let p = attr(e, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(), let s = attr(e, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return Rect(x: point.x, y: point.y, width: size.width, height: size.height)
    }
    func windows(pid: Int32? = nil) -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { item in
            guard let owner = item[kCGWindowOwnerPID as String] as? Int32, pid == nil || pid == owner, let id = item[kCGWindowNumber as String] as? UInt32, let b = item[kCGWindowBounds as String] as? [String: Double], let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"], w > 1, h > 1, pid != nil || (item[kCGWindowLayer as String] as? Int ?? 0) == 0 else { return nil }
            return WindowInfo(id: id, pid: owner, title: item[kCGWindowName as String] as? String ?? "", frame: Rect(x:x,y:y,width:w,height:h), onScreen: item[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }
    func observe(directory: String?, images: Bool = true, limit: Int = 600) async throws -> Observation {
        let start = Date(); elements = [:]
        let front = NSWorkspace.shared.frontmostApplication
        let target = sessionApp.flatMap(app) ?? (sessionApp == nil ? front : nil)
        let appRoot = target.map { AXUIElementCreateApplication($0.processIdentifier) }
        if let appRoot { AXUIElementSetMessagingTimeout(appRoot,0.3) }
        let availableAXWindows = appRoot.flatMap { attr($0,kAXWindowsAttribute) as? [AXUIElement] } ?? []
        let knownFrames = availableAXWindows.compactMap(frame)
        let rawWindows = windows(pid: target?.processIdentifier).filter { $0.pid == target?.processIdentifier }
        // CG's complete list contains hidden AppKit accessory/internal windows. Prefer windows
        // actually exposed by AX; these are the user's documents, not cached open/save panels.
        let targetWindows = rawWindows.filter { knownFrames.isEmpty ? $0.onScreen : knownFrames.contains($0.frame) }
        let focusedFrame = appRoot.flatMap { attr($0,kAXFocusedWindowAttribute) }.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? frame($0 as! AXUIElement) : nil }
        let selected = sessionWindowID.map { wanted in targetWindows.first { $0.id == wanted } } ?? (focusedFrame.flatMap { f in targetWindows.first { $0.frame == f } } ?? targetWindows.first(where: \.onScreen) ?? targetWindows.first)
        if sessionApp != nil, sessionWindowID == nil { sessionWindowID = selected?.id }
        func info(_ app: NSRunningApplication) -> AppInfo { AppInfo(pid: app.processIdentifier, bundle: app.bundleIdentifier ?? "pid:\(app.processIdentifier)", name: app.localizedName ?? "") }
        var nodes: [Node] = []; var truncated = false; var axError: String?
        if AXIsProcessTrusted(), target != nil {
            let root = appRoot!
            AXUIElementSetMessagingTimeout(root, 0.3)
            var visited: [AXUIElement] = []
            func walk(_ e: AXUIElement, _ id: String, _ depth: Int) {
                guard nodes.count < limit, depth < 18 else { truncated = true; return }
                if visited.contains(where: { CFEqual($0, e) }) { return }; visited.append(e)
                let role = str(e, kAXRoleAttribute)
                if str(e, kAXSubroleAttribute) == "AXSecureTextField" { return }
                var names: CFArray?; AXUIElementCopyActionNames(e, &names)
                let title = [str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute), str(e, kAXHelpAttribute)].filter { !$0.isEmpty }.joined(separator: " | ")
                let value = str(e,kAXValueAttribute)
                nodes.append(Node(id: id, role: role, title: String(title.prefix(300)), value: String(value.prefix(4000)), enabled: (attr(e, kAXEnabledAttribute) as? Bool) ?? true, actions: (names as? [String]) ?? [], frame: frame(e), focused: (attr(e, kAXFocusedAttribute) as? Bool) ?? false, subrole:str(e,kAXSubroleAttribute),valueTruncated:value.count>4000,selectedText:["AXTextArea","AXTextField"].contains(role) ? str(e,kAXSelectedTextAttribute) : nil))
                elements[id] = e
                if let children = attr(e, kAXChildrenAttribute) as? [AXUIElement] { for (i, child) in children.enumerated() { walk(child, "\(id).\(i)", depth + 1) } }
            }
            // Observe only the selected window plus the application's menu bar. Other documents
            // in the same process are not exposed as mutation candidates by accident.
            let axWindows = availableAXWindows
            let selectedAX = selected.flatMap { selected in axWindows.first { frame($0) == selected.frame } }
            if let selectedAX { walk(selectedAX, "w", 0); if let menu = attr(root, kAXMenuBarAttribute), CFGetTypeID(menu) == AXUIElementGetTypeID() { walk(menu as! AXUIElement, "m", 0) } }
            else if sessionWindowID == nil || (axWindows.isEmpty && target?.bundleIdentifier == "com.apple.dock") { walk(root, "0", 0) }
            else { axError = "Selected window disappeared or AX mapping unavailable; choose an observed window explicitly" }
            if elements["m"] == nil, let menu = attr(root,kAXMenuBarAttribute), CFGetTypeID(menu) == AXUIElementGetTypeID() { walk(menu as! AXUIElement,"m",0) }
            if let extras = attr(root, "AXExtrasMenuBar"), CFGetTypeID(extras) == AXUIElementGetTypeID() { walk(extras as! AXUIElement, "x", 0) }
            if nodes.count <= 1 { axError = "AX tree unavailable/empty for foreground app (app may not expose accessibility)" }
        } else { axError = AXIsProcessTrusted() ? "Target app is not running; launch it to obtain UI state" : "Accessibility permission missing" }
        var displays: [DisplayInfo] = []; var windowCapture: WindowCapture?
        if images {
            guard CGPreflightScreenCaptureAccess() else { throw Failure("Screen Recording permission missing. Grant the invoking host/binary in System Settings > Privacy & Security > Screen & System Audio Recording, then relaunch it.") }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let selected, let window = content.windows.first(where: { $0.windowID == selected.id }) {
                let config = SCStreamConfiguration(); config.width = max(1,Int(selected.frame.width * 2)); config.height = max(1,Int(selected.frame.height * 2)); config.showsCursor = false
                let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                var path: String?
                if let directory { path = directory + "/window-\(selected.id).png"; try saveImage(img, path!) }
                let req = VNRecognizeTextRequest(); req.recognitionLevel = .fast; try? VNImageRequestHandler(cgImage: img).perform([req])
                let digest=img.dataProvider?.data.map { SHA256.hash(data:$0 as Data).map { String(format:"%02x",$0) }.joined() }
                windowCapture = WindowCapture(window: selected, screenshot: path, pixelWidth: img.width, pixelHeight: img.height, ocr: (req.results ?? []).compactMap { $0.topCandidates(1).first?.string },imageSHA256:digest)
                preview?.update(image: img, target: "\(target?.localizedName ?? "") · \(selected.title)", phase: "Observing target window", bounds: selected.frame)
                preview?.live(window:window)
            } else { preview?.update(image: nil, target: sessionApp ?? "Desktop", phase: "Waiting for a capturable window") }
            for display in content.displays {
                let bounds = CGDisplayBounds(display.displayID)
                // Explicit desktop observation captures all screens. Target sessions capture the
                // independent window only; display geometry still validates global coordinates.
                if sessionApp != nil { displays.append(DisplayInfo(id: display.displayID, frame: Rect(x:bounds.minX,y:bounds.minY,width:bounds.width,height:bounds.height), pixelWidth:display.width,pixelHeight:display.height,screenshot:nil,ocr:[])); continue }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration(); config.width = display.width; config.height = display.height; config.showsCursor = true
                let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                var path: String?
                if let directory { path = directory + "/display-\(display.displayID).png"; let url = URL(fileURLWithPath: path!); guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failure("Cannot create screenshot") }; CGImageDestinationAddImage(dest, img, nil); guard CGImageDestinationFinalize(dest) else { throw Failure("Cannot save screenshot") } }
                let req = VNRecognizeTextRequest(); req.recognitionLevel = .fast; try? VNImageRequestHandler(cgImage: img).perform([req])
                let ocr = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                displays.append(DisplayInfo(id: display.displayID, frame: Rect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height), pixelWidth: img.width, pixelHeight: img.height, screenshot: path, ocr: ocr))
            }
        }
        return Observation(id: UUID().uuidString, timestamp: Date(), front: front.map(info), apps: NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(info), nodes: nodes, displays: displays, truncated: truncated, axError: axError, elapsedMS: milliseconds(start), target: target.map(info), windows: targetWindows, selectedWindow: selected, windowCapture: windowCapture)
    }
    func saveImage(_ img: CGImage, _ path: String) throws { guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw Failure("Cannot create screenshot") }; CGImageDestinationAddImage(dest,img,nil); guard CGImageDestinationFinalize(dest) else { throw Failure("Cannot save screenshot") } }
    func check(_ code: AXError, _ operation: String) throws { guard code == .success else { throw Failure("\(operation): AXError \(code.rawValue)") } }
    func execute(_ a: Action, observation: Observation, allowedApps: [String]) async throws {
        try validateAction(a, apps: allowedApps)
        if a.kind == "wait" { try await Task.sleep(nanoseconds: UInt64(max(0, min(a.amount ?? 250, 5000))) * 1_000_000); return }
        if a.kind == "launch" || a.kind == "activate" {
            guard let app = a.app else { throw Failure("Missing app") }
            sessionApp = app; sessionWindowID = nil
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app).first { if a.kind == "activate", !running.activate(options: [.activateAllWindows]) { throw Failure("Activation failed") } }
            else { guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { throw Failure("Application not found: \(app)") }; let config = NSWorkspace.OpenConfiguration(); config.activates = a.kind == "activate"; _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config) }; return
        }
        if a.kind == "openFile" {
            guard let app = a.app, let path = a.path, FileManager.default.fileExists(atPath: path), let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { throw Failure("openFile app/path unavailable") }
            let config = NSWorkspace.OpenConfiguration(); config.activates = false
            _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
            sessionApp = app; sessionWindowID = nil; return
        }
        guard AXIsProcessTrusted() else { throw Failure("Accessibility permission missing for invoking host/binary") }
        guard let observedTarget = observation.target ?? observation.front, allowedApps.contains(observedTarget.bundle), let front = NSRunningApplication(processIdentifier: observedTarget.pid), !front.isTerminated else { throw Failure("Target app changed or outside allowlist; reobserve") }
        if a.kind == "selectWindow" {
            guard let window = observation.windows.first(where: { $0.id == a.windowID }) else { throw Failure("Window not owned by observed target") }
            sessionWindowID = a.windowID
            let root = AXUIElementCreateApplication(front.processIdentifier)
            if let win = (attr(root,kAXWindowsAttribute) as? [AXUIElement])?.first(where: { frame($0)==window.frame }) {
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(win,kAXMainAttribute as CFString,&settable) == .success, settable.boolValue { try check(AXUIElementSetAttributeValue(win,kAXMainAttribute as CFString,kCFBooleanTrue),"select main window") }
            }
            return
        }
        // Resolve again and compare the target immediately before mutation. Never trust retained AX handles alone.
        if let id = a.target {
            guard let old = observation.nodes.first(where: { $0.id == id }), let e = elements[id], str(e, kAXRoleAttribute) == old.role, frame(e) == old.frame else { throw Failure("Stale/missing AX target; reobserve") }
            let title = [str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute), str(e, kAXHelpAttribute)].filter { !$0.isEmpty }.joined(separator: " | ")
            guard String(title.prefix(300)) == old.title else { throw Failure("AX target changed title; reobserve") }
            switch a.kind {
            case "press": if let f=old.frame { updateVirtualPointer(CGPoint(x:f.x+f.width/2,y:f.y+f.height/2),pid:front.processIdentifier) }; try check(AXUIElementPerformAction(e, kAXPressAction as CFString), "press")
            case "raise": try check(AXUIElementPerformAction(e, kAXRaiseAction as CFString), "raise")
            case "focus": try check(AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue), "focus")
            case "setValue": try check(AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, (a.text ?? "") as CFString), "setValue")
            case "secondary": guard old.actions.contains(a.axAction!) else { throw Failure("Secondary action not observed on target") }; try check(AXUIElementPerformAction(e, a.axAction! as CFString), "secondary")
            case "selectText": let size = old.value.utf16.count; guard a.selectionStart! <= size, a.selectionLength! <= size-a.selectionStart! else { throw Failure("Selection exceeds observed UTF-16 value") }; var range = CFRange(location:a.selectionStart!,length:a.selectionLength!); try check(AXUIElementSetAttributeValue(e,kAXSelectedTextRangeAttribute as CFString,AXValueCreate(.cfRange,&range)!),"selectText")
            case "resize": var size = CGSize(width: a.toX!, height: a.toY!); try check(AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!), "resize")
            case "moveWindow": var point = CGPoint(x:a.x!,y:a.y!); try check(AXUIElementSetAttributeValue(e,kAXPositionAttribute as CFString,AXValueCreate(.cgPoint,&point)!),"moveWindow")
            default: throw Failure("Target not applicable to \(a.kind)")
            }; return
        }
        guard CGPreflightPostEventAccess() else { throw Failure("Input posting permission missing") }
        if ["type","key"].contains(a.kind), let selected=observation.selectedWindow {
            let root=AXUIElementCreateApplication(front.processIdentifier)
            if let focused=attr(root,kAXFocusedWindowAttribute), CFGetTypeID(focused)==AXUIElementGetTypeID(), let focusedFrame=frame(focused as! AXUIElement), focusedFrame != selected.frame { throw Failure("Target app keyboard focus belongs to another window; select/focus the intended window first") }
        }
        if a.kind == "type" {
            // Chunk at Character boundaries to preserve surrogate pairs and composed characters.
            for char in a.text ?? "" { var chars = Array(String(char).utf16); for down in [true, false] { guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { throw Failure("CGEvent creation failed") }; e.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars); e.postToPid(front.processIdentifier) } }
            return
        }
        if a.kind == "key" {
            let map: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"return":36,"l":37,"j":38,"k":40,"n":45,"m":46,"tab":48,"space":49,"delete":51,"escape":53,"left":123,"right":124,"down":125,"up":126,"home":115,"end":119,"pageup":116,"pagedown":121,"forwarddelete":117]
            guard let code = map[a.key!.lowercased()] else { throw Failure("Unsupported key: \(a.key!)") }
            var flags: CGEventFlags = []; for modifier in a.modifiers ?? [] { switch modifier { case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift); case "alt": flags.insert(.maskAlternate); case "ctrl": flags.insert(.maskControl); default: break } }
            for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; e.flags = flags; e.postToPid(front.processIdentifier) }; return
        }
        func pointAllowed(_ p: CGPoint) -> Bool { observation.displays.contains { CGRect(x: $0.frame.x,y: $0.frame.y,width: $0.frame.width,height: $0.frame.height).contains(p) } }
        func resolve(_ x: Double, _ y: Double) throws -> CGPoint {
            if a.coordinateSpace == "windowPoints" { guard let w = observation.selectedWindow else { throw Failure("No selected window") }; return CGPoint(x:w.frame.x+x,y:w.frame.y+y) }
            if a.coordinateSpace == "screenshotPixels" { guard let c = observation.windowCapture else { throw Failure("No window screenshot mapping") }; return CGPoint(x:c.window.frame.x+x/Double(c.pixelWidth)*c.window.frame.width,y:c.window.frame.y+y/Double(c.pixelHeight)*c.window.frame.height) }
            return CGPoint(x:x,y:y)
        }
        let center = observation.selectedWindow.map { CGPoint(x:$0.frame.x+$0.frame.width/2,y:$0.frame.y+$0.frame.height/2) } ?? .zero
        let p = a.x != nil && a.y != nil ? try resolve(a.x!,a.y!) : (virtualPointer.targetPID == front.processIdentifier ? CGPoint(x:virtualPointer.x,y:virtualPointer.y) : center)
        guard pointAllowed(p) else { throw Failure("Point outside observed displays") }
        guard observation.selectedWindow != nil else { throw Failure("Coordinate input requires a selected target window; use AX actions or select an observed window") }
        guard windowEvents.available else { throw Failure("Apple window-local event annotation unavailable; coordinate input cannot be verified on this OS. Use AX actions; no global cursor fallback exists.") }
        // App-directed events bypass the global HID event stream and do not move the user's pointer.
        // Never save/restore the cursor: that would overwrite concurrent user movement.
        func mouse(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left, _ count: Int64 = 1) {
            updateVirtualPointer(p, pid: front.processIdentifier, button: [.leftMouseDown, .leftMouseDragged].contains(type) ? "left" : (type == .rightMouseDown ? "right" : nil))
            let cocoaTypes: [CGEventType: NSEvent.EventType] = [.leftMouseDown:.leftMouseDown,.leftMouseUp:.leftMouseUp,.rightMouseDown:.rightMouseDown,.rightMouseUp:.rightMouseUp,.mouseMoved:.mouseMoved,.leftMouseDragged:.leftMouseDragged]
            let local = observation.selectedWindow.map { NSPoint(x: p.x-$0.frame.x,y: $0.frame.height-(p.y-$0.frame.y)) } ?? p
            let cocoa = NSEvent.mouseEvent(with: cocoaTypes[type]!, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(observation.selectedWindow?.id ?? 0), context: nil, eventNumber: 0, clickCount: Int(count), pressure: [.leftMouseDown,.rightMouseDown,.leftMouseDragged].contains(type) ? 1 : 0)
            let e = cocoa?.cgEvent ?? CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
            e.location = p
            if let window = observation.selectedWindow { windowEvents.annotate(e, local: CGPoint(x:p.x-window.frame.x,y:p.y-window.frame.y),windowID:window.id) }
            e.setIntegerValueField(.eventSourceUserData,value:731731)
            e.setIntegerValueField(.mouseEventClickState, value: count)
            if let window = observation.selectedWindow { e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id)); e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.id)) }
            e.postToPid(front.processIdentifier)
        }
        switch a.kind {
        case "scroll":
            mouse(.mouseMoved,p)
            let e=CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:2,wheel1:Int32(clamping:a.amount ?? -3),wheel2:Int32(clamping:a.horizontalAmount ?? 0),wheel3:0)!
            e.location=p
            if let window=observation.selectedWindow { windowEvents.annotate(e,local:CGPoint(x:p.x-window.frame.x,y:p.y-window.frame.y),windowID:window.id); e.setIntegerValueField(.mouseEventWindowUnderMousePointer,value:Int64(window.id)); e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,value:Int64(window.id)) }
            e.setIntegerValueField(.eventSourceUserData,value:731731)
            e.postToPid(front.processIdentifier)
        case "move": mouse(.mouseMoved, p)
        case "click", "doubleClick", "rightClick": mouse(.mouseMoved,p); let right = a.kind == "rightClick"; for count in 1...(a.kind == "doubleClick" ? 2 : 1) { mouse(right ? .rightMouseDown : .leftMouseDown, p, right ? .right : .left, Int64(count)); mouse(right ? .rightMouseUp : .leftMouseUp, p, right ? .right : .left, Int64(count)) }
        case "drag": let dest = try resolve(a.toX!, a.toY!); guard pointAllowed(dest) else { throw Failure("Drag destination outside displays") }; mouse(.mouseMoved,p); mouse(.leftMouseDown, p); for i in 1...12 { let t = Double(i)/12; mouse(.leftMouseDragged, CGPoint(x: p.x+(dest.x-p.x)*t,y:p.y+(dest.y-p.y)*t)); try await Task.sleep(nanoseconds: 16_000_000) }; mouse(.leftMouseUp, dest)
        default: throw Failure("Unsupported input action")
        }
    }
}
