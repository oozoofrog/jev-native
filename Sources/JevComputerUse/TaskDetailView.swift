import AppKit

@MainActor final class TaskDetailView:ConversationView {
    private var rawWindow:NSWindow?
    private weak var focusedCard:NSView?
    init(state:RunPresentationState,directory:String?,selectedRecord:Int? = nil) {
        super.init(frame:.zero)
        let header=ConversationCard(title:"실제 작업 상세",body:state.request.isEmpty ? "요청 원문이 기록되지 않았습니다." : EvidencePrivacy.text(state.request))
        header.label("기록에 있는 관측·응답·오류만 표시합니다. 계획과 실행, 수신과 검증을 구분합니다.",size:12)
        if let directory { header.label("요청 ID · "+URL(fileURLWithPath:directory).lastPathComponent,size:11) }
        if state.paused { header.label("실행이 실제로 일시정지된 상태입니다.",size:12,bold:true) }
        append(header)
        let hasResearchDetail=state.topology.contains { $0.detail?.id == "search" }
        let records=hasResearchDetail ? state.topology.filter { $0.id == selectedRecord || $0.detail != nil || [.request,.plan,.result,.outcome].contains($0.kind) } : state.topology
        for (index,record) in records.enumerated() {
            let detail=TaskDetailProjection.detail(record)
            let card=ConversationCard(title:"\(index+1). "+detail.title,body:EvidencePrivacy.text(detail.summary))
            let status=NSTextField(labelWithString:state.paused && detail.state == .running ? "일시정지 대기" : detail.statusLabel)
            status.font = .systemFont(ofSize:12,weight:.semibold)
            status.textColor = detail.state == .failed ? .systemRed : detail.state == .partial ? .systemOrange : .secondaryLabelColor
            let image=NSImageView(image:NSImage(systemSymbolName:detail.state == .failed ? "exclamationmark.circle.fill" : detail.state == .completed ? "checkmark.circle.fill" : "circle.dotted",accessibilityDescription:detail.statusLabel) ?? NSImage())
            image.contentTintColor=status.textColor;image.setContentHuggingPriority(.required,for:.horizontal)
            card.row([image,status])
            if selectedRecord==record.id { card.label("선택한 단계",size:11,bold:true);focusedCard=card }
            if let date=record.recordedAt {
                card.label((record.timeSource ?? "실제 이벤트 기록 시각")+" · "+Self.format(date)+(record.updatedAt.map { "   ·   마지막 갱신 · "+Self.format($0) } ?? ""),size:11)
            } else { card.label("이 단계의 시각은 미기록",size:11) }
            for field in detail.fields {
                card.label(EvidencePrivacy.text(field.label),size:11,bold:true)
                card.label(EvidencePrivacy.text(String(field.value.prefix(4000))),size:13)
                if field.value.count>4000 { card.label("긴 내용은 아래 원문 확인에서 볼 수 있습니다.",size:11) }
            }
            if let directory {
                for link in detail.evidence {
                    var file=link.file
                    let prefix=URL(fileURLWithPath:directory).standardizedFileURL.path+"/"
                    if file.hasPrefix(prefix) { file=String(file.dropFirst(prefix.count)) }
                    let relative=file
                    card.button("근거 · "+link.label) { [weak self] in
                        do { self?.showRaw(try TaskEvidenceFiles.preview(relative,directory:directory),title:link.label) }
                        catch { self?.showRaw(String(describing:error),title:"근거 확인 제한") }
                    }
                }
            }
            if record.detail == nil {
                card.button("단계 원문 확인 · 보조") { [weak self] in self?.showRaw(EvidencePrivacy.text(record.text),title:record.title) }
            }
            append(card)
            if index<records.count-1 { let connector=ConversationCard(title:"↓",body:"다음 실제 기록");append(connector) }
        }
        if hasResearchDetail,let directory {
            let auxiliary=ConversationCard(title:"보조 기록",body:"상세 단계는 위 흐름에 정리했습니다. 전달된 이벤트 원문은 보조 확인 수단입니다.")
            auxiliary.button("전체 이벤트 기록 원문") { [weak self] in
                do { self?.showRaw(try TaskEvidenceFiles.preview("task-events.jsonl",directory:directory),title:"실제 이벤트 원문") }
                catch { self?.showRaw(String(describing:error),title:"원문 기록 확인 제한") }
            }
            append(auxiliary)
        }
        // Conversation append normally follows the newest card. A detail view
        // starts at the selected step, or at the request when opened as a flow.
        DispatchQueue.main.async { [weak self] in
            guard let self,let document=self.documentView else { return }
            self.layoutSubtreeIfNeeded()
            let y=self.focusedCard.map { $0.convert($0.bounds,to:document).minY } ?? 0
            document.scroll(NSPoint(x:0,y:max(0,y-14)))
            self.reflectScrolledClipView(self.contentView)
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    static func format(_ date:Date) -> String { let formatter=DateFormatter();formatter.dateStyle = .medium;formatter.timeStyle = .medium;return formatter.string(from:date) }
    private func showRaw(_ text:String,title:String) {
        let view=ConversationView(frame:.zero);view.append(ConversationCard(title:title,body:text))
        rawWindow?.close()
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:720,height:540),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="근거 원문 · 보조 확인";window.isReleasedWhenClosed=false;window.contentView=view;rawWindow=window;window.center();window.makeKeyAndOrderFront(nil)
    }
}
