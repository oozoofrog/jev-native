import AppKit

/// Native controls and full evidence remain accessible; the graph itself is a Metal surface.
@MainActor final class TopologyWorkspace:NSView {
    var onCommand:(String) -> Void = { _ in }
    var onDetails:(String) -> Bool = { _ in false }
    var runDirectory:String?
    let canvas = MetalTopologyView()
    private let heading = NSTextField(labelWithString:"요청 대기")
    private let mode = NSTextField(labelWithString:"자동 추적 · 현재 단계에 맞춰 확대·축소")
    private let historyHeading = NSTextField(labelWithString:"반복 기록")
    private let summary = NSTextField(labelWithString:"")
    private let selection = NSTextField(labelWithString:"완료된 반복을 선택하면 단계와 근거를 펼칩니다.")
    private let follow = NSButton(title:"현재 반복 따라가기",target:nil,action:nil)
    private let overview = NSButton(title:"전체 보기",target:nil,action:nil)
    private let collapse = NSButton(title:"반복 접기",target:nil,action:nil)
    private let failure = NSTextField(wrappingLabelWithString:"")
    private(set) var state = RunPresentationState()
    private(set) var focus = TopologyFocus()
    private(set) var projection = TopologyFocus().projection(RunPresentationState())
    private var queued:RunPresentationState?
    private var selectedRecord:Int?
    private var active = false,frozen = false,cameraInitialized = false
    private var lastRecord:Int?
    private var timer:Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var detailWindow:NSWindow?
    override init(frame:NSRect) {
        super.init(frame:frame)
        heading.font = .systemFont(ofSize:14,weight:.semibold)
        mode.font = .systemFont(ofSize:11); mode.textColor = .secondaryLabelColor
        historyHeading.font = .systemFont(ofSize:11,weight:.medium); historyHeading.textColor = .secondaryLabelColor
        summary.font = .monospacedSystemFont(ofSize:11,weight:.medium); summary.textColor = .secondaryLabelColor
        selection.font = .systemFont(ofSize:11); selection.textColor = .secondaryLabelColor; selection.lineBreakMode = .byTruncatingTail
        follow.target = self; follow.action = #selector(followCurrent)
        overview.target = self; overview.action = #selector(fitWholeCycle)
        collapse.target = self; collapse.action = #selector(followCurrent)
        for button in [follow,overview,collapse] { button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize:11) }
        failure.isHidden = canvas.rendererFailure == nil; failure.stringValue = canvas.rendererFailure.map { "Metal 그래프를 시작하지 못했습니다.\n"+$0 } ?? ""
        for view in [canvas,heading,mode,historyHeading,summary,selection,follow,overview,collapse,failure] { addSubview(view) }
        canvas.onSelect = { [weak self] in self?.select($0) }
        canvas.onManual = { [weak self] in
            guard let self else { return }; self.focus.manual(self.projection.shownCycle); self.refreshLabels()
        }
        timer = Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        refreshLabels()
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    func useDetailedDashboard() {}
    func message(_ text:String) { selection.stringValue = text }
    func update(_ next:RunPresentationState) {
        if state.runID != next.runID {
            queued = nil; focus = TopologyFocus(); selectedRecord = nil; lastRecord = nil
            canvas.railOffset = 0; canvas.eventTime = 0; canvas.pulseStart = nil
            canvas.camera = TopologyCamera(); cameraInitialized = false
            selection.stringValue = "완료된 반복을 선택하면 단계와 근거를 펼칩니다."
        }
        if frozen && state.runID == next.runID { queued = next; return }
        apply(next)
    }
    private func apply(_ next:RunPresentationState) {
        let changed = next.topology.last?.id != lastRecord
        state = next; lastRecord = next.topology.last?.id
        if changed { canvas.pulseStart = canvas.eventTime }
        rebuild(refit:focus.followsCurrent)
    }
    func execution(active:Bool,pauseRequested:Bool,paused:Bool) {
        self.active = active; let wasFrozen = frozen; frozen = active && pauseRequested
        canvas.camera.frozen = frozen
        if wasFrozen && !frozen,let pending = queued { queued = nil; apply(pending) }
        rebuild(refit:false)
    }
    @objc func followCurrent() {
        focus.follow(); selectedRecord = nil; detailWindow?.close(); detailWindow = nil
        selection.stringValue = "완료된 반복을 선택하면 단계와 근거를 펼칩니다."
        rebuild(refit:true)
    }
    @objc func fitWholeCycle() { focus.overview(); selectedRecord = nil; rebuild(refit:true) }
    func select(_ id:MetalTopologyID) {
        switch id {
        case .cycle(let cycle):
            if projection.currentCycle == cycle && !state.completedCycles.contains(cycle) { focus.follow() }
            else { focus.inspect(cycle) }
            selectedRecord = nil
            selection.stringValue = "완료된 반복을 선택하면 단계와 근거를 펼칩니다."
            rebuild(refit:true)
            showTaskDetails()
        case .record(let id):
            guard let record = state.topology.first(where: { $0.id == id }) else { return }
            focus.manual(projection.shownCycle); selectedRecord = id
            rebuild(refit:false)
            if let card = canvas.cards.first(where: { $0.id == .record(id) }) {
                canvas.camera.fit(card.frame,in:canvas.mainViewport,minimumScale:1,maximumScale:1.15,snap:frozen); canvas.draw()
            }
            selection.stringValue = (record.cycle > 0 ? "반복 \(record.cycle) · " : "")+record.title+" · 전문과 근거 확인 중"
            showDetails(record)
        }
    }
    private func refreshLabels() {
        collapse.isHidden = focus.inspectedCycle == nil
        follow.isEnabled = !focus.followsCurrent
        heading.stringValue = projection.shownCycle.map { "반복 \($0) · "+(state.completedCycles.contains($0) ? "기록 확인" : "진행 중") } ?? (state.outcome == nil ? (state.cycle == 0 ? "요청 준비" : "다음 단계 준비") : "작업 결과")
        mode.stringValue = frozen ? "일시정지 · 자동 이동과 실행 애니메이션 정지" : focus.followsCurrent ? "자동 추적 · 현재 단계에 맞춰 확대·축소" : "기록 확인 · 현재 반복 따라가기로 복귀"
        summary.stringValue = "반복 \(projection.summaries.count)회 · 접힌 반복 \(projection.summaries.filter { $0.closed && !$0.expanded }.count)개 · 전체 단계 \(state.topology.count)개"
        historyHeading.stringValue = projection.summaries.isEmpty ? "반복 기록" : "반복 기록 · \(projection.summaries.count)개"
        needsLayout = true
    }
    private func rebuild(refit:Bool) {
        projection = focus.projection(state)
        let frames = TopologyStageLayout.frames(count:projection.records.count,viewport:canvas.mainViewport.size)
        let maxOffset = max(0,CGFloat(projection.summaries.count)*100-canvas.bounds.height+32)
        if focus.followsCurrent { canvas.railOffset = maxOffset }
        else { canvas.railOffset = min(canvas.railOffset,maxOffset) }
        var cards = projection.summaries.enumerated().map { index,item in
            MetalTopologyCard(id:.cycle(item.cycle),frame:CGRect(x:8,y:16+CGFloat(index)*100-canvas.railOffset,width:canvas.railWidth,height:84),
                title:item.title,badge:item.subtitle,text:item.preview,footnote:!item.closed ? "진행 중 · 자동 추적" : item.expanded ? "펼침 · 선택해 접기" : "접힘 · 선택해 펼치기",
                selected:item.expanded,current:active && !frozen && projection.currentCycle == item.cycle,isRail:true)
        }
        cards += zip(projection.records,frames).map { record,frame in
            let number = (state.topology.firstIndex(where: { $0.id == record.id }) ?? 0)+1
            return MetalTopologyCard(id:.record(record.id),frame:frame,title:record.kind == .source ? "원문" : record.title,
                badge:"단계 \(number) · "+(record.detail?.statusLabel ?? (record.cycle > 0 ? "반복 \(record.cycle)" : "시작")),text:String((record.detail?.summary ?? TaskDetailProjection.detail(record).summary).prefix(180)),footnote:"선택해 실제 단계·시각·근거 확인",selected:selectedRecord == record.id,current:active && !frozen && projection.currentRecordID == record.id)
        }
        canvas.cards = cards
        if refit,!frames.isEmpty {
            let content = TopologyStageLayout.focusBounds(frames,whole:focus.fitsWholeCycle,viewport:canvas.mainViewport)
            canvas.camera.fit(content,in:canvas.mainViewport,minimumScale:focus.fitsWholeCycle ? 0.45 : 0.8,snap:!cameraInitialized || frozen)
            cameraInitialized = true
        }
        refreshLabels(); canvas.draw()
    }
    override func layout() {
        super.layout()
        let oldSize = canvas.bounds.size
        canvas.frame = CGRect(x:20,y:48,width:max(1,bounds.width-40),height:max(1,bounds.height-112))
        var x = bounds.width-20
        for button in [overview,follow,collapse] where !button.isHidden { button.sizeToFit(); x -= button.frame.width; button.setFrameOrigin(CGPoint(x:x,y:bounds.height-29)); x -= 8 }
        heading.frame = CGRect(x:canvas.mainViewport.minX+20,y:bounds.height-29,width:max(1,x-canvas.mainViewport.minX-28),height:21)
        mode.frame = CGRect(x:canvas.mainViewport.minX+20,y:bounds.height-48,width:max(1,bounds.width-canvas.mainViewport.minX-50),height:17)
        historyHeading.frame = CGRect(x:28,y:bounds.height-43,width:canvas.railWidth,height:19)
        summary.frame = CGRect(x:28,y:26,width:max(1,bounds.width-56),height:18)
        selection.frame = CGRect(x:28,y:6,width:max(1,bounds.width-56),height:17)
        failure.frame = CGRect(x:canvas.mainViewport.minX+32,y:bounds.midY,width:max(1,bounds.width-canvas.mainViewport.minX-64),height:100)
        if oldSize != canvas.bounds.size { rebuild(refit:focus.followsCurrent || focus.fitsWholeCycle) }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime,dt = min(0.05,max(0,now-lastTick)); lastTick = now
        guard !frozen,window?.isVisible == true else { return }
        let moving = canvas.camera.isMoving,pulsing = canvas.pulseStart.map { canvas.eventTime-$0 < 1.1 } ?? false
        guard moving || pulsing else { return }
        canvas.eventTime += dt
        canvas.camera.advance(dt,reducedMotion:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        canvas.draw()
    }
    private func showDetails(_ record:TopologyRecord) {
        showTaskDetails(selectedRecord:record.id)
    }
    func showTaskDetails(selectedRecord:Int? = nil) {
        let view=TaskDetailView(state:queued ?? state,directory:runDirectory,selectedRecord:selectedRecord)
        let refresh=ConversationCard(title:"선택 시점의 기록",body:"새 기록은 실제 실행에서만 추가됩니다.")
        refresh.button("최신 단계로 새로고침") { [weak self] in self?.showTaskDetails(selectedRecord:selectedRecord) }
        view.cards.insertArrangedSubview(refresh,at:0)
        detailWindow?.close()
        let panel = NSWindow(contentRect:CGRect(x:0,y:0,width:780,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        panel.title = "작업 상세 · 실제 단계와 근거"; panel.isReleasedWhenClosed = false; panel.contentView = view; detailWindow = panel; panel.center(); panel.makeKeyAndOrderFront(nil)
    }
}
