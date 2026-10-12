import XCTest
@testable import JevComputerUse

final class LocalTaskTests:XCTestCase {
    func testMissingOptionalPlannerMetadataUsesDefaultsAndKeepsRequiredFields() throws {
        let raw = #"{"summary":"Mixed","steps":[{"kind":"command","command":{"tool":"pwd","arguments":[],"directory":"/fixture"}},{"kind":"native","nativeRequest":"Open owned file in TextEdit"}]}"#
        let plan = try JSONDecoder().decode(LocalTaskPlan.self,from:Data(raw.utf8))
        XCTAssertEqual(plan.steps[0].reason,"요청한 로컬 명령")
        XCTAssertEqual(plan.steps[0].command?.timeoutSeconds,300)
        XCTAssertEqual(plan.steps[1].reason,"요청한 앱 작업")
        XCTAssertNil(plan.steps[1].command)
        XCTAssertThrowsError(try JSONDecoder().decode(LocalCommandSpec.self,from:Data(#"{"tool":"pwd","directory":"/fixture"}"#.utf8)))
    }

    private func directory() throws -> URL {
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at:r,withIntermediateDirectories:true); addTeardownBlock { try? FileManager.default.removeItem(at:r) }; return r
    }
    private func command(_ tool:String = "pwd",_ args:[String] = [],_ root:URL) -> LocalTaskStep {
        .init(kind:"command",reason:"requested query",command:.init(tool:tool,arguments:args,directory:root.path),nativeRequest:nil)
    }
    private func command(_ root:URL) -> LocalTaskStep { command("pwd",[],root) }
    @MainActor func testRejectedPlanNeverSpawnsAndPreservesDiagnostic() async throws {
        let r = try directory(),process = LocalProcessRunner(); var spawns = 0
        process.onStart = { _ in spawns += 1 }
        let runner = LocalTaskRunner(judge:{_,_,_,_,_,_ in "outside"},process:process)
        let report = try await runner.run(request:"owned",workspace:r.path,directory:r.path+"/run",model:nil,control:RunControl(),suppliedPlan:.init(summary:"owned",steps:[command(r)]))
        XCTAssertEqual(report.status,"local_failed"); XCTAssertEqual(spawns,0); XCTAssertTrue(report.localCommands?.isEmpty == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath:r.path+"/run/local-plan.json"))
    }
    @MainActor func testFailedCommandStopsBeforeNextCommandAndNativeStep() async throws {
        let r = try directory(); var nativeCalls = 0,judgments = 0
        let runner = LocalTaskRunner(judge:{_,_,_,_,_,_ in judgments += 1; return "fits"})
        let plan = LocalTaskPlan(summary:"owned",steps:[command("cat",["missing-file"],r),command(r),.init(kind:"native",reason:"owned",command:nil,nativeRequest:"owned GUI")])
        let report = try await runner.run(request:"owned",workspace:r.path,directory:r.path+"/run",model:nil,control:RunControl(),suppliedPlan:plan,native:{_,_,_ in nativeCalls += 1; throw Failure("must not execute")})
        XCTAssertEqual(report.status,"local_failed"); XCTAssertEqual(report.localCommands?.count,1); XCTAssertEqual(nativeCalls,0); XCTAssertEqual(judgments,1)
        XCTAssertNotEqual(report.localCommands?.first?.exitCode,0)
    }
    @MainActor func testPauseBeforeStartResumesAndCannotSkipVerification() async throws {
        let r = try directory(),control = RunControl(); control.requestPause()
        let runner = LocalTaskRunner(judge:{_,_,_,_,name,_ in name == "local-plan-fit" ? "fits" : "partial"})
        let task = Task { @MainActor in try await runner.run(request:"owned",workspace:r.path,directory:r.path+"/run",model:nil,control:control,suppliedPlan:.init(summary:"owned",steps:[command(r)])) }
        try await Task.sleep(nanoseconds:100_000_000)
        XCTAssertTrue(control.isPaused); XCTAssertFalse(FileManager.default.fileExists(atPath:r.path+"/run/command-1"))
        control.resume(); let report = try await task.value
        XCTAssertEqual(report.status,"local_partial"); XCTAssertEqual(report.localCommands?.count,1)
    }
    @MainActor func testHybridExecutionUsesDistinctCyclesAndRetainsBothEvidenceLanes() async throws {
        let r = try directory(),control = RunControl(); var state = RunPresentationState()
        control.onPresentation = { state.apply($0) }; control.emit(.request("owned hybrid"))
        let runner = LocalTaskRunner(judge:{_,_,_,_,name,_ in name == "local-plan-fit" ? "fits" : "complete"})
        let plan = LocalTaskPlan(summary:"owned",steps:[command(r),.init(kind:"native",reason:"owned",command:nil,nativeRequest:"owned GUI"),command(r)])
        let report = try await runner.run(request:"owned hybrid",workspace:r.path,directory:r.path+"/run",model:nil,control:control,suppliedPlan:plan,native:{_,dir,control in
            control.emit(.cycle(1)); control.emit(.input("owned native input")); control.emit(.cycleEnd(1))
            control.emit(.cycle(2)); control.emit(.verification("owned native verification")); control.emit(.cycleEnd(2))
            return RunReport(status:"verified_complete",goal:"owned GUI",steps:[.init(index:1,observation:"owned")],finalObservation:"owned",directory:dir)
        })
        XCTAssertEqual(report.status,"local_complete"); XCTAssertEqual(report.localCommands?.count,2); XCTAssertEqual(report.steps.count,1)
        XCTAssertEqual(state.localCommands,2); XCTAssertEqual(state.inputs,1)
        XCTAssertEqual(state.completedCycles,[1,2,3,4]); XCTAssertEqual(state.cycle,4)
        XCTAssertEqual(Set(state.topology.map(\.id)).count,state.topology.count)
    }
    @MainActor func testUnresolvedNativeStepRetainsCompletedCLIOutput() async throws {
        let r = try directory()
        try "CLI 한글 결과\n".write(to:r.appendingPathComponent("source.txt"),atomically:true,encoding:.utf8)
        let runner = LocalTaskRunner(judge:{_,_,_,_,_,_ in "fits"})
        let plan = LocalTaskPlan(summary:"mixed",steps:[command("cat",["source.txt"],r),.init(kind:"native",reason:"requested",command:nil,nativeRequest:"owned GUI")])
        let report = try await runner.run(request:"owned hybrid",workspace:r.path,directory:r.path+"/run",model:nil,control:RunControl(),suppliedPlan:plan,native:{request,dir,_ in
            RunReport(status:"request_needs_input",goal:request,steps:[],finalObservation:"",directory:dir,response:"필수 대상이 확정되지 않았습니다.")
        })
        XCTAssertEqual(report.status,"local_partial"); XCTAssertEqual(report.localCommands?.count,1)
        XCTAssertTrue(report.response?.contains("CLI 한글 결과") == true)
        XCTAssertTrue(report.response?.contains("필수 대상이 확정되지 않았습니다.") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath:report.localCommands!.first!.stdoutPath))
    }
    @MainActor func testCompletionReceivesNativeObservationInsteadOfOnlyStatus() async throws {
        let r = try directory(); var sawObservation = false
        let runner = LocalTaskRunner(judge:{_,evidence,_,_,name,_ in
            if name == "local-plan-fit" { return "fits" }
            let native = ((evidence as? [String:Any])?["nativeResults"] as? [[String:Any]])?.first
            let text = native?["observedText"] as? String ?? ""
            sawObservation = native?["observationAvailable"] as? Bool == true && text.contains("result=small")
            XCTAssertFalse(text.contains("PRIVATE_MENU")); return sawObservation ? "complete" : "partial"
        })
        let plan = LocalTaskPlan(summary:"mixed",steps:[command(r),.init(kind:"native",reason:"requested",command:nil,nativeRequest:"owned GUI")])
        let report = try await runner.run(request:"owned hybrid",workspace:r.path,directory:r.path+"/run",model:nil,control:RunControl(),suppliedPlan:plan,native:{request,dir,_ in
            let observation = Observation(id:"owned",timestamp:Date(),front:nil,apps:[],nodes:[Node(id:"1",role:"AXStaticText",title:"Fixture result",value:"result=small",enabled:true,actions:[],frame:nil),Node(id:"2",role:"AXMenuItem",title:"PRIVATE_MENU",value:"",enabled:true,actions:[],frame:nil)],displays:[],truncated:false,axError:nil,elapsedMS:0)
            try writeJSON(observation,dir+"/observation.json")
            return RunReport(status:"jev_observed_complete",goal:request,steps:[],finalObservation:dir+"/observation.json",directory:dir,completionSource:"jev")
        })
        XCTAssertTrue(sawObservation); XCTAssertEqual(report.status,"local_complete")
        XCTAssertTrue(report.response?.contains("result=small") == true)
    }
    @MainActor func testUnsupportedLaterStepIsRejectedBeforeAnyCommand() async throws {
        let r = try directory(); var judgments = 0
        let runner = LocalTaskRunner(judge:{_,_,_,_,_,_ in judgments += 1; return "fits"})
        let plan = LocalTaskPlan(summary:"owned",steps:[command(r),command("sh",["-c","true"],r)])
        let report = try await runner.run(request:"owned",workspace:r.path,directory:r.path+"/run",model:nil,control:RunControl(),suppliedPlan:plan)
        XCTAssertEqual(report.status,"local_failed"); XCTAssertEqual(judgments,0); XCTAssertTrue(report.localCommands?.isEmpty == true)
    }
}
