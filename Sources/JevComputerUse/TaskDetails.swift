import Foundation

struct TaskDetailField:Codable,Equatable { var label:String; var value:String }
struct TaskEvidenceLink:Codable,Equatable { var file:String; var label:String }
struct TaskStepDetail:Codable,Equatable {
    enum State:String,Codable { case running,waiting,completed,partial,failed,cancelled }
    var id:String
    var title:String
    var summary:String
    var state:State
    var fields:[TaskDetailField] = []
    var evidence:[TaskEvidenceLink] = []
    var statusLabel:String { switch state { case .running:return "진행 중";case .waiting:return "대기";case .completed:return "확인됨";case .partial:return "일부 확인";case .failed:return "오류";case .cancelled:return "중지" } }
}

enum TaskEvidenceFiles {
    static func resolve(_ file:String,directory:String) throws -> URL {
        let root=URL(fileURLWithPath:directory).standardizedFileURL.resolvingSymlinksInPath()
        guard !file.hasPrefix("/"),!file.split(separator:"/").contains(".."),!file.isEmpty else { throw Failure("이 작업의 상대 근거 파일만 볼 수 있습니다.") }
        let url=root.appendingPathComponent(file).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path+"/"),FileManager.default.fileExists(atPath:url.path) else { throw Failure("이 작업에서 저장한 근거 파일을 찾지 못했습니다.") }
        return url
    }
    static func preview(_ file:String,directory:String) throws -> String {
        let url=try resolve(file,directory:directory),handle=try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        let data=try handle.read(upToCount:131073) ?? Data(),limited=data.count>131072
        let bounded=Data(data.prefix(131072))
        let raw=String(decoding:bounded,as:UTF8.self),trimmed=String(decoding:bounded,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        var structured=false
        let text:String
        if url.pathExtension.lowercased() == "json" || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if !limited,let object=try? JSONSerialization.jsonObject(with:bounded,options:.fragmentsAllowed),let redacted=try? JSONSerialization.data(withJSONObject:EvidencePrivacy.json(object),options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed]) {
                text=String(decoding:redacted,as:UTF8.self)
                structured=true
            } else if !limited,url.pathExtension.lowercased() != "json",raw.split(separator:"\n").allSatisfy({ (try? JSONSerialization.jsonObject(with:Data($0.utf8),options:.fragmentsAllowed)) != nil }) {
                text=raw.split(separator:"\n").map { line in
                    guard let object=try? JSONSerialization.jsonObject(with:Data(line.utf8),options:.fragmentsAllowed),let redacted=try? JSONSerialization.data(withJSONObject:EvidencePrivacy.json(object),options:[.sortedKeys,.fragmentsAllowed]) else { return "[JSON 행을 표시하지 않습니다.]" }
                    return String(decoding:redacted,as:UTF8.self)
                }.joined(separator:"\n")
                structured=true
            } else { text="구조를 안전하게 확인할 수 없는 JSON 원문은 미리보기에 표시하지 않습니다." }
        } else if url.pathExtension.lowercased() == "jsonl" {
            var lines=String(decoding:bounded,as:UTF8.self).components(separatedBy:"\n")
            if limited { lines.removeLast() }
            text=lines.filter { !$0.isEmpty }.map { line in
                guard let object=try? JSONSerialization.jsonObject(with:Data(line.utf8),options:.fragmentsAllowed),let redacted=try? JSONSerialization.data(withJSONObject:EvidencePrivacy.json(object),options:[.sortedKeys,.fragmentsAllowed]) else { return "[구조를 확인할 수 없는 JSON 행은 표시하지 않습니다.]" }
                return String(decoding:redacted,as:UTF8.self)
            }.joined(separator:"\n")
            structured=true
        } else { text=raw }
        return (structured ? text : EvidencePrivacy.text(text))+(limited ? "\n\n[원문 미리보기는 128 KiB까지 표시합니다.]" : "")
    }
}

enum TaskDetailProjection {
    static func detail(_ record:TopologyRecord) -> TaskStepDetail {
        if let detail=record.detail { return detail }
        let text=EvidencePrivacy.text(record.text)
        let state:TaskStepDetail.State
        let summary:String
        switch record.kind {
        case .request: state = .completed; summary="요청을 접수했습니다. 아래 원문이 이번 작업의 범위입니다."
        case .plan: state = .completed; summary="요청을 수행할 계획을 정리했습니다. 계획 자체는 실행 완료를 뜻하지 않습니다."
        case .source: state = .completed; summary="단계에서 전달된 원문을 기록했습니다. 수집 범위와 원문은 근거에서 확인할 수 있습니다."
        case .decision: state = .completed; summary="다음 동작을 선택했습니다. 실제 실행 결과는 별도 단계에서 확인합니다."
        case .observation: state = .completed; summary="실제 관측한 정보를 기록했습니다."
        case .execution: state = .completed; summary="실행 단계에서 전달된 내용을 기록했습니다. 이 기록만으로 전체 요청 완료를 판단하지 않습니다."
        case .verification: state = .completed; summary="실행 후 확인한 근거를 기록했습니다."
        case .recovery: state = .partial; summary="진행 중 문제 또는 재시도 근거를 기록했습니다."
        case .commandOutput: state = .completed; summary="실제로 수신한 명령 출력을 기록했습니다."
        case .result: state = .completed; summary="결과를 받았습니다. 확인한 내용과 남은 항목은 아래 결과에 구분돼 있습니다."
        case .outcome: state = .completed; summary="실제 작업 종료 상태입니다."
        }
        return .init(id:"record-\(record.id)",title:record.title,summary:summary,state:state,
                     fields:[.init(label:record.kind == .request ? "요청 원문" : record.kind == .result ? "자연어 결과" : "이 단계의 기록 · 앞부분",value:record.kind == .result ? text : String(text.prefix(1200)))],
                     evidence:(record.evidencePaths ?? []).map { .init(file:$0,label:URL(fileURLWithPath:$0).lastPathComponent) })
    }
}
