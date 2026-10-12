import Foundation

extension Action {
    func presentationLabel(observation:Observation) -> String {
        let title = target.flatMap { id in observation.nodes.first { $0.id == id }?.title } ?? ""
        switch kind {
        case "press": return title.isEmpty ? "선택한 버튼 누르기" : "버튼 누르기 · " + title
        case "focus": return title.isEmpty ? "입력란 선택" : "입력란 선택 · " + title
        case "type": return "텍스트 입력 · \((text ?? "").count)자"
        case "key": return "키 입력 · " + ((modifiers ?? []) + [key ?? ""]).joined(separator:" + ")
        case "launch": return "대상 앱 실행"
        case "activate": return "대상 앱 활성화"
        case "openFile": return "요청한 파일 열기"
        case "selectWindow": return "창 선택 · " + (observation.windows.first { $0.id == windowID }?.title ?? "선택한 창")
        case "scroll": return "대상 창 스크롤"
        case "click": return "대상 창 클릭"
        case "doubleClick": return "대상 창 두 번 클릭"
        case "rightClick": return "대상 창 보조 클릭"
        case "drag": return "대상 창에서 드래그"
        case "move": return "작업 포인터 이동"
        case "raise": return "선택한 창 앞으로 가져오기"
        case "wait": return "화면 응답 대기"
        default: return "대상 앱에서 동작"
        }
    }
}

/// Presentation facts come from the runner. No animation can advance execution or assert completion.
struct ResearchCounts:Codable,Equatable { var sources:Int?; var found:Int?; var ready:Int?; var registered:Int? }

struct RunPresentationEvent: Codable,Equatable {
    enum Fact: Codable,Equatable {
        case request(String), phase(String), target(String), source(String, String), plan(String)
        case observation(String), action(String), input(String), result(String), outcome(String), pause(Bool), research(ResearchCounts)
        case cycle(Int), cycleEnd(Int), execution(String), verification(String), recovery(String)
        case commandStarted(String), commandOutput(String,String,[String])
        case detail(TaskStepDetail), failure(String)
    }
    let runID: UUID
    let sequence: Int
    let fact: Fact
    var recordedAt:Date = Date()
}

struct TopologyRecord: Equatable, Identifiable {
    enum Kind: String { case request, plan, source, observation, decision, execution, verification, recovery, result, outcome, commandOutput }
    let id: Int
    let kind: Kind
    let cycle: Int
    let title: String
    var text: String
    var evidencePaths:[String]? = nil
    var recordedAt:Date? = nil
    var detail:TaskStepDetail? = nil
    var updatedAt:Date? = nil
    var timeSource:String? = nil
}

struct RunPresentationState: Equatable {
    var runID: UUID?
    private var retiredRuns = Set<UUID>()
    var sequence = -1
    var request = ""
    var phase = "요청을 기다리고 있어요"
    var target = ""
    var plan = ""
    var source = ""
    var sourceTitle = "원문"
    var result = ""
    var outcome: String?
    var paused = false
    var history: [String] = []
    var historyFocus: [Double] = []
    var inputs = 0
    var localCommands = 0
    private var commandOutputRecords:[String:Int] = [:]
    private var detailRecords:[String:Int] = [:]
    private var currentEventDate:Date?
    var research:ResearchCounts?
    var cycle = 0
    var topology: [TopologyRecord] = []
    var completedCycles = Set<Int>()
    var hasDocumentProvenance: Bool { !source.isEmpty && !result.isEmpty }

    mutating func apply(_ event: RunPresentationEvent) {
        if case .request = event.fact, event.runID != runID {
            guard !retiredRuns.contains(event.runID) else { return }
            var retired = retiredRuns; if let runID { retired.insert(runID) }
            self = RunPresentationState(); runID = event.runID; retiredRuns = retired
        }
        guard event.runID == runID, event.sequence > sequence else { return }
        sequence = event.sequence
        currentEventDate=event.recordedAt
        switch event.fact {
        case .request(let text): request = text; record("요청 접수",focus:0); append(.request,"요청",text)
        case .phase(let text):
            phase = UserStatus.progress(text)
            if history.last != phase { record(phase,focus:text == "source" ? -1 : 0) }
        case .target(let text): target = text
        case .plan(let text): plan = text; record("실행 계획 확인",focus:0); append(.plan,"실행 계획",text)
        case .source(let text, let title): source = text; sourceTitle = title; record("원문 확인 · " + title,focus:-1); append(.source,title,text)
        case .cycle(let index):
            if cycle > 0 && cycle != index { completedCycles.insert(cycle) }
            cycle = index
        case .cycleEnd(let index): completedCycles.insert(index)
        case .observation(let text): record("관찰 · " + text,focus:0); append(.observation,"관찰",text)
        case .action(let text): record("선택 · " + text,focus:0); append(.decision,"판단",text)
        case .input(let text): inputs += 1; record("실행 · " + text,focus:1); append(.execution,"앱 입력",text)
        case .execution(let text): record("실행 · " + text,focus:1); append(.execution,"실행",text)
        case .commandStarted(let text): localCommands += 1; record("로컬 명령 실행",focus:1); append(.execution,"로컬 명령",text)
        case .commandOutput(let id,let text,let paths):
            if let recordID = commandOutputRecords[id],let index = topology.firstIndex(where: { $0.id == recordID }) {
                topology[index] = TopologyRecord(id:recordID,kind:.commandOutput,cycle:topology[index].cycle,title:"명령 출력",text:text,evidencePaths:paths,recordedAt:topology[index].recordedAt,updatedAt:event.recordedAt)
            } else {
                topology.append(TopologyRecord(id:sequence,kind:.commandOutput,cycle:cycle,title:"명령 출력",text:text,evidencePaths:paths,recordedAt:event.recordedAt))
                commandOutputRecords[id] = sequence; record("명령 출력 수신",focus:0)
            }
        case .verification(let text): record("확인 · " + text,focus:0); append(.verification,"실행 후 확인",text)
        case .detail(let detail):
            if let recordID=detailRecords[detail.id],let index=topology.firstIndex(where:{$0.id==recordID}) {
                topology[index].detail=detail; topology[index].text=detail.summary; topology[index].updatedAt=event.recordedAt
            } else {
                topology.append(TopologyRecord(id:sequence,kind:.execution,cycle:cycle,title:detail.title,text:detail.summary,recordedAt:event.recordedAt,detail:detail,updatedAt:event.recordedAt))
                detailRecords[detail.id]=sequence
            }
        case .failure(let text):
            append(.recovery,"오류",text)
            topology[topology.count-1].detail = .init(id:"failure-\(sequence)",title:"실제 오류",summary:EvidencePrivacy.text(text),state:.failed,fields:[.init(label:"확인된 오류",value:EvidencePrivacy.text(text))])
            if let index=topology.lastIndex(where:{$0.detail?.state == .running}) {
                topology[index].detail?.state = .failed; topology[index].detail?.fields.append(.init(label:"확인된 오류",value:EvidencePrivacy.text(text))); topology[index].updatedAt=event.recordedAt
            }
        case .recovery(let text): record("재시도 근거 · " + text,focus:0); append(.recovery,"복구 판단",text)
        case .result(let text): if result != text { result = text; if !text.isEmpty { record("결과 수신",focus:1); append(.result,"결과",text) } }
        case .outcome(let text):
            let failed=text == "error" || text == "local_failed" || text.hasSuffix("_error")
            let cancelled=text == "cancelled" || text.hasSuffix("_cancelled")
            if cancelled || failed {
                for index in topology.indices where topology[index].detail?.state == .running { topology[index].detail?.state = cancelled ? .cancelled : .failed;topology[index].updatedAt=event.recordedAt }
            }
            outcome = text; phase = UserStatus.result(text); record(phase,focus:result.isEmpty ? 0 : 1); append(.outcome,"종료 상태",phase)
            if let index=topology.indices.last {
                let state:TaskStepDetail.State = failed ? .failed : cancelled ? .cancelled : text.contains("partial") || text.contains("blocked") || text.contains("unresolved") || text.contains("needs_fields") ? .partial : .completed
                topology[index].detail = .init(id:"outcome",title:"종료 상태",summary:phase,state:state,fields:[.init(label:"실제 종료 코드",value:text)])
            }
            completedCycles.formUnion(topology.map(\.cycle).filter { $0 > 0 })
        case .pause(let value): paused = value
        case .research(let counts): research = counts
        }
    }
    private mutating func append(_ kind:TopologyRecord.Kind,_ title:String,_ text:String) {
        topology.append(TopologyRecord(id:sequence,kind:kind,cycle:cycle,title:title,text:text,recordedAt:currentEventDate))
    }
    private mutating func record(_ text:String,focus:Double) { history.append(text); historyFocus.append(focus) }
}

/// One clock for the entire world. Pausing preserves camera, content and transfer positions.
struct SpatialMotion {
    var time = 0.0
    var focus = 0.0
    var target = 0.0
    var velocity = 0.0
    var frozen = false
    mutating func advance(_ delta: Double, reducedMotion: Bool) {
        guard !frozen else { return }
        let dt = max(0, min(delta, 0.05)); time += dt
        if reducedMotion { focus = target; velocity = 0; return }
        velocity += ((target-focus)*28 - velocity*10)*dt
        focus += velocity*dt
        if abs(target-focus) < 0.0001 && abs(velocity) < 0.0001 { focus = target; velocity = 0 }
    }
}
