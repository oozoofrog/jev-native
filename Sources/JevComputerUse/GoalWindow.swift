import AppKit

@MainActor final class GoalWindowController: NSWindowController, NSWindowDelegate {
    let session = RunSession()
    private let goal = NSTextView()
    private let payload = NSTextField()
    private let mode = NSPopUpButton()
    private let start = NSButton(title:"Run",target:nil,action:nil)
    private let stop = NSButton(title:"Stop",target:nil,action:nil)
    private let previewToggle = NSButton(checkboxWithTitle:"Show Target Preview",target:nil,action:nil)
    private let generate = NSButton(checkboxWithTitle:"Generate Text with Codex",target:nil,action:nil)
    private let inspect = NSButton(checkboxWithTitle:"Inspect Image with Codex",target:nil,action:nil)
    private let status = NSTextField(wrappingLabelWithString:"Ready")
    private let reportPath = NSTextField(labelWithString:"")
    private let reveal = NSButton(title:"Show Report",target:nil,action:nil)
    private let keyStatus = NSTextField(labelWithString:"")
    private let importKey = NSButton(title:"Import Key from Clipboard",target:nil,action:nil)
    private let openKeys = NSButton(title:"Open Key Management",target:nil,action:nil)
    private var preview: PreviewController?
    private var picker: AppPickerWindow?
    private var currentDirectory: String?
    private let options: GUIOptions

    init(options: GUIOptions) {
        self.options = options
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "JEV Native — Run a Task"; window.minSize = NSSize(width:660,height:620); window.isReleasedWhenClosed = false; window.delegate = self
        NSApp.setActivationPolicy(.regular); NSApp.applicationIconImage = NSImage(systemSymbolName:"cursorarrow.rays",accessibilityDescription:"JEV Native")
        let content = NSView(frame:window.contentView!.bounds); window.contentView = content
        func label(_ text:String,_ y:CGFloat) { let field = NSTextField(labelWithString:text); field.frame = NSRect(x:20,y:y,width:620,height:22); content.addSubview(field) }
        label("Task goal",578)
        let scroll = NSScrollView(frame:NSRect(x:20,y:362,width:620,height:210)); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width,.height]
        goal.frame = scroll.contentView.bounds; goal.isRichText = false; goal.isAutomaticQuoteSubstitutionEnabled = false; goal.font = .systemFont(ofSize:14)
        goal.textContainerInset = NSSize(width:8,height:8); goal.isVerticallyResizable = true; goal.isHorizontallyResizable = false
        goal.autoresizingMask = [.width]; goal.textContainer?.widthTracksTextView = true; goal.setAccessibilityLabel("Task Goal"); scroll.documentView = goal; content.addSubview(scroll)
        goal.string = options.goal
        label("Text to type (optional literal)",331)
        payload.frame = NSRect(x:20,y:299,width:620,height:28); payload.placeholderString = ""; payload.setAccessibilityLabel("Text to Type"); content.addSubview(payload)
        mode.addItems(withTitles:["Automatic App Selection","Choose Apps from List"]); mode.frame = NSRect(x:20,y:253,width:290,height:30)
        mode.setAccessibilityLabel("App Selection Mode"); if options.chooseApps { mode.selectItem(at:1) }; content.addSubview(mode)
        previewToggle.frame = NSRect(x:330,y:254,width:310,height:26); previewToggle.state = options.showPreview ? .on : .off; previewToggle.target = self; previewToggle.action = #selector(togglePreview); content.addSubview(previewToggle)
        generate.frame = NSRect(x:20,y:218,width:290,height:26); inspect.frame = NSRect(x:330,y:218,width:310,height:26); content.addSubview(generate); content.addSubview(inspect)
        start.frame = NSRect(x:20,y:171,width:110,height:32); start.target = self; start.action = #selector(runTask); start.bezelStyle = .rounded; content.addSubview(start)
        stop.frame = NSRect(x:140,y:171,width:110,height:32); stop.target = self; stop.action = #selector(requestStop); stop.bezelStyle = .rounded; stop.isEnabled = false; content.addSubview(stop)
        status.frame = NSRect(x:20,y:120,width:620,height:45); status.setAccessibilityLabel("Run Status"); status.maximumNumberOfLines = 2; status.lineBreakMode = .byTruncatingTail; content.addSubview(status)
        reportPath.frame = NSRect(x:20,y:88,width:470,height:24); reportPath.lineBreakMode = .byTruncatingMiddle; reportPath.isSelectable = true; reportPath.setAccessibilityLabel("Report Location"); content.addSubview(reportPath)
        reveal.frame = NSRect(x:510,y:84,width:130,height:30); reveal.target = self; reveal.action = #selector(showReport); reveal.bezelStyle = .rounded; reveal.isEnabled = false; content.addSubview(reveal)
        keyStatus.frame = NSRect(x:20,y:55,width:620,height:20); keyStatus.font = .systemFont(ofSize:11); content.addSubview(keyStatus)
        importKey.frame = NSRect(x:20,y:15,width:250,height:30); importKey.target = self; importKey.action = #selector(importCredential); importKey.bezelStyle = .rounded; content.addSubview(importKey)
        openKeys.frame = NSRect(x:285,y:15,width:220,height:30); openKeys.target = self; openKeys.action = #selector(openKeyManagement); openKeys.bezelStyle = .rounded; content.addSubview(openKeys)
        session.onChange = { [weak self] in self?.refresh() }
        refreshCredential(); installMenu(); window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); if !session.active { window?.makeFirstResponder(goal) } }
    private func installMenu() {
        let main = NSMenu(), appMenu = NSMenu(), edit = NSMenu(), windowMenu = NSMenu()
        func submenu(_ title:String,_ menu:NSMenu) { let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); item.submenu = menu; main.addItem(item) }
        appMenu.addItem(withTitle:"Quit JEV Native",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        for (title,action,key) in [("Undo","undo:","z"),("Redo","redo:","Z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            edit.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        let show = NSMenuItem(title:"Show Task Window",action:#selector(show),keyEquivalent:"1"); show.target = self; windowMenu.addItem(show)
        submenu("JEV Native",appMenu); submenu("Edit",edit); submenu("Window",windowMenu); NSApp.mainMenu = main
    }
    private func refreshCredential() {
        let ready = (try? credential()) != nil
        keyStatus.stringValue = ready ? "TypeSafe API key configured" : "TypeSafe API key missing — copy the key, then use Import Key from Clipboard"
        importKey.isEnabled = !ready && !session.active; openKeys.isEnabled = !session.active
    }
    private func refresh() {
        start.isEnabled = !session.active; stop.isEnabled = session.active; goal.isEditable = !session.active
        for control in [payload,mode,previewToggle,generate,inspect] as [NSControl] { control.isEnabled = !session.active }
        refreshCredential()
        if !session.active {
            preview?.finish()
            if let report = session.report {
                let detail: String
                if report.appSelection?.status == "error", let diagnostic = report.appSelection?.diagnostic {
                    detail = " — " + String((diagnostic.components(separatedBy:" Candidates:").first ?? diagnostic).prefix(240))
                } else if report.status.hasPrefix("app_selection_"), report.appSelection?.status != "cancelled" {
                    detail = " — Choose Apps from List or revise the goal. See the report for details."
                } else if let error = report.error { detail = " — " + error }
                else { detail = "" }
                status.stringValue = "Result: " + report.status + detail
                currentDirectory = report.directory; reportPath.stringValue = report.directory + "/report.json"
                reveal.isEnabled = FileManager.default.fileExists(atPath: report.directory + "/report.json")
            } else if let error = session.error { status.stringValue = error }
            AppDelegate.completePendingTermination()
        }
    }
    @objc private func runTask() {
        guard !session.active else { return }
        do {
            var args = ["--goal",goal.string,mode.indexOfSelectedItem == 1 ? "--simple" : "--auto"]
            if !payload.stringValue.isEmpty { args += ["--text",payload.stringValue] }
            if generate.state == .on { args += ["--generate-text"] }; if inspect.state == .on { args += ["--inspect-image"] }
            let request = try RunRequest(arguments:args)
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runs/" + UUID().uuidString).path
            currentDirectory = directory; reportPath.stringValue = directory + "/report.json"; reveal.isEnabled = false
            status.stringValue = "Starting"
            let runner = TaskRunner(showVirtualPointer:options.showVirtualPointer)
            let model = options.model
            try session.start(status: { [weak self] text in self?.status.stringValue = text }) { [weak self] control in
                guard let self else { throw CancellationError() }
                return try await runner.run(request:request,directory:directory,model:model,control:control,
                    selection:{ [weak self] apps in guard let self else { return nil }; return await self.chooseApps(apps) },
                    makePreview:{ [weak self] in
                        guard let self, self.previewToggle.state == .on else { return nil }
                        if self.preview == nil { self.preview = PreviewController() }; self.preview?.onStop = { [weak self] in self?.requestStop() }; self.preview?.beginRun(); AppDelegate.preview = self.preview; return self.preview
                    })
            }
        } catch { status.stringValue = String(describing:error) }
    }
    private func chooseApps(_ apps:[AppCandidate]) async -> [String]? {
        guard let window, let control = session.control, !control.isCancelled else { return nil }
        return await withCheckedContinuation { continuation in
            let picker = AppPickerWindow(apps:apps) { [weak self] ids in self?.picker = nil; continuation.resume(returning:ids) }
            self.picker = picker
            if let sheet = picker.window { window.beginSheet(sheet) }
        }
    }
    @objc private func togglePreview() {
        if previewToggle.state == .off { preview?.hide() } else { preview?.show() }
    }
    @objc func requestStop() { session.stop(); picker?.cancel() }
    func windowShouldClose(_ sender:NSWindow) -> Bool { if session.active { requestStop() }; sender.orderOut(nil); return false }
    @objc private func showReport() { if let directory = currentDirectory { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:directory + "/report.json")]) } }
    @objc private func importCredential() {
        guard !session.active else { return }
        do { _ = try setupCredential(importPasteboard:true); status.stringValue = "API key configured. Validity will be checked on the next JEV request." }
        catch { status.stringValue = String(describing:error) }
        refreshCredential()
    }
    @objc private func openKeyManagement() {
        guard !session.active else { return }
        if !CredentialSetupIO.native().openKeys() { status.stringValue = "Could not open TypeSafe key management." }
    }
}
