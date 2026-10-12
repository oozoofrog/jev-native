import XCTest
import AppKit
import Darwin
@testable import JevComputerUse

final class LocalCommandTests:XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("JEV CLI 한글 "+UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return URL(fileURLWithPath:LocalCommandPolicy.canonical(url.path,relativeTo:"/"))
    }
    private func policy(_ root:URL) -> LocalCommandPolicy { .init(workspace:root.path,runDirectory:root.appendingPathComponent("run").path,tools:LocalTools.discover()) }
    private func spec(_ tool:String,_ args:[String],_ root:URL) -> LocalCommandSpec { .init(tool:tool,arguments:args,directory:root.path) }
    /// Shell is used only as an owned subprocess fixture, never through production policy.
    private func fixture(_ script:String,_ root:URL,timeout:Double = 5) -> ValidatedLocalCommand {
        .init(spec:.init(tool:"owned-fixture",arguments:[],directory:root.path,timeoutSeconds:timeout),executable:"/bin/sh",arguments:["-c",script],directory:root.path,environment:["PATH":"/usr/bin:/bin"],expectedFiles:[],successExitCodes:[0])
    }
    func testPolicyRejectsInterpretersUnsafeOptionsAndEscapingPaths() throws {
        let r = try root(),p = policy(r)
        for (tool,args) in [("sh",["-c","true"]),("env",["sh"]),("git",["config","x","y"]),("git",["-c","alias.x=!true","x"]),("rg",["--pre","/bin/sh","x"]),("swift",["-e","print(1)"]),("xcrun",["--run","sh"]),("xcodebuild",["install"])] {
            XCTAssertThrowsError(try p.validate(spec(tool,args,r)),tool)
        }
        XCTAssertThrowsError(try p.validate(spec("cat",["../outside.txt"],r)))
        let outside = r.deletingLastPathComponent().appendingPathComponent("other-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:outside) }
        try FileManager.default.createSymbolicLink(at:r.appendingPathComponent("escape"),withDestinationURL:outside)
        XCTAssertThrowsError(try p.validate(spec("cat",["escape/file.txt"],r)))
        var env = spec("pwd",[],r); env.environment = ["PATH":"/tmp"]
        XCTAssertThrowsError(try p.validate(env))
    }
    func testPolicyStripsCredentialsAndAllowsOnlyMeaningfulNonzeroExits() throws {
        let r = try root(),p = policy(r)
        let valid = try p.validate(spec("pwd",[],r))
        for name in ["TYPESAFE_API_KEY","OPENAI_API_KEY","AWS_SECRET_ACCESS_KEY","GITHUB_TOKEN","DYLD_INSERT_LIBRARIES"] { XCTAssertNil(valid.environment[name]) }
        var search = spec("rg",["missing","."],r); search.successExitCodes = [0,1]
        if p.tools.contains(where:{$0.name == "rg"}) { XCTAssertEqual(try p.validate(search).successExitCodes,[0,1]) }
        var cat = spec("cat",[],r); cat.successExitCodes = [1]
        XCTAssertThrowsError(try p.validate(cat))
    }
    @MainActor func testLiteralArgumentsUnicodeAndWorkingDirectoryAreNotShellEvaluated() async throws {
        let r = try root(),file = r.appendingPathComponent("문서 ' $(touch INJECTED).txt")
        let text = "한글🙂와 작은따옴표를 그대로 전달합니다.\n"
        try text.write(to:file,atomically:true,encoding:.utf8)
        var input = spec("cat",[file.lastPathComponent],r); input.expectedStdout = "한글🙂"
        let valid = try policy(r).validate(input),runner = LocalProcessRunner()
        let output = try await runner.run(valid,index:1,directory:r.path+"/run",control:RunControl())
        XCTAssertTrue(output.succeeded); XCTAssertEqual(output.exitCode,0)
        XCTAssertEqual(try String(contentsOfFile:output.stdoutPath,encoding:.utf8),text)
        XCTAssertFalse(FileManager.default.fileExists(atPath:r.path+"/INJECTED"))
        let attrs = try FileManager.default.attributesOfItem(atPath:output.stdoutPath)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue,0o600)
        let saved = try JSONDecoder().decode(LocalCommandResult.self,from:Data(contentsOf:r.appendingPathComponent("run/result.json")))
        XCTAssertEqual(saved,output)
    }
    @MainActor func testLargeStdoutAndStderrStreamWithoutPipeDeadlock() async throws {
        let r = try root(),runner = LocalProcessRunner(); var samples:[LocalOutputSnapshot] = []
        runner.onOutput = { samples.append($0) }
        let output = try await runner.run(fixture("i=0; while [ $i -lt 12000 ]; do printf 'stdout 한글🙂 %s\\n' \"$i\"; printf 'stderr 한글🙂 %s\\n' \"$i\" >&2; i=$((i+1)); done",r),index:1,directory:r.path+"/run",control:RunControl())
        XCTAssertTrue(output.succeeded); XCTAssertGreaterThan(output.stdoutBytes,65536); XCTAssertGreaterThan(output.stderrBytes,65536)
        XCTAssertGreaterThanOrEqual(samples.count,2)
        XCTAssertTrue(try String(contentsOfFile:output.stdoutPath,encoding:.utf8).hasSuffix("11999\n"))
        XCTAssertTrue(try String(contentsOfFile:output.stderrPath,encoding:.utf8).contains("한글🙂"))
    }
    @MainActor func testNonzeroAndMissingExpectedArtifactAreFailures() async throws {
        let r = try root(),runner = LocalProcessRunner()
        let failed = try await runner.run(fixture("printf 'actual failure' >&2; exit 7",r),index:1,directory:r.path+"/fail",control:RunControl())
        XCTAssertFalse(failed.succeeded); XCTAssertEqual(failed.exitCode,7); XCTAssertEqual(failed.termination,"exited")
        var expected = spec("pwd",[],r); expected.expectedFiles = ["missing-result.txt"]
        let missing = try await runner.run(policy(r).validate(expected),index:2,directory:r.path+"/missing",control:RunControl())
        XCTAssertFalse(missing.succeeded); XCTAssertEqual(missing.exitCode,0); XCTAssertTrue(missing.files.isEmpty)
    }
    @MainActor func testOutputLimitAndTimeoutPreserveEvidence() async throws {
        let r = try root(),runner = LocalProcessRunner(); runner.maximumOutputBytes = 1024
        let output = try await runner.run(fixture("i=0; while [ $i -lt 4000 ]; do printf 'many bytes of output\\n'; i=$((i+1)); done; sleep 10",r),index:1,directory:r.path+"/limit",control:RunControl())
        XCTAssertFalse(output.succeeded); XCTAssertEqual(output.termination,"output_limit"); XCTAssertGreaterThan(output.stdoutBytes,1024)
        let timed = try await runner.run(fixture("trap '' TERM; sleep 20 & wait",r,timeout:0.25),index:2,directory:r.path+"/timeout",control:RunControl())
        XCTAssertFalse(timed.succeeded); XCTAssertEqual(timed.termination,"timeout"); XCTAssertLessThan(timed.durationMS,2000)
    }
    @MainActor func testCancellationTerminatesChildAndDoesNotLosePartialOutput() async throws {
        let r = try root(),runner = LocalProcessRunner(),control = RunControl()
        runner.onStart = { _ in Task { @MainActor in try? await Task.sleep(nanoseconds:150_000_000); control.stop() } }
        let output = try await runner.run(fixture("sleep 30 & child=$!; printf '%s' \"$child\" > child.pid; printf 'partial 한글🙂'; wait",r),index:1,directory:r.path+"/run",control:control)
        XCTAssertEqual(output.termination,"cancelled"); XCTAssertFalse(output.succeeded)
        XCTAssertEqual(try String(contentsOfFile:output.stdoutPath,encoding:.utf8),"partial 한글🙂")
        let child = try XCTUnwrap(Int32(try String(contentsOf:r.appendingPathComponent("child.pid"),encoding:.utf8)))
        XCTAssertTrue(kill(child,0) != 0,"Descendant should be reaped after the process group is stopped")
    }
    @MainActor func testCancellationTerminatesDescendantInSeparateProcessGroup() async throws {
        let r = try root(),runner = LocalProcessRunner(),control = RunControl()
        runner.onStart = { _ in Task { @MainActor in try? await Task.sleep(nanoseconds:300_000_000); control.stop() } }
        let script = "set -m; sleep 30 & child=$!; printf '%s' \"$child\" > child.pid; ps -o pgid= -p \"$child\" > child.group; wait"
        let result = try await runner.run(fixture(script,r),index:1,directory:r.path+"/run",control:control)
        let child = try XCTUnwrap(Int32(try String(contentsOf:r.appendingPathComponent("child.pid"),encoding:.utf8)))
        let group = try XCTUnwrap(Int32(try String(contentsOf:r.appendingPathComponent("child.group"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)))
        XCTAssertEqual(group,child); XCTAssertNotEqual(group,result.pid)
        XCTAssertEqual(result.termination,"cancelled"); XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.trackedDescendantPIDs?.contains(child) == true)
        XCTAssertEqual(result.remainingProcessPIDs,[]); XCTAssertNotEqual(kill(child,0),0)
    }
    @MainActor func testExitedLeaderCannotLeaveChildRunning() async throws {
        let r = try root(),runner = LocalProcessRunner()
        let output = try await runner.run(fixture("sleep 30 & printf '%s' \"$!\" > child.pid; exit 0",r),index:1,directory:r.path+"/run",control:RunControl())
        XCTAssertTrue(output.succeeded)
        let child = try XCTUnwrap(Int32(try String(contentsOf:r.appendingPathComponent("child.pid"),encoding:.utf8)))
        XCTAssertNotEqual(kill(child,0),0)
    }
    @MainActor func testConversionVerifiesActualNewImageAndRejectsOverwrite() async throws {
        let r = try root(),bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:8,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:32,bitsPerPixel:32))
        let input = r.appendingPathComponent("입력.png"),output = r.appendingPathComponent("변환.jpg")
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:input)
        var command = spec("sips",["-s","format","jpeg",input.path,"--out",output.path],r); command.expectedFiles = [output.path]
        let result = try await LocalProcessRunner().run(policy(r).validate(command),index:1,directory:r.path+"/run",control:RunControl())
        XCTAssertTrue(result.succeeded,result.error ?? ""); XCTAssertEqual(result.files.count,1)
        XCTAssertNotNil(NSImage(contentsOf:output)); XCTAssertGreaterThan(result.files.first?.bytes ?? 0,0)
        XCTAssertEqual(result.files.first?.sha256.count,64)
        XCTAssertThrowsError(try policy(r).validate(command))
    }
    func testWorkspaceAndHeadlessCLIOptionsUseExplicitScope() throws {
        let r = try root()
        XCTAssertEqual(try LocalWorkspace.select(request:"\"\(r.path)\"에서 검색",defaultDirectory:"/"),r.path)
        let options = try LocalCLIOptions(["--goal","조회","--directory",r.path,"--out",r.path+"/logs"])
        XCTAssertEqual(options.workspace,r.path); XCTAssertEqual(startupMode(["local"]),.cli)
        XCTAssertThrowsError(try LocalCLIOptions(["--goal","x","--directory","/"]))
        XCTAssertThrowsError(try LocalCLIOptions(["--goal","x","--unknown","x"]))
    }
    func testCommandOutputUpdatesStableRecordAndKeepsLogPaths() {
        let id = UUID(); var state = RunPresentationState()
        let facts:[RunPresentationEvent.Fact] = [.request("CLI"),.cycle(1),.commandStarted("cat file"),.commandOutput("one","처음",["/fixture/stdout.log","/fixture/stderr.log"]),.commandOutput("one","한글🙂 전체 미리보기",["/fixture/stdout.log","/fixture/stderr.log"]),.verification("exit 0"),.cycleEnd(1)]
        for (index,fact) in facts.enumerated() { state.apply(.init(runID:id,sequence:index,fact:fact)) }
        let outputs = state.topology.filter { $0.kind == .commandOutput }
        XCTAssertEqual(outputs.count,1); XCTAssertEqual(outputs[0].id,3); XCTAssertEqual(outputs[0].text,"한글🙂 전체 미리보기")
        XCTAssertEqual(outputs[0].evidencePaths?.count,2); XCTAssertEqual(state.inputs,0); XCTAssertEqual(state.localCommands,1)
        XCTAssertTrue(state.completedCycles.contains(1))
    }
    @MainActor func testCLIReadinessDoesNotRequireNativePermissions() {
        var state = SetupState(); state.codexInstalled = true; state.codexAuthenticated = true; state.keyVerified = true
        XCTAssertTrue(state.canPlan); XCTAssertFalse(state.ready)
    }
}
