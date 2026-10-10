import AppKit

final class WrappingTextView: NSTextView {
    override func layout() {
        super.layout()
        guard let scroll = enclosingScrollView, let container = textContainer else { return }
        let width = max(1,scroll.contentSize.width - 2 * textContainerInset.width)
        container.widthTracksTextView = false
        if container.containerSize.width != width {
            container.containerSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
        }
    }
}

private final class TaskDocumentView: NSView { override var isFlipped: Bool { true } }

@MainActor final class GoalWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let session = RunSession()
    private let goal = WrappingTextView(usingTextLayoutManager:false)
    private let start = NSButton(title:"요청하기",target:nil,action:nil)
    private let stop = NSButton(title:"중지",target:nil,action:nil)
    private let status = NSTextField(wrappingLabelWithString:"요청을 기다리고 있어요")
    private let reveal = NSButton(title:"작업 기록 보기",target:nil,action:nil)
    private let response = WrappingTextView(usingTextLayoutManager:false)
    private let responseScroll = NSScrollView()
    private let responseTitle = NSTextField(labelWithString:"작업 결과")
    private let examples = NSStackView()
    private var preview: PreviewController?
    private var picker: AppPickerWindow?
    private var followUp: FollowUpWindow?
    private var connection: ConnectionWindow?
    private var currentDirectory: String?
    private let options: GUIOptions
    private var showPreview: Bool
    private var previewMenu: NSMenuItem?
    private var connectionMenu: NSMenuItem?

    init(options: GUIOptions) {
        self.options = options; showPreview = options.showPreview
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:640),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "새 작업"; window.minSize = NSSize(width:540,height:610); window.isReleasedWhenClosed = false; window.delegate = self
        NSApp.setActivationPolicy(.regular); NSApp.applicationIconImage = NSImage(systemSymbolName:"sparkles",accessibilityDescription:"작업 도우미")
        let content = window.contentView!
        let outer = NSScrollView(); outer.hasVerticalScroller = true; outer.autohidesScrollers = true; outer.drawsBackground = false; outer.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(outer)
        NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo:content.leadingAnchor),outer.trailingAnchor.constraint(equalTo:content.trailingAnchor),outer.topAnchor.constraint(equalTo:content.topAnchor),outer.bottomAnchor.constraint(equalTo:content.bottomAnchor)])
        let document = TaskDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false; outer.documentView = document
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:outer.contentView.widthAnchor),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:24),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)])
        func add(_ view:NSView, fullWidth:Bool = true) { view.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(view); if fullWidth { view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true } }
        let heading = NSTextField(labelWithString:"무엇을 도와드릴까요?"); heading.font = .systemFont(ofSize:24,weight:.semibold); add(heading)
        let subtitle = NSTextField(wrappingLabelWithString:"컴퓨터에 맡길 일을 평소 말하듯 요청하세요."); subtitle.textColor = .secondaryLabelColor; add(subtitle)
        let label = NSTextField(labelWithString:"작업 요청"); label.font = .systemFont(ofSize:13,weight:.medium); add(label)
        let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        goal.minSize = NSSize(width:0,height:200); goal.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude); goal.isRichText = false; goal.isAutomaticQuoteSubstitutionEnabled = false; goal.isAutomaticTextReplacementEnabled = false; goal.font = .systemFont(ofSize:16)
        goal.textContainerInset = NSSize(width:12,height:12); goal.isVerticallyResizable = true; goal.isHorizontallyResizable = false; goal.autoresizingMask = [.width]; goal.textContainer?.widthTracksTextView = true; goal.textContainer?.lineBreakMode = .byWordWrapping; goal.textContainer?.containerSize = NSSize(width:576,height:CGFloat.greatestFiniteMagnitude); goal.setAccessibilityLabel("작업 요청"); goal.delegate = self
        scroll.documentView = goal; add(scroll); scroll.heightAnchor.constraint(equalToConstant:210).isActive = true; goal.string = options.goal
        let hint = NSTextField(wrappingLabelWithString:"필요한 정보가 있으면 이어서 질문할게요."); hint.font = .systemFont(ofSize:12); hint.textColor = .secondaryLabelColor; add(hint)
        examples.orientation = .horizontal; examples.spacing = 8; examples.distribution = .fillEqually
        for (title,tag) in [("회의 준비 목록 작성",0),("계산기에서 계산",1)] {
            let button = NSButton(title:title,target:self,action:#selector(useExample(_:))); button.tag = tag; button.bezelStyle = .rounded; examples.addArrangedSubview(button)
        }
        add(examples); examples.heightAnchor.constraint(equalToConstant:32).isActive = true
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 8
        start.target = self; start.action = #selector(runTask); start.bezelStyle = .rounded; start.keyEquivalent = "\r"; start.keyEquivalentModifierMask = .command
        stop.target = self; stop.action = #selector(requestStop); stop.bezelStyle = .rounded; stop.isEnabled = false
        buttons.addArrangedSubview(start); buttons.addArrangedSubview(stop); add(buttons,fullWidth:false)
        status.setAccessibilityLabel("작업 상태"); status.maximumNumberOfLines = 3; status.font = .systemFont(ofSize:13); add(status); status.heightAnchor.constraint(greaterThanOrEqualToConstant:38).isActive = true
        responseTitle.font = .systemFont(ofSize:14,weight:.semibold); add(responseTitle); responseTitle.isHidden = true
        response.isEditable = false; response.isSelectable = true; response.isRichText = false; response.font = .systemFont(ofSize:14); response.textContainerInset = NSSize(width:10,height:10); response.autoresizingMask = [.width]; response.isVerticallyResizable = true; response.isHorizontallyResizable = false; response.textContainer?.widthTracksTextView = true; response.setAccessibilityLabel("작업 결과")
        responseScroll.documentView = response; responseScroll.hasVerticalScroller = true; responseScroll.borderType = .bezelBorder; add(responseScroll); responseScroll.heightAnchor.constraint(equalToConstant:160).isActive = true; responseScroll.isHidden = true
        reveal.target = self; reveal.action = #selector(showReport); reveal.bezelStyle = .rounded; reveal.isEnabled = false; add(reveal,fullWidth:false)
        session.onChange = { [weak self] in self?.refresh() }
        installMenu(); refresh(); window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); if !session.active { window?.makeFirstResponder(goal) } }
    private func installMenu() {
        let main = NSMenu(), appMenu = NSMenu(), edit = NSMenu(), windowMenu = NSMenu()
        func submenu(_ title:String,_ menu:NSMenu) { let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); item.submenu = menu; main.addItem(item) }
        let settings = NSMenuItem(title:"연결 설정…",action:#selector(showConnection),keyEquivalent:","); settings.target = self; appMenu.addItem(settings); connectionMenu = settings
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"JEV Native 종료",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        for (title,action,key) in [("실행 취소","undo:","z"),("다시 실행","redo:","Z"),("오려두기","cut:","x"),("복사","copy:","c"),("붙여넣기","paste:","v"),("모두 선택","selectAll:","a")] { edit.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key) }
        let show = NSMenuItem(title:"작업 창 보기",action:#selector(show),keyEquivalent:"1"); show.target = self; windowMenu.addItem(show)
        let previewItem = NSMenuItem(title:"작업 미리보기",action:#selector(togglePreview),keyEquivalent:""); previewItem.target = self; previewItem.state = showPreview ? .on : .off; windowMenu.addItem(previewItem); previewMenu = previewItem
        submenu("JEV Native",appMenu); submenu("편집",edit); submenu("윈도우",windowMenu); NSApp.mainMenu = main
    }
    func textDidChange(_ notification:Notification) { refreshControls() }
    private func refreshControls() {
        start.isEnabled = !session.active
        stop.isEnabled = session.active; goal.isEditable = !session.active; connectionMenu?.isEnabled = !session.active
        for view in examples.arrangedSubviews { (view as? NSControl)?.isEnabled = !session.active }
    }
    private func refresh() {
        refreshControls()
        if session.active { examples.isHidden = true }
        else {
            preview?.finish()
            if let report = session.report {
                status.stringValue = UserStatus.result(report.status); currentDirectory = report.directory
                reveal.isEnabled = FileManager.default.fileExists(atPath:report.directory + "/report.json")
                response.string = report.response ?? ""; responseTitle.isHidden = response.string.isEmpty; responseScroll.isHidden = response.string.isEmpty
                examples.isHidden = !response.string.isEmpty
            } else if session.error != nil { status.stringValue = UserStatus.result("error") }
            AppDelegate.completePendingTermination()
        }
    }
    @objc private func useExample(_ sender:NSButton) {
        guard !session.active else { return }
        goal.string = sender.tag == 0 ? "텍스트 편집기에 내일 회의 준비 목록을 써줘" : "계산기에서 12800 곱하기 3을 계산해줘"
        refreshControls(); window?.makeFirstResponder(goal)
    }
    @objc private func runTask() {
        guard !session.active else { return }
        guard !goal.string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { status.stringValue="맡길 작업을 입력해 주세요."; return }
        let original = goal.string
        guard original.utf16.count <= 6000 else { status.stringValue="요청이 길어요. 더 짧게 나누어 주세요. 입력 한도는 UTF-16 코드 단위 6,000개입니다."; return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runs/" + UUID().uuidString).path
        currentDirectory = directory; reveal.isEnabled = false; response.string = ""; responseTitle.isHidden = true; responseScroll.isHidden = true; status.stringValue = UserStatus.progress("intent")
        do {
            let runner = NaturalTaskRunner(showVirtualPointer:options.showVirtualPointer), model = options.model
            try session.start(status:{ [weak self] text in self?.status.stringValue = UserStatus.progress(text) }) { [weak self] control in
                guard let self else { throw CancellationError() }
                return try await runner.run(request:original,directory:directory,model:model,control:control,
                    followUp:{ [weak self] question in guard let self else { return nil }; return await self.ask(question) },
                    chooseApps:self.options.chooseApps,
                    selection:{ [weak self] apps in guard let self else { return nil }; return await self.chooseApps(apps) },
                    makePreview:{ [weak self] in
                        guard let self, self.showPreview else { return nil }
                        if self.preview == nil { self.preview = PreviewController() }; self.preview?.onStop = { [weak self] in self?.requestStop() }; self.preview?.beginRun(); AppDelegate.preview = self.preview; return self.preview
                    })
            }
        } catch { status.stringValue = UserStatus.result("error") }
    }
    private func ask(_ question:RequestQuestion) async -> RequestAnswer? {
        guard let window, session.control?.isCancelled == false else { return nil }
        return await withCheckedContinuation { continuation in
            let sheet = FollowUpWindow(question:question) { [weak self] answer in self?.followUp = nil; continuation.resume(returning:answer) }
            followUp = sheet; if let child = sheet.window { window.beginSheet(child) }
        }
    }
    private func chooseApps(_ apps:[AppCandidate]) async -> [String]? {
        guard let window, session.control?.isCancelled == false else { return nil }
        return await withCheckedContinuation { continuation in
            let picker = AppPickerWindow(apps:apps) { [weak self] ids in self?.picker = nil; continuation.resume(returning:ids) }
            self.picker = picker; if let sheet = picker.window { window.beginSheet(sheet) }
        }
    }
    @objc private func togglePreview() { showPreview.toggle(); previewMenu?.state = showPreview ? .on : .off; if showPreview { preview?.show() } else { preview?.hide() } }
    @objc func requestStop() { session.stop(); picker?.cancel(); followUp?.cancel() }
    func windowShouldClose(_ sender:NSWindow) -> Bool { if session.active { requestStop() }; sender.orderOut(nil); return false }
    @objc private func showReport() { if let directory = currentDirectory { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:directory + "/report.json")]) } }
    @objc private func showConnection() { guard !session.active else { return }; if connection == nil { connection = ConnectionWindow() }; connection?.show() }
}
