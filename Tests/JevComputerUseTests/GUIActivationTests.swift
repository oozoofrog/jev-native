import Foundation
import XCTest
@testable import JevComputerUse

final class GUIActivationTests:XCTestCase {
    func testExplicitGUIAlwaysDelegatesEvenWhenOriginIsInherited() {
        let inherited=[GUIActivation.originKey:GUIActivation.originValue,GUIActivation.optionsKey:"old launch data"]
        for environment in [[:],inherited] {
            XCTAssertEqual(GUIActivation.entry(["--gui"],bundled:true,environment:environment),.activateApplication)
            XCTAssertEqual(GUIActivation.entry(["--gui","--goal","new request"],bundled:true,environment:environment),.activateApplication)
        }
    }
    func testFinderHostAndBareCLIHaveDifferentEntryRoles() {
        XCTAssertEqual(GUIActivation.entry([],bundled:true,environment:[:]),.activateApplication)
        XCTAssertEqual(GUIActivation.entry([],bundled:true,environment:[GUIActivation.originKey:GUIActivation.originValue]),.applicationHost)
        XCTAssertEqual(GUIActivation.entry([],bundled:true,environment:[GUIActivation.originKey:"other"]),.activateApplication)
        XCTAssertEqual(GUIActivation.entry([],bundled:false,environment:[GUIActivation.originKey:GUIActivation.originValue]),.command)
        for args in [["observe"],["act"],["--version-json"],["run","--no-preview"],["calendar-list"]] {
            XCTAssertEqual(GUIActivation.entry(args,bundled:true,environment:[GUIActivation.originKey:GUIActivation.originValue]),.command)
        }
    }
    func testNewLaunchOptionsPreserveLiteralInputAndInheritedDataIsReplaced() throws {
        let options=try GUIOptions(arguments:["--gui","--goal","읽기만 하세요\n🙂 & $(literal)","--directory","/fixture-workspace/path with spaces","--codex-model","chosen-model","--simple","--no-preview"])
        let environment=try GUIActivation.launchEnvironment(options:options)
        XCTAssertEqual(try GUIActivation.startOptions(environment:environment),options)
        let defaultOptions=try GUIOptions(arguments:["--gui"])
        XCTAssertEqual(try GUIActivation.startOptions(environment:GUIActivation.launchEnvironment(options:defaultOptions)),defaultOptions)
        XCTAssertEqual(try GUIActivation.startOptions(environment:[:]),defaultOptions)
        XCTAssertThrowsError(try GUIActivation.startOptions(environment:[GUIActivation.optionsKey:"malformed"]))
    }
    func testReturnedPIDAndExactApplicationIdentityAreRequired() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("gui-activation-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let app=root.appendingPathComponent("JevNative.app"),exe=app.appendingPathComponent("Contents/MacOS/jev-native")
        try FileManager.default.createDirectory(at:exe.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data().write(to:exe)
        let info:[String:Any]=["CFBundleIdentifier":CompiledProduct.bundleIdentifier,"CFBundleExecutable":"jev-native","CFBundlePackageType":"APPL"]
        try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:app.appendingPathComponent("Contents/Info.plist"))
        let execution=StartupExecutionIdentity(executablePath:exe.path),target=try GUIActivation.Target(execution:execution)
        XCTAssertNoThrow(try target.validate(pid:123,bundle:CompiledProduct.bundleIdentifier,bundleURL:app,executableURL:exe,caller:456))
        XCTAssertThrowsError(try target.validate(pid:456,bundle:CompiledProduct.bundleIdentifier,bundleURL:app,executableURL:exe,caller:456))
        XCTAssertThrowsError(try target.validate(pid:123,bundle:CompiledProduct.bundleIdentifier,bundleURL:app,executableURL:exe,caller:456,expectedOwner:789))
        XCTAssertThrowsError(try target.validate(pid:0,bundle:CompiledProduct.bundleIdentifier,bundleURL:app,executableURL:exe,caller:456))
        XCTAssertThrowsError(try target.validate(pid:123,bundle:"other",bundleURL:app,executableURL:exe,caller:456))
        XCTAssertThrowsError(try target.validate(pid:123,bundle:CompiledProduct.bundleIdentifier,bundleURL:root.appendingPathComponent("other/JevNative.app"),executableURL:exe,caller:456))
        XCTAssertThrowsError(try target.validate(pid:123,bundle:CompiledProduct.bundleIdentifier,bundleURL:app,executableURL:root.appendingPathComponent("other"),caller:456))
    }

    func testPreviewCommandsAndAmbiguousOwnersCannotBeAcceptedAsWorkshop() throws {
        XCTAssertEqual(GUIActivation.processRole(argumentCount:1),.workshop)
        XCTAssertEqual(GUIActivation.processRole(argumentCount:2),.command)
        XCTAssertEqual(GUIActivation.processRole(argumentCount:nil),.unavailable)
        XCTAssertNil(try GUIActivation.validatedOwner([]))
        XCTAssertEqual(try GUIActivation.validatedOwner([(pid:123,role:.workshop)]),123)
        XCTAssertThrowsError(try GUIActivation.validatedOwner([(pid:123,role:.workshop),(pid:456,role:.workshop)]))
        XCTAssertThrowsError(try GUIActivation.validatedOwner([(pid:123,role:.command)]))
        XCTAssertThrowsError(try GUIActivation.validatedOwner([(pid:123,role:.unavailable)]))
    }
    func testCallerContextDoesNotTurnOmittedDirectoryIntoExplicitOverride() throws {
        let caller="/fixture-workspace/current project"
        XCTAssertNil(try GUIActivation.activationOptions(arguments:["--gui"],workingDirectory:caller).workingDirectory)
        XCTAssertNil(try GUIActivation.activationOptions(arguments:[],workingDirectory:caller).workingDirectory)
        XCTAssertEqual(try GUIActivation.activationOptions(arguments:["--gui","--directory","/fixture-workspace/chosen"],workingDirectory:caller).workingDirectory,"/fixture-workspace/chosen")
        XCTAssertEqual(try GUIActivation.activationOptions(arguments:["--gui","--directory","subproject"],workingDirectory:caller).workingDirectory,caller+"/subproject")
        let omitted=try GUIActivation.activationOptions(arguments:["--gui"],workingDirectory:caller)
        let context=try XCTUnwrap(GUIActivation.startContext(environment:GUIActivation.launchEnvironment(options:omitted,workingDirectory:caller)))
        XCTAssertEqual(context.workingDirectory,caller)
        XCTAssertNil(context.options.workingDirectory)

    }
    func testLaunchPayloadDoesNotLeakIntoChildProcesses() throws {
        let before=ProcessInfo.processInfo.environment
        defer {
            for key in [GUIActivation.originKey,GUIActivation.optionsKey] {
                if let value=before[key] { setenv(key,value,1) } else { unsetenv(key) }
            }
        }
        setenv(GUIActivation.originKey,GUIActivation.originValue,1)
        setenv(GUIActivation.optionsKey,"private fixture request",1)
        let captured=GUIActivation.consumeLaunchEnvironment()
        XCTAssertEqual(captured[GUIActivation.optionsKey],"private fixture request")
        XCTAssertNil(ProcessInfo.processInfo.environment[GUIActivation.originKey])
        XCTAssertNil(ProcessInfo.processInfo.environment[GUIActivation.optionsKey])
        let child=Process(),pipe=Pipe();child.executableURL=URL(fileURLWithPath:"/usr/bin/printenv");child.arguments=[GUIActivation.originKey,GUIActivation.optionsKey];child.standardOutput=pipe
        try child.run();child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus,1)
        XCTAssertTrue(pipe.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    func testUnknownOrRelativeLaunchContextIsRejected() throws {
        let options=try GUIOptions(arguments:["--gui"])
        for context in [GUIActivation.LaunchContext(schema:2,options:options,workingDirectory:"/fixture-workspace"),GUIActivation.LaunchContext(schema:1,options:options,workingDirectory:"relative")] {
            let json=String(decoding:try JSONEncoder().encode(context),as:UTF8.self)
            XCTAssertThrowsError(try GUIActivation.startContext(environment:[GUIActivation.optionsKey:json]))
        }
    }

    func testCallerFolderContextDoesNotChangeProcessDirectoryOrBypassGoalInference() throws {
        let before=FileManager.default.currentDirectoryPath
        let defaults=try GUIOptions(arguments:["--gui"])
        let caller="/fixture-workspace/not-opened-during-startup"
        let options=try GUIActivation.hostOptions(environment:GUIActivation.launchEnvironment(options:defaults,workingDirectory:caller))
        XCTAssertEqual(FileManager.default.currentDirectoryPath,before)
        XCTAssertNil(options.workingDirectory)
        XCTAssertEqual(options.launchWorkingDirectory,caller)
        var readFallback=false
        func fallback()->String {readFallback=true;return "unused"}
        XCTAssertEqual(options.baseWorkingDirectory(fallback:fallback()),caller)
        XCTAssertFalse(readFallback)
    }
}
