import Foundation

struct TaskRunSummary {
    var directory:String
    var request:String
    var status:String
    var modifiedAt:Date
    var identifier:String { URL(fileURLWithPath:directory).lastPathComponent }
}

enum TaskHistory {
    static var defaultRoot:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runs") }
    static func summaries(root:URL = defaultRoot) throws -> [TaskRunSummary] {
        let directories=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles])
        return directories.compactMap { directory in
            guard UUID(uuidString:directory.lastPathComponent) != nil,
                  directory.standardizedFileURL.resolvingSymlinksInPath()==directory.standardizedFileURL,
                  let url=try? TaskEvidenceFiles.resolve("report.json",directory:directory.path),
                  let attributes=try? FileManager.default.attributesOfItem(atPath:url.path),
                  (attributes[.size] as? Int ?? Int.max)<2_000_000,
                  let data=try? Data(contentsOf:url),let report=try? JSONDecoder().decode(RunReport.self,from:data) else { return nil }
            return TaskRunSummary(directory:directory.path,request:EvidencePrivacy.text(report.goal),status:report.status,modifiedAt:attributes[.modificationDate] as? Date ?? .distantPast)
        }.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(30).map { $0 }
    }

    static func load(_ directory:String) throws -> RunPresentationState {
        var state=RunPresentationState()
        let root=URL(fileURLWithPath:directory)
        if FileManager.default.fileExists(atPath:root.appendingPathComponent("task-events.jsonl").path) {
            let url=try TaskEvidenceFiles.resolve("task-events.jsonl",directory:directory)
            let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
            guard (attributes[.size] as? Int ?? Int.max)<8_000_000 else { throw Failure("단계 기록이 읽기 한도를 넘습니다.") }
            let lines=try String(contentsOf:url,encoding:.utf8).split(separator:"\n")
            var runID:UUID?,lastSequence = -1
            for line in lines {
                let event=try JSONDecoder().decode(RunPresentationEvent.self,from:Data(line.utf8))
                if runID == nil { guard case .request=event.fact else { throw Failure("요청 시작 기록이 없는 단계 파일입니다.") } }
                guard runID == nil || event.runID == runID,event.sequence > lastSequence else { throw Failure("다른 작업이 섞였거나 단계 순서가 손상된 기록입니다.") }
                runID=event.runID;lastSequence=event.sequence;state.apply(event)
            }
            return state
        }
        // Legacy evidence never invents missing activity or exact operation timestamps.
        let reportURL=try TaskEvidenceFiles.resolve("report.json",directory:directory)
        let report=try JSONDecoder().decode(RunReport.self,from:Data(contentsOf:reportURL))
        let id=UUID(uuidString:root.lastPathComponent) ?? UUID()
        var sequence=0
        func record(_ file:String,_ fact:RunPresentationEvent.Fact) throws {
            let url=try TaskEvidenceFiles.resolve(file,directory:directory)
            let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
            let date=attributes[.modificationDate] as? Date ?? .distantPast
            let oldCount=state.topology.count
            state.apply(.init(runID:id,sequence:sequence,fact:fact,recordedAt:date));sequence+=1
            for index in oldCount..<state.topology.count { state.topology[index].timeSource="파일 수정 시각 · 당시 실행 시각 미기록" }
        }
        try record("report.json",.request(report.goal))
        if let url=try? TaskEvidenceFiles.resolve("workflow-jev.json",directory:directory),
           let root=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any],
           let answers=root["answers"] as? [String:Any],let choice=answers["route"] as? [String:Any],let selected=choice["choice"] as? String {
            try record("workflow-jev.json",.detail(.init(id:"legacy-workflow",title:"작업 경로 선택",summary:"저장된 선택 응답에 작업 경로가 있습니다.",state:.completed,fields:[.init(label:"선택 경로",value:selected),.init(label:"시각 기준",value:"파일 수정 시각 · 당시 실행 시각은 별도 미기록")],evidence:[.init(file:"workflow-jev.json",label:"원래 선택 응답")])))
        }
        if let url=try? TaskEvidenceFiles.resolve("query/codex-result.json",directory:directory),let handoff=try? JSONDecoder().decode(Handoff.self,from:Data(contentsOf:url)) {
            try record("query/codex-result.json",.detail(.init(id:"legacy-query",title:"검색어 생성",summary:"저장된 Codex 응답에서 검색어를 확인했습니다.",state:.completed,fields:[.init(label:"검색어",value:handoff.text),.init(label:"시각 기준",value:"파일 수정 시각")],evidence:[.init(file:"query/codex-result.json",label:"원래 검색어 응답")])))
        }
        if let url=try? TaskEvidenceFiles.resolve("search-results.json",directory:directory),let results=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [[String:String]] {
            try record("search-results.json",.detail(.init(id:"legacy-search",title:"검색 결과 수신",summary:"검색 결과 \(results.count)개가 저장돼 있습니다. 원문 수집·사실 확인 완료와는 다릅니다.",state:.completed,fields:results.map { .init(label:$0["title"] ?? "검색 결과",value:$0["url"] ?? "") }+[.init(label:"시각 기준",value:"파일 수정 시각")],evidence:[.init(file:"search-results.json",label:"원래 검색 결과")])))
        }
        if let response=report.response,!response.isEmpty { try record("report.json",.result(response)) }
        if report.error != nil,FileManager.default.fileExists(atPath:root.appendingPathComponent("search-results.json").path),!FileManager.default.fileExists(atPath:root.appendingPathComponent("source-choice-diagnostic.json").path) {
            try record("report.json",.detail(.init(id:"legacy-diagnostic-gap",title:"실패 진단의 기록 범위",summary:"검색 결과는 보존돼 있으나 출처 선택의 거부 응답 진단은 없습니다. HTTP·응답 구조·신뢰도 중 정확한 원인을 이 자료만으로 단정하지 않습니다.",state:.partial,fields:[.init(label:"기록되지 않은 근거",value:"source-choice-diagnostic.json")],evidence:[.init(file:"report.json",label:"원래 종료 보고서")])))
        }
        if let error=report.error { try record("report.json",.failure(error)) }
        try record("report.json",.outcome(report.status))
        return state
    }
}
