import AppKit

final class WrappingTextView: NSTextView {
    var onSubmit:(() -> Void)?
    override func keyDown(with event:NSEvent) {
        if let onSubmit, isEditable, (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) { insertNewline(nil) } else { onSubmit() }; return
        }
        super.keyDown(with:event)
    }
    var placeholder = "예: 열린 문서의 핵심을 정리해 줘. 필요한 출처도 함께 보여 줘."
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && isEditable { placeholder.draw(in:NSRect(x:textContainerInset.width+4,y:textContainerInset.height,width:max(0,bounds.width-32),height:54),withAttributes:[.font:font ?? NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.placeholderTextColor]) }
    }
    override func didChangeText() { super.didChangeText(); needsDisplay = true }
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

@MainActor final class GoalWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let session = RunSession()
    private let goal = WrappingTextView(usingTextLayoutManager:false)
    private let workspace = TopologyWorkspace(frame:.zero)
    private let conversation = ConversationView(frame:.zero)
    private let setup = SetupCoordinator()
    private let setupAction = NSButton(title:"",target:nil,action:nil)
    private let setupLine = NSTextField(wrappingLabelWithString:"")
    private let metrics = NSTextField(labelWithString:"")
    private var setupBanner:NSStackView?
    private var bannerHeight:NSLayoutConstraint?
    private let questionHost = ConversationView(frame:.zero)
    private var questionHeight:NSLayoutConstraint?
    private var examplesMenu:NSPopUpButton?
    private var dialog:NSWindow?
    private var currentPlan:ResearchPlan?
    private var detailWindow:NSWindow?
    private let status = NSTextField(wrappingLabelWithString:"준비 상태를 확인하고 있어요")
    private let run = SendRequestButton(title:"",target:nil,action:nil)
    private let pause = NSButton(title:"일시정지",target:nil,action:nil)
    private let stop = NSButton(title:"중지",target:nil,action:nil)
    private var setupCard:ConversationCard?
    private var examplesCard:ConversationCard?
    private var setupRows:NSTextField?
    private var setupMessage:NSTextField?
    private var presentation = RunPresentationState()
    private var preview:PreviewController?
    private var picker:AppPickerWindow?
    private var connection:ConnectionWindow?
    private var currentDirectory:String?
    private var cancelPending:(() -> Void)?
    private var finalShown = true
    private var activationObserver:NSObjectProtocol?
    private let options:GUIOptions
    private var showPreview:Bool
    private var previewMenu:NSMenuItem?
    private var connectionMenu:NSMenuItem?

    init(options:GUIOptions) {
        self.options = options; showPreview = options.showPreview
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:920),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:window); window.title = "JEV · 작업실 · \(CompiledProduct.version) (\(CompiledProduct.build))"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.minSize = NSSize(width:760,height:760); window.isReleasedWhenClosed = false; window.delegate = self
        NSApp.setActivationPolicy(.regular)
        if let icon = Bundle.main.url(forResource:"JevNative",withExtension:"icns").flatMap({NSImage(contentsOf:$0)}) { NSApp.applicationIconImage = icon }
        let content = window.contentView!
        workspace.useDetailedDashboard()
        let header = NSStackView(); header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 14
        let brand = NSTextField(labelWithString:"JEV"); brand.font = .systemFont(ofSize:23,weight:.bold)
        let title = NSTextField(labelWithString:"작업실"); title.font = .systemFont(ofSize:16,weight:.medium); title.textColor = .secondaryLabelColor
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        status.font = .systemFont(ofSize:13,weight:.medium); status.setAccessibilityLabel("현재 단계와 다음 단계")
        let details = ConversationButton("기록") { [weak self] in self?.showTaskHistory() }; details.toolTip = "작업별 요약에서 실제 단계·검색·출처·오류 근거 확인"
        let context = ConversationButton("설정") { [weak self] in self?.showSetupDetails() }
        for view in [brand,title,spacer,status,details,context] { header.addArrangedSubview(view) }
        status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let scroll = NSScrollView(); scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        goal.minSize = NSSize(width:0,height:62); goal.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        goal.isRichText = false; goal.isAutomaticQuoteSubstitutionEnabled = false; goal.isAutomaticTextReplacementEnabled = false; goal.font = .systemFont(ofSize:16)
        goal.textContainerInset = NSSize(width:4,height:8); goal.drawsBackground = false; goal.isVerticallyResizable = true; goal.isHorizontallyResizable = false; goal.autoresizingMask = [.width]
        goal.textContainer?.widthTracksTextView = true; goal.textContainer?.lineBreakMode = .byWordWrapping; goal.setAccessibilityLabel("작업 요청"); goal.delegate = self; goal.string = options.goal; scroll.documentView = goal
        let composer = WorkspaceSurface(); composer.translatesAutoresizingMaskIntoConstraints = false
        let prompt = NSTextField(labelWithString:"무엇을 도와드릴까요?"); prompt.font = .systemFont(ofSize:13,weight:.semibold)
        let hint = NSTextField(labelWithString:"Enter 전송 · Shift+Enter 줄바꿈"); hint.font = .systemFont(ofSize:11); hint.textColor = .tertiaryLabelColor
        goal.onSubmit = { [weak self] in self?.runTask() }
        run.target = self; run.action = #selector(runTask); run.bezelStyle = .rounded; run.controlSize = .large; run.bezelColor = .labelColor; run.image = NSImage(systemSymbolName:"arrow.up",accessibilityDescription:"요청 전송"); run.title = ""; run.setAccessibilityLabel("요청 전송"); run.toolTip = "Enter로 요청 전송"; run.isBordered = false; run.widthAnchor.constraint(equalToConstant:34).isActive = true; run.heightAnchor.constraint(equalToConstant:34).isActive = true
        pause.target = self; pause.action = #selector(togglePause); pause.bezelStyle = .rounded
        stop.target = self; stop.action = #selector(requestStop); stop.bezelStyle = .rounded
        let examples = NSPopUpButton(); examples.addItems(withTitles:["예시로 시작", "웹 정보 비교", "열린 문서 요약", "글 작성"]); examples.target = self; examples.action = #selector(selectExample); examplesMenu = examples
        examples.controlSize = .small; examples.setAccessibilityLabel("작업 예시")
        let composerHeader = NSStackView(views:[prompt,NSView(),examples]); composerHeader.orientation = .horizontal; composerHeader.alignment = .centerY
        composerHeader.views[1].setContentHuggingPriority(.defaultLow,for:.horizontal)
        let actions = NSStackView(views:[hint,NSView(),pause,stop,run]); actions.orientation = .horizontal; actions.spacing = 10; actions.alignment = .centerY
        actions.views[1].setContentHuggingPriority(.defaultLow,for:.horizontal)
        for view in [composerHeader,scroll,actions] { view.translatesAutoresizingMaskIntoConstraints = false; composer.addSubview(view) }
        NSLayoutConstraint.activate([
            composerHeader.leadingAnchor.constraint(equalTo:composer.leadingAnchor,constant:18),composerHeader.trailingAnchor.constraint(equalTo:composer.trailingAnchor,constant:-18),composerHeader.topAnchor.constraint(equalTo:composer.topAnchor,constant:12),composerHeader.heightAnchor.constraint(equalToConstant:24),
            scroll.leadingAnchor.constraint(equalTo:composer.leadingAnchor,constant:14),scroll.trailingAnchor.constraint(equalTo:composer.trailingAnchor,constant:-14),scroll.topAnchor.constraint(equalTo:composerHeader.bottomAnchor,constant:3),scroll.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-4),
            actions.leadingAnchor.constraint(equalTo:composer.leadingAnchor,constant:18),actions.trailingAnchor.constraint(equalTo:composer.trailingAnchor,constant:-14),actions.bottomAnchor.constraint(equalTo:composer.bottomAnchor,constant:-10),actions.heightAnchor.constraint(equalToConstant:32)])
        let banner = NSStackView(); banner.orientation = .horizontal; banner.alignment = .centerY; banner.spacing = 12
        setupLine.font = .systemFont(ofSize:13); setupLine.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        setupAction.bezelStyle = .rounded; setupAction.target = self; setupAction.action = #selector(performSetupAction)
        banner.addArrangedSubview(setupLine); banner.addArrangedSubview(setupAction); setupBanner = banner
        metrics.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium); metrics.textColor = .secondaryLabelColor; metrics.stringValue = "출처 · 계획 · 진행 · 결과 · 기록"
        for view in [header,banner,metrics,workspace,questionHost,composer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        bannerHeight = banner.heightAnchor.constraint(equalToConstant:28); questionHeight = questionHost.heightAnchor.constraint(equalToConstant:0); questionHost.isHidden = true
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),header.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),header.topAnchor.constraint(equalTo:content.safeAreaLayoutGuide.topAnchor,constant:8),header.heightAnchor.constraint(equalToConstant:40),
            banner.leadingAnchor.constraint(equalTo:header.leadingAnchor),banner.trailingAnchor.constraint(equalTo:header.trailingAnchor),banner.topAnchor.constraint(equalTo:header.bottomAnchor,constant:2),bannerHeight!,
            metrics.leadingAnchor.constraint(equalTo:header.leadingAnchor),metrics.trailingAnchor.constraint(equalTo:header.trailingAnchor),metrics.topAnchor.constraint(equalTo:banner.bottomAnchor,constant:2),metrics.heightAnchor.constraint(equalToConstant:20),
            workspace.leadingAnchor.constraint(equalTo:content.leadingAnchor),workspace.trailingAnchor.constraint(equalTo:content.trailingAnchor),workspace.topAnchor.constraint(equalTo:metrics.bottomAnchor,constant:4),workspace.bottomAnchor.constraint(equalTo:questionHost.topAnchor,constant:-4),
            questionHost.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:8),questionHost.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-8),questionHost.bottomAnchor.constraint(equalTo:composer.topAnchor,constant:-6),questionHeight!,
            composer.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:22),composer.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-22),composer.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-16),composer.heightAnchor.constraint(equalToConstant:156)])
        workspace.onCommand = { [weak self] command in guard let self else { return }; switch command { case "run":self.runTask(); case "pause":self.togglePause(); case "stop":self.requestStop(); case "report":self.showReport(); default:break } }
        session.onChange = { [weak self] in self?.refresh() }; setup.onChange = { [weak self] in self?.renderSetup() }
        workspace.onDetails = { [weak self] kind in
            guard kind == "source", let self, let plan = self.currentPlan else { return false }
            self.showSourceDetails(plan); return true
        }
        installMenu(); refresh(); window.center()
        activationObserver = NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { if self?.session.active == false { self?.setup.check() } } }
        setup.check()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc func show() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); if !session.active { window?.makeFirstResponder(goal) } }
    private func installMenu() {
        let main = NSMenu(), appMenu = NSMenu(), edit = NSMenu(), taskMenu = NSMenu(), windowMenu = NSMenu()
        func submenu(_ title:String,_ menu:NSMenu) { let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); item.submenu = menu; main.addItem(item) }
        let settings = NSMenuItem(title:"연결 설정…",action:#selector(showConnection),keyEquivalent:","); settings.target = self; appMenu.addItem(settings); connectionMenu = settings
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"JEV Native 종료",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        for (title,action,key) in [("실행 취소","undo:","z"),("다시 실행","redo:","Z"),("오려두기","cut:","x"),("복사","copy:","c"),("붙여넣기","paste:","v"),("모두 선택","selectAll:","a")] { edit.addItem(withTitle:title,action:NSSelectorFromString(action),keyEquivalent:key) }
        let show = NSMenuItem(title:"작업 창 보기",action:#selector(show),keyEquivalent:"1"); show.target = self; windowMenu.addItem(show)
        let previewItem = NSMenuItem(title:"작업 미리보기",action:#selector(togglePreview),keyEquivalent:""); previewItem.target = self; previewItem.state = showPreview ? .on : .off; windowMenu.addItem(previewItem); previewMenu = previewItem
        for (title,action,key) in [("요청하기",#selector(runTask),"\r"),("일시정지 / 계속하기",#selector(togglePause),"p"),("중지",#selector(requestStop),"."),("작업 기록 보기",#selector(showReport),"r")] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:key); item.target = self; taskMenu.addItem(item)
        }
        submenu("JEV Native",appMenu); submenu("작업",taskMenu); submenu("편집",edit); submenu("윈도우",windowMenu); NSApp.mainMenu = main
    }
    @objc private func selectExample(_ sender:NSPopUpButton) {
        let texts = ["", "서울의 이번 달 무료 전시 정보를 공식 출처로 조사하고 날짜·장소·출처를 비교해 주세요.", "열린 TextEdit 문서를 읽고 핵심을 작업 창에 요약해 주세요.", "팀에 공유할 짧은 프로젝트 소개문을 작성해서 작업 창에 보여 주세요."]
        if texts.indices.contains(sender.indexOfSelectedItem), sender.indexOfSelectedItem > 0 { example(texts[sender.indexOfSelectedItem]) }; sender.selectItem(at:0)
    }
    private func renderSetup() {
        let state = setup.state
        setupRows?.stringValue = state.rows.filter { !$0.contains("캘린더") }.joined(separator:"\n"); setupMessage?.stringValue = state.detail+(state.failure.map { "\n"+$0 } ?? "")
        setupBanner?.isHidden = state.ready; bannerHeight?.constant = state.ready ? 0 : 28
        setupAction.isHidden = state.ready || state.checking
        setupLine.stringValue = state.checking ? "준비 상태 자동 점검 중" : state.ready ? "준비 완료 · 요청 범위에서 자동으로 실행합니다" : nextSetup().0
        setupAction.title = nextSetup().1
        if !session.active { status.stringValue = state.canPlan ? "요청 대기" : "초기 설정" }; refreshControls()
    }
    private func nextSetup() -> (String,String) {
        let state = setup.state
        if state.permissions["accessibility"] != true || state.permissions["screenRecording"] != true || state.permissions["inputPosting"] != true { return ("앱의 화면과 버튼을 확인하고 입력하려면 macOS 권한이 필요합니다.","권한 승인") }
        if !state.codexInstalled { return (state.failure ?? "Codex 실행 도구를 자동으로 준비합니다.","다시 점검") }
        if !state.codexAuthenticated { return ("원문 해석과 결과 작성에 사용할 Codex에 로그인해 주세요.","Codex 로그인") }
        if !state.keyConfigured { return ("다음 동작을 선택할 TypeSafe 연결 키를 설정해 주세요.","연결 설정") }
        if !state.keyVerified { return (state.failure ?? "TypeSafe 연결을 확인해야 합니다.","연결 점검") }
        return ("준비됐어요.","다시 점검")
    }
    @objc private func performSetupAction() {
        guard !session.active else { return }; let state = setup.state
        if state.permissions["accessibility"] != true || state.permissions["screenRecording"] != true || state.permissions["inputPosting"] != true { setup.requestPermissions() }
        else if !state.codexInstalled { setup.check() }
        else if !state.codexAuthenticated { setup.signIn() }
        else if !state.keyConfigured { showConnection() }
        else { setup.check(forceConnection:true) }
    }
    private func showSetupDetails() {
        guard !session.active else { return }
        let card = ConversationCard(title:"준비 상태",body:"각 항목을 실제로 점검합니다. 연결 키가 있다는 사실과 서버 연결 성공은 구분합니다.")
        setupRows = card.label(setup.state.rows.filter { !$0.contains("캘린더") }.joined(separator:"\n")); setupMessage = card.label(setup.state.detail)
        card.button("다시 점검") { [weak self] in self?.setup.check(forceConnection:true) }
        if !setup.state.ready { card.button(nextSetup().1) { [weak self] in self?.performSetupAction() } }
        card.button("연결 설정") { [weak self] in self?.showConnection() }
        showDetailCard(card,title:"설정")
    }
    private func showDetailCard(_ card:ConversationCard,title:String) {
        let view = ConversationView(frame:.zero); view.append(card); openDetails(view,title:title)
    }
    private func openDetails(_ view:ConversationView,title:String) {
        detailWindow?.close()
        let panel = NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:640),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false); panel.title = title; panel.isReleasedWhenClosed = false
        panel.contentView = view; detailWindow = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    private func showTranscript() {
        let data = conversation
        if let parent = data.superview { data.removeFromSuperview(); _ = parent }
        openDetails(data,title:"작업 상세 · 결과와 실행 기록")
    }
    private func showSourceDetails(_ plan:ResearchPlan) {
        let view = ConversationView(frame:.zero)
        for source in plan.sources {
            let card = ConversationCard(title:"[\(source.id)] \(source.title)",body:"\(source.url)\n수집: \(source.fetchedAt.formatted())\nSHA-256: \(source.sha256)\n\n\(source.text)")
            card.button("출처 열기") { if let url = try? ResearchValidation.publicURL(source.url) { NSWorkspace.shared.open(url) } }; view.append(card)
        }; openDetails(view,title:"조사 출처 · 원문과 수집 근거")
    }
    private func presentQuestion(_ card:ConversationCard,title:String) {
        endQuestion(); questionHost.isHidden = false; questionHost.append(card); questionHeight?.constant = 206
        status.stringValue = title
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    private func endQuestion() {
        for card in questionHost.cards.arrangedSubviews { questionHost.cards.removeArrangedSubview(card); card.removeFromSuperview() }
        questionHeight?.constant = 0; questionHost.isHidden = true
    }
    private func example(_ text:String) { guard !session.active else { return }; goal.string = text; window?.makeFirstResponder(goal); refreshControls() }
    func textDidChange(_ notification:Notification) { refreshControls() }
    private func refreshControls() {
        goal.isEditable = !session.active; goal.needsDisplay = true; examplesMenu?.isEnabled = !session.active && setup.state.canPlan; run.isEnabled = !session.active && setup.state.canPlan && !goal.string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        setupCard?.setControlsEnabled(!session.active); examplesCard?.isHidden = !setup.state.canPlan
        connectionMenu?.isEnabled = !session.active; pause.isEnabled = session.active; stop.isEnabled = session.active
        pause.isHidden = !session.active; stop.isHidden = !session.active
        pause.title = session.control?.pauseRequested == true ? "계속하기" : "일시정지"
        workspace.execution(active:session.active,pauseRequested:session.control?.pauseRequested ?? false,paused:session.control?.isPaused ?? false)
    }
    private func refresh() {
        refreshControls()
        if !session.active {
            preview?.finish(); AppDelegate.completePendingTermination()
            if !finalShown {
                finalShown = true
                let report = session.report
                let card = ConversationCard(title:UserStatus.result(report?.status ?? (session.error == nil ? "cancelled" : "error")),body:report?.response ?? session.error ?? "작업 기록에서 이미 실행한 동작을 확인해 주세요.")
                card.button("작업 기록 확인") { [weak self] in self?.showReport() }; conversation.append(card)
            }
        }
    }
    private func receive(_ event:RunPresentationEvent) {
        presentation.apply(event); workspace.update(presentation); status.stringValue = presentation.phase
        let sources = presentation.research?.sources.map { "출처 \($0)개" } ?? (presentation.localCommands > 0 ? "로컬 명령" : (presentation.source.isEmpty ? "출처 대기" : "원문 확인"))
        metrics.stringValue = sources+"   ·   앱 입력 \(presentation.inputs)회"+(presentation.localCommands > 0 ? "   ·   CLI \(presentation.localCommands)회" : "")+"   ·   기록 \(presentation.history.count)개"
        if case .input(let text) = event.fact { conversation.append(ConversationCard(title:"확인한 실행",body:text)) }
    }
    @objc private func togglePause() { guard let control = session.control else { return }; if control.pauseRequested { control.resume() } else { control.requestPause() } }
    @objc private func runTask() {
        guard !session.active, setup.state.canPlan else { return }
        let original = goal.string.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        guard original.utf16.count <= 6000 else { status.stringValue = "요청을 6,000 UTF-16 코드 단위 이내로 입력해 주세요."; return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runs/"+UUID().uuidString).path
        currentDirectory = directory; workspace.runDirectory=directory; currentPlan = nil; metrics.stringValue = "요청 확인 중"; finalShown = false; conversation.append(ConversationCard(title:"내 요청",body:original))
        do {
            try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try session.start(status:{ _ in },presentation:{ [weak self] in self?.receive($0) },request:original,directory:directory) { [weak self] control in
                guard let self else { throw CancellationError() }
                do {
                    try await control.checkpoint()
                    let researcher = ResearchRunner(); control.status("요청할 작업 경로를 확인하고 있어요 · 다음: 조사·CLI·앱 작업")
                    try await control.checkpoint()
                    let route = try await researcher.route(original,directory:directory)
                    try await control.checkpoint()
                    guard route != "ask" else { throw Failure("요청에서 실행 경로를 확정하지 못했습니다. 실행한 앱 작업은 없습니다. 상세 근거는 작업 기록에 보존했습니다.") }
                    guard route != "calendar" else { throw Failure("캘린더 등록은 현재 작업 화면의 지원 범위에서 제외했습니다. 실행한 앱 작업은 없습니다.") }
                    if route == "research" {
                        control.emit(.plan("공개 웹 출처 수집\n원문 확인·정보 비교\n출처를 포함해 결과 작성"))
                        return try await self.research(original,directory:directory,runner:researcher,control:control)
                    }
                    if route == "local" {
                        let workspace = try self.options.workingDirectory.map { try LocalWorkspace.select(request:"",defaultDirectory:$0) } ?? LocalWorkspace.select(request:original,defaultDirectory:self.options.baseWorkingDirectory(fallback:FileManager.default.currentDirectoryPath))
                        return try await LocalTaskRunner().run(request:original,workspace:workspace,directory:directory,model:self.options.model,control:control,native:{ [weak self] request,dir,control in
                            guard let self else { throw CancellationError() }
                            guard self.setup.state.ready else { throw Failure("이 단계에는 네이티브 앱 접근 권한이 필요합니다. 실행한 CLI 결과는 작업 기록에 보존했습니다.") }
                            return try await NaturalTaskRunner(showVirtualPointer:self.options.showVirtualPointer).run(request:request,directory:dir,model:self.options.model,control:control,followUp:nil,chooseApps:false,selection:nil,makePreview:{ [weak self] in self?.beginPreview() })
                        })
                    }
                    guard self.setup.state.ready else { throw Failure("네이티브 앱 작업에는 접근성·화면 기록·입력 권한이 필요합니다. 설정에서 해당 권한을 승인해 주세요.") }
                    control.emit(.plan("필요한 대상 앱 자동 선택\n원문 확인·요청 해석\n요청 범위에서 앱 작업 실행"))
                    try await control.checkpoint()
                    return try await NaturalTaskRunner(showVirtualPointer:self.options.showVirtualPointer).run(request:original,directory:directory,model:self.options.model,control:control,
                        followUp:nil,chooseApps:false,selection:nil,makePreview:{ [weak self] in self?.beginPreview() })
                } catch {
                    if error is CancellationError { control.stop() }
                    let report = RunReport(status:control.isCancelled || error is CancellationError ? "cancelled" : "error",goal:original,steps:[],finalObservation:"",directory:directory,error:String(describing:error))
                    try? writeJSON(report,directory+"/report.json"); throw error
                }
            }
        } catch { conversation.append(ConversationCard(title:"작업을 시작하지 못했어요",body:String(describing:error))); finalShown = true }
    }
    private func research(_ original:String,directory:String,runner:ResearchRunner,control:RunControl) async throws -> RunReport {
        let plan = try await runner.prepare(request:original,calendar:false,directory:directory,model:options.model,control:control)
        try await control.checkpoint()
        currentPlan = plan
        let limits = plan.questions.isEmpty ? "" : "\n\n확인하지 못한 항목\n"+plan.questions.joined(separator:"\n")
        let response = plan.summary+limits+"\n\n"+plan.sources.map { "[\($0.id)] \($0.url)" }.joined(separator:"\n")
        control.emit(.target("웹 조사")); control.emit(.result(response))
        let report = RunReport(status:plan.questions.isEmpty ? "content_delivered" : "research_partial",goal:original,steps:[],finalObservation:directory+"/sources.json",directory:directory,completionSource:"public_sources_codex",response:response)
        try writeJSON(report,directory+"/report.json"); return report
    }
    private func beginPreview() -> PreviewController? {
        guard showPreview else { return nil }; if preview == nil { preview = PreviewController() }; preview?.onStop = { [weak self] in self?.requestStop() }; preview?.beginRun(); AppDelegate.preview = preview; return preview
    }
    @objc private func togglePreview() { showPreview.toggle(); previewMenu?.state = showPreview ? .on : .off; if showPreview { preview?.show() } else { preview?.hide() } }
    func prepareToTerminate() { setup.cancel(); detailWindow?.close() }
    @objc func requestStop() { session.stop(); picker?.cancel(); cancelPending?() }
    func windowShouldClose(_ sender:NSWindow) -> Bool { if session.active { requestStop() }; sender.orderOut(nil); return false }
    @objc private func showReport() { if !presentation.request.isEmpty { workspace.showTaskDetails() } else { showTaskHistory() } }
    private func showTaskHistory() {
        let view=ConversationView(frame:.zero)
        if !presentation.request.isEmpty {
            let current=ConversationCard(title:session.active ? "현재 진행 중인 작업" : "현재 작업",body:EvidencePrivacy.text(presentation.request))
            current.button("실제 단계 상세") { [weak self] in self?.workspace.showTaskDetails() };view.append(current)
        }
        do {
            let items=try TaskHistory.summaries()
            if items.isEmpty { view.append(ConversationCard(title:"저장된 작업이 없습니다",body:"새 작업부터 단계별 시각과 근거를 저장합니다.")) }
            for item in items {
                let card=ConversationCard(title:UserStatus.result(item.status),body:item.request)
                card.label("요청 ID · "+item.identifier+"\n보고서 수정 시각 · "+TaskDetailView.format(item.modifiedAt),size:11)
                card.button("작업 상세 보기") { [weak self] in
                    do { self?.showHistoryDetail(try TaskHistory.load(item.directory),directory:item.directory) }
                    catch { self?.showHistoryError(String(describing:error)) }
                }
                view.append(card)
            }
        } catch { view.append(ConversationCard(title:"기록 확인 제한",body:String(describing:error))) }
        detailWindow?.close()
        let panel=NSWindow(contentRect:CGRect(x:0,y:0,width:740,height:640),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title="작업 기록 · 요약에서 상세 보기";panel.isReleasedWhenClosed=false;panel.contentView=view;detailWindow=panel;panel.center();panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak view] in view?.layoutSubtreeIfNeeded();view?.documentView?.scroll(.zero) }
    }
    private func showHistoryDetail(_ state:RunPresentationState,directory:String) {
        detailWindow?.close()
        let panel=NSWindow(contentRect:CGRect(x:0,y:0,width:780,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title="작업 상세 · "+URL(fileURLWithPath:directory).lastPathComponent
        panel.isReleasedWhenClosed=false;panel.contentView=TaskDetailView(state:state,directory:directory);detailWindow=panel;panel.center();panel.makeKeyAndOrderFront(nil)
    }
    private func showHistoryError(_ message:String) { showDetailCard(ConversationCard(title:"작업 근거를 읽지 못했습니다",body:message),title:"기록 확인 제한") }
    @objc private func showConnection() { guard !session.active else { return }; if connection == nil { connection = ConnectionWindow(); connection?.onChange = { [weak self] in self?.setup.check(forceConnection:true) } }; connection?.show() }
}
