import AppKit

@MainActor final class ConversationButton:NSButton {
    var invoke:() -> Void = {}
    init(_ title:String,action:@escaping () -> Void) { super.init(frame:.zero); self.title = title; invoke = action; target = self; self.action = #selector(invokeAction); bezelStyle = .rounded }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func invokeAction() { invoke() }
}
@MainActor final class ConversationCard:NSView {
    let stack = NSStackView()
    init(title:String,body:String = "") {
        super.init(frame:.zero); wantsLayer = true; layer?.cornerRadius = 12
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-14)])
        label(title,size:16,bold:true); if !body.isEmpty { label(body) }; updateColor()
    }
    required init?(coder:NSCoder) { fatalError() }
    @discardableResult func label(_ text:String,size:CGFloat = 15,bold:Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString:text); label.font = .systemFont(ofSize:size,weight:bold ? .semibold : .regular); label.isSelectable = true
        stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true; return label
    }
    func row(_ views:[NSView]) { let row = NSStackView(views:views); row.orientation = .horizontal; row.spacing = 8; row.alignment = .centerY; stack.addArrangedSubview(row) }
    func button(_ title:String,_ action:@escaping () -> Void) { stack.addArrangedSubview(ConversationButton(title,action:action)) }
    func setControlsEnabled(_ enabled:Bool) {
        func walk(_ view:NSView) { (view as? NSControl)?.isEnabled = enabled; view.subviews.forEach(walk) }; walk(stack)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColor() }
    private func updateColor() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.borderColor = NSColor.separatorColor.cgColor; layer?.borderWidth = 1 } }
}
@MainActor final class ConversationDocument:NSView { override var isFlipped:Bool { true } }
@MainActor class ConversationView:NSScrollView {
    let cards = NSStackView()
    override init(frame:NSRect) {
        super.init(frame:frame); hasVerticalScroller = true; autohidesScrollers = true; drawsBackground = false
        let document = ConversationDocument(); document.translatesAutoresizingMaskIntoConstraints = false; documentView = document
        cards.orientation = .vertical; cards.alignment = .leading; cards.spacing = 12; cards.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(cards)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:contentView.widthAnchor),cards.topAnchor.constraint(equalTo:document.topAnchor,constant:14),cards.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-14),cards.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:18),cards.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-18)])
    }
    required init?(coder:NSCoder) { fatalError() }
    func append(_ card:ConversationCard) { cards.addArrangedSubview(card); card.widthAnchor.constraint(equalTo:cards.widthAnchor).isActive = true; scrollToEnd() }
    func scrollToEnd() { DispatchQueue.main.async { [weak self] in guard let self else { return }; self.documentView?.scroll(NSPoint(x:0,y:max(0,(self.documentView?.bounds.height ?? 0)-self.contentView.bounds.height))) } }
    func remove(_ card:ConversationCard) { cards.removeArrangedSubview(card); card.removeFromSuperview() }
}
@MainActor final class EventPlanEditor {
    var original:ResearchEvent
    let start:NSTextField; let end:NSTextField; let zone:NSTextField; let location:NSTextField; let allDay:NSButton; let include:NSButton
    init(_ event:ResearchEvent,card:ConversationCard) {
        original = event; start = NSTextField(string:event.start); end = NSTextField(string:event.end); zone = NSTextField(string:event.timeZone); location = NSTextField(string:event.location)
        allDay = NSButton(checkboxWithTitle:"종일 일정으로 확정",target:nil,action:nil); allDay.state = event.allDay ? .on : .off
        include = NSButton(checkboxWithTitle:"이 일정 등록",target:nil,action:nil); include.state = .on
        card.label(event.title,size:16,bold:true)
        if !event.clarification.isEmpty { card.label("확인이 필요해요: "+event.clarification).textColor = .systemOrange }
        card.label("\(event.start.isEmpty ? "시작 미확정" : event.start) ~ \(event.end.isEmpty ? "종료 미확정" : event.end)\n시간대: \(event.timeZone.isEmpty ? "미확정" : event.timeZone) · \(event.allDay ? "종일" : "시간 지정")\n장소: \(event.location.isEmpty ? "미확정" : event.location)",size:14)
        let fields = NSStackView(); fields.orientation = .vertical; fields.alignment = .leading; fields.spacing = 6
        card.stack.addArrangedSubview(fields); fields.widthAnchor.constraint(equalTo:card.stack.widthAnchor).isActive = true
        fields.isHidden = event.clarification.isEmpty
        for (name,field) in [("시작",start),("종료 (종일이면 다음 날)",end),("시간대",zone),("장소",location)] {
            field.setAccessibilityLabel(event.title+" · "+name); field.placeholderString = name == "시간대" ? "Asia/Seoul" : name == "장소" ? "출처의 장소" : "2026-10-11T09:00:00+09:00 / 2026-10-11"
            let label = NSTextField(labelWithString:name); label.font = .systemFont(ofSize:12); fields.addArrangedSubview(label); fields.addArrangedSubview(field); field.widthAnchor.constraint(equalTo:fields.widthAnchor).isActive = true
        }
        fields.addArrangedSubview(allDay)
        let edit = ConversationButton("날짜·장소 수정") { fields.isHidden.toggle() }
        card.row([include,edit]); card.label("출처 [\(event.sourceID)] · "+event.quotes.joined(separator:" / "),size:13)
    }
    func value() -> ResearchEvent? {
        guard include.state == .on else { return nil }
        var result = original; result.start = start.stringValue.trimmingCharacters(in:.whitespacesAndNewlines); result.end = end.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        result.timeZone = zone.stringValue.trimmingCharacters(in:.whitespacesAndNewlines); result.location = location.stringValue; result.allDay = allDay.state == .on
        let changed = result != original || !original.clarification.isEmpty
        result.clarification = ""; if changed { result.userConfirmed = true }; return result
    }
}

@MainActor final class WorkspaceSurface:NSView {
    override init(frame:NSRect) { super.init(frame:frame); wantsLayer = true; layer?.cornerRadius = 16; updateSurface() }
    convenience init() { self.init(frame:.zero) }
    required init?(coder:NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateSurface() }
    private func updateSurface() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderWidth = 1; layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.06; layer?.shadowRadius = 12; layer?.shadowOffset = CGSize(width:0,height:-3)
        }
    }
}

@MainActor final class SendRequestButton:NSButton {
    override func draw(_ dirtyRect:NSRect) {
        (isEnabled ? NSColor.labelColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()
        contentTintColor = .controlBackgroundColor
        super.draw(dirtyRect)
    }
}
