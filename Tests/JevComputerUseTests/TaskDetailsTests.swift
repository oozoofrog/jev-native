import AppKit
import Foundation
import XCTest
@testable import JevComputerUse

final class TaskDetailsTests:XCTestCase {
    @MainActor func testResearchResultSelectionRemainsVisibleWithNaturalLanguageAnswer() {
        let id=UUID();var state=RunPresentationState()
        state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"search",title:"검색",summary:"8개 수신",state:.completed))))
        let answer=String(repeating:"확인한 자료의 자연어 결과입니다. ",count:100)+"END_PUBLIC_ANSWER"
        state.apply(.init(runID:id,sequence:2,fact:.result(answer)))
        let result=state.topology.first { $0.kind == .result }!
        XCTAssertEqual(TaskDetailProjection.detail(result).fields.first?.value,answer)
        let view=TaskDetailView(state:state,directory:nil,selectedRecord:result.id)
        func texts(_ v:NSView) -> [String] { (v as? NSTextField).map { [$0.stringValue] } ?? v.subviews.flatMap(texts) }
        let rendered=texts(view).joined(separator:"\n")
        XCTAssertTrue(rendered.contains("선택한 단계"));XCTAssertTrue(rendered.contains("자연어 결과"));XCTAssertTrue(rendered.contains("END_PUBLIC_ANSWER"))
    }
    func testReasoningEventTypeCannotLeakThroughApprovedLocalLogRead() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let raw="{\"type\":\"item.completed\",\"item\":{\"type\":\"reasoning\",\"text\":\"PRIVATE_REASONING\"},\"public\":\"actual metadata\"}"
        for file in ["events.jsonl","stdout.log"] {
            try Data(raw.utf8).write(to:root.appendingPathComponent(file))
            let preview=try TaskEvidenceFiles.preview(file,directory:root.path)
            XCTAssertFalse(preview.contains("PRIVATE_REASONING"));XCTAssertTrue(preview.contains("actual metadata"))
        }
        let mixed="command output\n"+raw
        try Data(mixed.utf8).write(to:root.appendingPathComponent("mixed.log"))
        XCTAssertFalse(try TaskEvidenceFiles.preview("mixed.log",directory:root.path).contains("PRIVATE_REASONING"))
        XCTAssertFalse(EvidencePrivacy.text(raw).contains("PRIVATE_REASONING"))
    }
    func testFailureAfterCompletedResearchStepKeepsVisibleReason() {
        let id=UUID();var state=RunPresentationState()
        state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"search",title:"검색",summary:"8개 수신",state:.completed))))
        state.apply(.init(runID:id,sequence:2,fact:.failure("sources.json 저장 실패")))
        state.apply(.init(runID:id,sequence:3,fact:.outcome("error")))
        let failures=state.topology.compactMap(\.detail).filter { $0.state == .failed }
        XCTAssertTrue(failures.contains { $0.summary.contains("sources.json 저장 실패") })
        XCTAssertEqual(state.topology.first { $0.detail?.id == "search" }?.detail?.state,.completed)
    }
    func testStructuredPreviewMasksSecretsAndReasoningAndRefusesIncompleteJSON() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let raw="{\"api_key\":\"PRIVATE_VALUE\",\"analysis\":\"PRIVATE_REASONING\",\"answer\":\"public\"}"
        for file in ["old.json","events.jsonl","stdout.log"] {
            try Data(raw.utf8).write(to:root.appendingPathComponent(file))
            let preview=try TaskEvidenceFiles.preview(file,directory:root.path)
            XCTAssertFalse(preview.contains("PRIVATE_VALUE"));XCTAssertFalse(preview.contains("PRIVATE_REASONING"));XCTAssertTrue(preview.contains("public"))
        }
        try Data(("command output\n"+raw).utf8).write(to:root.appendingPathComponent("mixed.log"))
        let mixed=try TaskEvidenceFiles.preview("mixed.log",directory:root.path)
        XCTAssertFalse(mixed.contains("PRIVATE_VALUE"));XCTAssertFalse(mixed.contains("PRIVATE_REASONING"));XCTAssertTrue(mixed.contains("표시하지 않습니다"))
        try Data("command output\n{\n \"analysis\": {\n  \"steps\": [\"PRIVATE_REASONING\"]\n },\n \"answer\":\"public\"\n}".utf8).write(to:root.appendingPathComponent("nested-mixed.log"))
        let nested=try TaskEvidenceFiles.preview("nested-mixed.log",directory:root.path)
        XCTAssertFalse(nested.contains("PRIVATE_REASONING"));XCTAssertTrue(nested.contains("표시하지 않습니다"))
        for value in ["command output\n{\"api_key\":\"PRIVATE_VALUE", "command output\n{\"analysis\":\""+String(repeating:"PRIVATE_REASONING",count:10000)] {
            try Data(value.utf8).write(to:root.appendingPathComponent("incomplete-mixed.log"))
            let preview=try TaskEvidenceFiles.preview("incomplete-mixed.log",directory:root.path)
            XCTAssertFalse(preview.contains("PRIVATE_VALUE"));XCTAssertFalse(preview.contains("PRIVATE_REASONING"));XCTAssertTrue(preview.contains("표시하지 않습니다"))
        }
        for rawValue in ["{\"password\":\"PRIVATE_VALUE\"", "{\"analysis\":\""+String(repeating:"PRIVATE_REASONING",count:10000)+"\"}"] {
            try Data(rawValue.utf8).write(to:root.appendingPathComponent("incomplete.json"))
            let preview=try TaskEvidenceFiles.preview("incomplete.json",directory:root.path)
            XCTAssertFalse(preview.contains("PRIVATE_VALUE"));XCTAssertFalse(preview.contains("PRIVATE_REASONING"));XCTAssertTrue(preview.contains("표시하지 않습니다"))
        }
    }
    private func directory() throws -> URL { let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url }
    func testStartedAndCompletedDetailKeepIdentityAndActualTimes() {
        let id=UUID(),first=Date(timeIntervalSince1970:100),last=Date(timeIntervalSince1970:105);var state=RunPresentationState()
        state.apply(.init(runID:id,sequence:0,fact:.request("owned"),recordedAt:first))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"search",title:"검색",summary:"요청 준비",state:.running)),recordedAt:first))
        state.apply(.init(runID:id,sequence:2,fact:.detail(.init(id:"search",title:"검색",summary:"8개 수신",state:.completed)),recordedAt:last))
        let record=state.topology.first { $0.detail?.id=="search" }
        XCTAssertEqual(state.topology.filter { $0.detail?.id=="search" }.count,1);XCTAssertEqual(record?.recordedAt,first);XCTAssertEqual(record?.updatedAt,last);XCTAssertEqual(record?.detail?.state,.completed)
    }
    func testActualFailureMarksRunningStepWithoutInventingNextActivity() {
        let id=UUID();var state=RunPresentationState();state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"source-priority",title:"출처 선택",summary:"응답 대기",state:.running))))
        state.apply(.init(runID:id,sequence:2,fact:.failure("HTTP403")));state.apply(.init(runID:id,sequence:3,fact:.outcome("error")))
        XCTAssertEqual(state.topology.first { $0.detail?.id=="source-priority" }?.detail?.state,.failed)
        XCTAssertFalse(state.topology.contains { $0.detail?.id=="fetch-1" });XCTAssertEqual(state.topology.last?.detail?.state,.failed)
    }
    func testCancellationIsShownAsCancellationNotSuccessfulOrFailedWork() {
        let id=UUID();var state=RunPresentationState();state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"query",title:"검색어",summary:"준비",state:.running))))
        state.apply(.init(runID:id,sequence:2,fact:.outcome("cancelled")))
        XCTAssertEqual(state.topology.first { $0.detail?.id=="query" }?.detail?.state,.cancelled)
    }
    func testFailedLocalReportCannotLeaveCommandMarkedRunningOrSuccess() {
        let id=UUID();var state=RunPresentationState();state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"command-1",title:"로컬 명령",summary:"시작",state:.running))))
        state.apply(.init(runID:id,sequence:2,fact:.outcome("local_failed")))
        XCTAssertEqual(state.topology.first { $0.detail?.id=="command-1" }?.detail?.state,.failed)
        XCTAssertEqual(state.topology.last?.detail?.state,.failed)
    }
    func testEvidenceOnlyReadsFilesInsideSelectedRunAndRejectsAliases() throws {
        let root=try directory(),outside=try directory();defer {try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:outside)}
        try Data("owned".utf8).write(to:root.appendingPathComponent("source.txt"));try Data("private".utf8).write(to:outside.appendingPathComponent("private.txt"))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("alias"),withDestinationURL:outside.appendingPathComponent("private.txt"))
        XCTAssertEqual(try TaskEvidenceFiles.preview("source.txt",directory:root.path),"owned")
        for file in ["../private.txt",outside.appendingPathComponent("private.txt").path,"alias"] { XCTAssertThrowsError(try TaskEvidenceFiles.resolve(file,directory:root.path)) }
    }
    func testRawPreviewIsBoundedAndMasksBearerValues() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        try Data(("Bearer PRIVATE_TOKEN "+String(repeating:"a",count:140000)).utf8).write(to:root.appendingPathComponent("raw.log"))
        let preview=try TaskEvidenceFiles.preview("raw.log",directory:root.path);XCTAssertFalse(preview.contains("PRIVATE_TOKEN"));XCTAssertTrue(preview.contains("128 KiB"))
    }
    @MainActor func testJournalPersistsActualEventsAndCannotOverwriteExistingRun() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        let control=RunControl();try control.recordEvents(in:root.path);control.emit(.request("owned Bearer PRIVATE_TOKEN"));control.emit(.detail(.init(id:"search",title:"검색",summary:"응답 준비",state:.running)));control.emit(.failure("HTTP403"));control.emit(.outcome("error"))
        let text=try String(contentsOf:root.appendingPathComponent("task-events.jsonl"));XCTAssertFalse(text.contains("PRIVATE_TOKEN"))
        let restored=try TaskHistory.load(root.path);XCTAssertEqual(restored.outcome,"error");XCTAssertEqual(restored.topology.first { $0.detail?.id=="search" }?.detail?.state,.failed)
        XCTAssertThrowsError(try RunControl().recordEvents(in:root.path))
    }
    func testMixedRunJournalAndOutOfOrderJournalAreRejected() throws {
        for mixed in [true,false] {
            let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
            let id=UUID(),events=[RunPresentationEvent(runID:id,sequence:0,fact:.request("first")),RunPresentationEvent(runID:mixed ? UUID() : id,sequence:mixed ? 1 : 0,fact:.outcome("error"))]
            var data=Data();for event in events { data.append(try JSONEncoder().encode(event));data.append(10) };try data.write(to:root.appendingPathComponent("task-events.jsonl"))
            XCTAssertThrowsError(try TaskHistory.load(root.path))
        }
    }
    func testLegacySummaryDoesNotInventMissingSourceRankingOrExactTime() throws {
        let root=try directory();defer {try? FileManager.default.removeItem(at:root)}
        try writeJSON(RunReport(status:"error",goal:"owned original",steps:[],finalObservation:"",directory:"/untrusted/serialized/path",error:"old generic failure"),root.path+"/report.json")
        try writeJSON([["title":"recorded result","url":"https://example.org/a"]],root.path+"/search-results.json")
        let state=try TaskHistory.load(root.path)
        XCTAssertEqual(state.request,"owned original");XCTAssertEqual(state.outcome,"error")
        XCTAssertTrue(state.topology.allSatisfy { $0.timeSource?.contains("파일 수정 시각")==true })
        XCTAssertTrue(state.topology.contains { $0.detail?.id=="legacy-diagnostic-gap" });XCTAssertFalse(state.topology.contains { $0.detail?.id=="fetch-1" })
    }
    @MainActor func testNativeDetailViewHasNaturalStepsStatusEvidenceAndNoPercentProgress() throws {
        let id=UUID();var state=RunPresentationState();state.apply(.init(runID:id,sequence:0,fact:.request("owned")))
        state.apply(.init(runID:id,sequence:1,fact:.detail(.init(id:"search",title:"공개 웹 검색",summary:"실제로 결과 8개를 받았습니다.",state:.completed,fields:[.init(label:"검색어",value:"owned query")],evidence:[.init(file:"search-results.json",label:"실제 검색 결과")]))))
        let view=TaskDetailView(state:state,directory:"/fixture-workspace/owned")
        func text(_ view:NSView) -> [String] { (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(text) }
        let labels=text(view).joined(separator:"\n");XCTAssertTrue(labels.contains("실제 작업 상세"));XCTAssertTrue(labels.contains("실제로 결과 8개"));XCTAssertTrue(labels.contains("검색어"));XCTAssertFalse(labels.contains("%"))
        func buttons(_ view:NSView) -> [String] { (view as? NSButton).map { [$0.title] } ?? view.subviews.flatMap(buttons) }
        XCTAssertTrue(buttons(view).contains("근거 · 실제 검색 결과"))
    }
}
