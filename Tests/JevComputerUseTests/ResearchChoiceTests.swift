import Foundation
import XCTest
@testable import JevComputerUse

final class ResearchChoiceTests:XCTestCase {
    func testStartupConnectionPurposeIsSupportedAndRecordedSeparately() throws {
        XCTAssertEqual(ResearchChoicePurpose(rawValue:"connection"),.connection)
        XCTAssertNil(ResearchChoicePurpose(rawValue:"../other"))
        XCTAssertTrue(ResearchChoicePurpose.connection.instructions.contains("connection verification"))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        XCTAssertEqual(try ResearchChoiceEvidence.receive(body(1.0,"ready"),status:200,purpose:"connection",criteria:["ready":"Connection verification succeeded"],directory:root.path,startedAt:Date(),secrets:[]),"ready")
        let diagnostic=try JSONDecoder().decode(ResearchChoiceDiagnostic.self,from:Data(contentsOf:root.appendingPathComponent("connection-choice-diagnostic.json")))
        XCTAssertEqual(diagnostic.purpose,"connection");XCTAssertEqual(diagnostic.selected,"ready");XCTAssertNil(diagnostic.failure)
        let denied=ResearchChoiceFailure(purpose:"connection",code:.httpDenied,httpStatus:403)
        XCTAssertTrue(denied.description.contains("연결 확인"));XCTAssertFalse(denied.description.contains("출처 우선순위"));XCTAssertFalse(ResearchChoiceFailure(purpose:"connection",code:.lowConfidence).canKeepSearchOrder)
    }
    private let criteria=["source_0":"source","ask":"none"]
    private func body(_ confidence:Any = 0.9,_ choice:Any = "source_0") throws -> Data {
        try JSONSerialization.data(withJSONObject:["answers":["route":["choice":choice,"confidence":confidence]]])
    }
    private func assertFailure(_ data:Data,status:Int = 200,code:ResearchChoiceFailure.Code,file:StaticString = #filePath,line:UInt = #line) {
        XCTAssertThrowsError(try ResearchChoiceValidation.parse(data,status:status,purpose:"source",criteria:criteria),file:file,line:line) { error in
            XCTAssertEqual((error as? ResearchChoiceFailure)?.code,code,file:file,line:line)
        }
    }
    func testHTTPDenialAndLimitsDoNotBecomeWorkflowAmbiguity() throws {
        for status in [401,403] { assertFailure(try body(),status:status,code:.httpDenied) }
        assertFailure(try body(),status:429,code:.rateLimited);assertFailure(try body(),status:503,code:.httpFailure)
        XCTAssertTrue(ResearchChoiceFailure(purpose:"source",code:.httpDenied,httpStatus:403).description.contains("출처 우선순위"))
    }
    func testMalformedJSONAndSchemaAreDifferentFailures() throws {
        assertFailure(Data("<html>unavailable</html>".utf8),code:.invalidJSON)
        assertFailure(Data("{}".utf8),code:.invalidSchema)
        assertFailure(try body(0.9,0),code:.invalidSchema)
        assertFailure(try body(0.9,"outside"),code:.invalidChoice)
    }
    func testConfidenceBooleanStringsBoundsAndThreshold() throws {
        let values:[Any]=[true,false,"0.9",-0.1,1.1]
        for value in values { assertFailure(try body(value),code:.invalidConfidence) }
        assertFailure(try body(0.54),code:.lowConfidence)
        XCTAssertEqual(try ResearchChoiceValidation.parse(body(0.55),status:200,purpose:"source",criteria:criteria).0,"source_0")
    }
    func testOnlySourceLowConfidenceCanRetainReceivedSearchOrder() {
        XCTAssertTrue(ResearchChoiceFailure(purpose:"source",code:.lowConfidence).canKeepSearchOrder)
        XCTAssertFalse(ResearchChoiceFailure(purpose:"workflow",code:.lowConfidence).canKeepSearchOrder)
        let codes:[ResearchChoiceFailure.Code]=[.httpDenied,.invalidJSON,.invalidSchema,.invalidChoice,.invalidConfidence,.transport,.timeout,.rateLimited]
        for code in codes {
            XCTAssertFalse(ResearchChoiceFailure(purpose:"source",code:code).canKeepSearchOrder)
        }
    }
    func testRejectedHTTPAndLowConfidenceResponsesArePreservedBeforeThrowing() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:root)}
        for (index,status) in [403,200].enumerated() {
            let dir=root.appendingPathComponent(String(index));try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            XCTAssertThrowsError(try ResearchChoiceEvidence.receive(body(0.1),status:status,purpose:"source",criteria:criteria,directory:dir.path,startedAt:Date(),secrets:[]))
            XCTAssertTrue(FileManager.default.fileExists(atPath:dir.appendingPathComponent("source-jev.json").path))
            let diagnostic=try JSONDecoder().decode(ResearchChoiceDiagnostic.self,from:Data(contentsOf:dir.appendingPathComponent("source-choice-diagnostic.json")))
            XCTAssertEqual(diagnostic.failure,status == 403 ? .httpDenied : .lowConfidence)
            XCTAssertNotNil(diagnostic.responseSHA256);XCTAssertNotNil(diagnostic.redactedResponseSHA256)
        }
    }
    func testResponseRedactionKeepsChoiceButMasksCredentialsAndPrivateReasoning() throws {
        let data=try JSONSerialization.data(withJSONObject:["answers":["route":["choice":"source_0","confidence":0.9]],"authorization":"Bearer abcprivate","analysis":"hidden-private-text","other":"KNOWN_PRIVATE"])
        let redacted=EvidencePrivacy.response(data,secrets:["KNOWN_PRIVATE"]),text=String(decoding:redacted,as:UTF8.self)
        XCTAssertFalse(text.contains("abcprivate"));XCTAssertFalse(text.contains("hidden-private-text"));XCTAssertFalse(text.contains("KNOWN_PRIVATE"))
        XCTAssertEqual(try ResearchChoiceValidation.parse(redacted,status:200,purpose:"source",criteria:criteria).0,"source_0")
        let urls=EvidencePrivacy.text("https://u:private@example.org/a?token=secret&x=ok")
        XCTAssertFalse(urls.contains("private"));XCTAssertFalse(urls.contains("secret"))
    }
    func testEvidenceIOFailureDoesNotBecomeRecoverableConfidenceFailure() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try Data().write(to:file);defer {try? FileManager.default.removeItem(at:file)}
        XCTAssertThrowsError(try ResearchChoiceEvidence.receive(body(0.1),status:200,purpose:"source",criteria:criteria,directory:file.path,startedAt:Date(),secrets:[])) { error in
            XCTAssertNil(error as? ResearchChoiceFailure)
        }
    }
}
