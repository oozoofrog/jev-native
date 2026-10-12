import Foundation
import XCTest
@testable import JevComputerUse

@MainActor final class ResearchFlowTests:XCTestCase {
    private func directory() throws -> String {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url.path
    }
    private func runner(_ fetches: @escaping (String) async throws -> (String,URL)) -> ResearchRunner {
        let runner=ResearchRunner()
        runner.search = { _ in (0..<8).map { ("Recorded candidate \($0)","https://example.org/source/\($0)") } }
        runner.fetch=fetches
        runner.delegate = { _,directory,_,_ in
            let handoff=directory.hasSuffix("query") ? Handoff(text:"bounded query",observation:"",actions:[]) : Handoff(text:#"{"summary":"Collected evidence [S1]","events":[],"questions":[]}"#,observation:"",actions:[])
            try writeJSON(handoff,directory+"/codex-result.json");return handoff
        }
        return runner
    }
    private func page(_ url:String) -> (String,URL) { ("<p>"+String(repeating:"Public observed source text. ",count:8)+"</p>",URL(string:url)!) }
    func testReceivedEightResultsLowConfidenceRankingContinuesToActualSourceCollection() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var fetched:[String]=[],state=RunPresentationState();let control=RunControl();control.onPresentation={state.apply($0)};control.emit(.request("owned public research"))
        let runner=runner { url in fetched.append(url);return self.page(url) }
        runner.choice = { _,_,_,name in throw ResearchChoiceFailure(purpose:name,code:.lowConfidence,confidence:0.3) }
        let plan=try await runner.prepare(request:"owned public research",calendar:false,directory:dir,model:nil,control:control)
        XCTAssertEqual(fetched.count,4);XCTAssertEqual(fetched.first,"https://example.org/source/0")
        XCTAssertEqual(plan.sources.count,4);XCTAssertTrue(plan.summary.contains("[S1]"))
        XCTAssertEqual(state.topology.first { $0.detail?.id=="source-priority" }?.detail?.state,.partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath:dir+"/research-plan.json"))
    }
    func testDeniedMalformedTransportAndTimeoutRankingDoNotFetchOrFallback() async throws {
        for code in [ResearchChoiceFailure.Code.httpDenied,.invalidJSON,.transport,.timeout] {
            let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
            var fetched=0;let runner=runner { url in fetched+=1;return self.page(url) }
            runner.choice={ _,_,_,name in throw ResearchChoiceFailure(purpose:name,code:code,httpStatus:code == .httpDenied ? 403 : nil) }
            do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:RunControl());XCTFail("Must stop") }
            catch { XCTAssertEqual((error as? ResearchChoiceFailure)?.code,code) }
            XCTAssertEqual(fetched,0);XCTAssertFalse(FileManager.default.fileExists(atPath:dir+"/sources.json"))
        }
    }
    func testAskDoesNotPretendARelevantSourceWasFound() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var fetched=0;let runner=runner { url in fetched+=1;return self.page(url) };runner.choice={ _,_,_,_ in "ask" }
        do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:RunControl());XCTFail() } catch { XCTAssertTrue(String(describing:error).contains("관련 출처")) }
        XCTAssertEqual(fetched,0)
    }
    func testCancellationDoesNotBecomeOptionalRankingRecovery() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var fetched=0;let runner=runner { url in fetched+=1;return self.page(url) };runner.choice={ _,_,_,_ in throw CancellationError() }
        do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:RunControl());XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fetched,0)
    }
    func testFetchCancellationStopsFurtherSources() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var fetched=0;let runner=runner { _ in fetched+=1;throw CancellationError() };runner.choice={ _,_,_,_ in "source_0" }
        do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:RunControl());XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fetched,1)
    }
    func testFailedSourcesAreRecordedAndComparisonCycleFollowsActualAttempts() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var count=0,state=RunPresentationState();let control=RunControl();control.onPresentation={state.apply($0)};control.emit(.request("owned"))
        let runner=runner { url in count+=1;if count<=2 { throw Failure("HTTP403 fixture: source unavailable, no bypass") };return self.page(url) };runner.choice={ _,_,_,_ in "source_0" }
        let plan=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:control)
        XCTAssertEqual(count,6);XCTAssertEqual(plan.sources.count,4);XCTAssertEqual(state.cycle,7)
        XCTAssertEqual(state.topology.filter { $0.detail?.state == .failed }.count,2)
        XCTAssertEqual(state.topology.first { $0.detail?.id=="fetch-3" }?.cycle,3)
    }
    func testDuplicateFinalSourceGetsFinishedPartialDetailNotPermanentRunning() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var count=0,state=RunPresentationState();let control=RunControl();control.onPresentation={state.apply($0)};control.emit(.request("owned"))
        let runner=runner { url in count+=1;return self.page(count==2 ? "https://example.org/source/0" : url) };runner.choice={ _,_,_,_ in "source_0" }
        _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:control)
        XCTAssertEqual(state.topology.first { $0.detail?.id=="fetch-2" }?.detail?.state,.partial)
        XCTAssertFalse(state.topology.contains { $0.detail?.state == .running })
    }
    func testRankingEvidenceIOErrorStopsInsteadOfFallingBack() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        var fetched=0;let runner=runner { url in fetched+=1;return self.page(url) };runner.choice={ _,_,_,_ in throw CocoaError(.fileWriteNoPermission) }
        do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:RunControl());XCTFail() } catch { XCTAssertEqual((error as NSError).domain,NSCocoaErrorDomain) }
        XCTAssertEqual(fetched,0)
    }
    func testStopDuringLowConfidenceSelectionPreventsRecoveryFetch() async throws {
        let dir=try directory();defer {try? FileManager.default.removeItem(atPath:dir)}
        let control=RunControl();var fetched=0
        let runner=runner { url in fetched+=1;return self.page(url) }
        runner.choice={ _,_,_,name in control.stop();throw ResearchChoiceFailure(purpose:name,code:.lowConfidence,confidence:0.2) }
        do { _=try await runner.prepare(request:"owned",calendar:false,directory:dir,model:nil,control:control);XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fetched,0)
    }
}
