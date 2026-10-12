import XCTest
@testable import JevComputerUse

final class StartupTests: XCTestCase {
    func testBundledDefaultLaunchOpensTaskWindowButRawCLIStillShowsHelp() {
        let bundled = startupArguments([], inApplicationBundle: true)
        XCTAssertEqual(bundled, ["--gui"])
        XCTAssertEqual(startupMode(bundled), .application)
        XCTAssertNoThrow(try GUIOptions(arguments: bundled))
        let raw = startupArguments([], inApplicationBundle: false)
        XCTAssertEqual(raw, [])
        XCTAssertEqual(startupMode(raw), .cli)
        for args in [["help"], ["--help"], ["doctor"], ["--version-json"], ["observe"], ["act"], ["--gui", "--goal", "test"]] {
            XCTAssertEqual(startupArguments(args, inApplicationBundle: true), args)
            XCTAssertEqual(startupArguments(args, inApplicationBundle: false), args)
        }
    }
    func testPureCommandsDoNotRequestApplicationRegistration() {
        for args in [[], ["help"], ["--help"], ["setup"], ["setup", "--import-pasteboard"], ["install-skill", "--host", "both"], ["doctor"], ["startup-check"], ["delegate", "--prompt", "test"]] {
            XCTAssertEqual(startupMode(args), .cli)
        }
    }
    func testPreviewAndVirtualMarkerRequireApplicationLoop() {
        XCTAssertEqual(startupMode(["--gui"]), .application)
        XCTAssertEqual(startupMode(["--gui", "--no-preview"]), .application)
        XCTAssertEqual(startupMode(["run"]), .application)
        XCTAssertEqual(startupMode(["run", "--no-preview"]), .nativeServices)
        XCTAssertEqual(startupMode(["run", "--no-preview", "--show-virtual-cursor"]), .application)
        XCTAssertEqual(startupMode(["act", "--show-virtual-cursor"]), .application)
        XCTAssertEqual(startupMode(["act"]), .nativeServices)
        XCTAssertEqual(startupMode(["observe"]), .nativeServices)
    }
    func testMissingDesktopAndLaunchServicesErrorsAreActionable() {
        for context in [GUIContext(sessionStatus: -60500, graphicalAccess: false), GUIContext(sessionStatus: 0, graphicalAccess: false)] {
            XCTAssertThrowsError(try context.requireAvailable()) { error in
                XCTAssertTrue(String(describing: error).contains("logged-in"))
            }
        }
        let unknown = StartupLookup(applicationURLs: [], errorDomain: "test-domain", errorCode: 801)
        XCTAssertEqual(unknown.failureCategory, .lookupFailure)
        XCTAssertThrowsError(try GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: unknown).requireAvailable())
        XCTAssertNoThrow(try GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: StartupLookup(applicationURLs: ["/System/Library/CoreServices/Finder.app"])).requireAvailable())
    }
    func testFinderFormatFailureIsNotPermissionDenialOrJEVFormatFailure() {
        let lookup = StartupLookup(applicationURLs: [], errorDomain: NSOSStatusErrorDomain, errorCode: -10661, evaluatorFile: "LSBindingEvaluator.mm", evaluatorFunction: "runEvaluator", evaluatorLine: 1972)
        let context = GUIContext(sessionStatus: 0, graphicalAccess: true, securitySession: 100021, finderLookup: lookup)
        XCTAssertEqual(lookup.failureCategory, .incompatibleExecutable)
        XCTAssertEqual(context.diagnostic.status, "blockedFinderLookup")
        XCTAssertThrowsError(try context.requireAvailable()) { error in
            let text = String(describing: error)
            XCTAssertTrue(text.contains("Target: com.apple.finder"))
            XCTAssertTrue(text.contains("not an explicit permission-denial code"))
            XCTAssertTrue(text.contains("does not identify the JEV executable as malformed"))
            XCTAssertFalse(text.contains("LaunchServices is unavailable"))
        }
        XCTAssertEqual(StartupLookup(applicationURLs: [], errorDomain: "unrelated-domain", errorCode: -10661).failureCategory, .lookupFailure)
    }
    func testExplicitAccessRestrictionsRemainBlockedEvenWithURLs() {
        for (domain, code) in [(NSPOSIXErrorDomain, 1), (NSPOSIXErrorDomain, 13), (NSOSStatusErrorDomain, -54), (NSCocoaErrorDomain, 257)] {
            let lookup = StartupLookup(applicationURLs: ["/System/Library/CoreServices/Finder.app"], errorDomain: domain, errorCode: code)
            let context = GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: lookup)
            XCTAssertEqual(lookup.failureCategory, .accessRestricted)
            XCTAssertThrowsError(try context.requireAvailable()) { error in
                XCTAssertTrue(String(describing: error).contains("access restriction"))
            }
        }
    }
    func testEmptyUncheckedAndUnknownLookupsFailClosed() {
        let empty = StartupLookup(applicationURLs: [])
        XCTAssertEqual(empty.failureCategory, .noApplicationURLs)
        for lookup in [nil, empty, StartupLookup(applicationURLs: ["/Finder.app"], errorDomain: NSOSStatusErrorDomain, errorCode: -123456)] as [StartupLookup?] {
            XCTAssertThrowsError(try GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: lookup).requireAvailable())
        }
        XCTAssertEqual(StartupLookup(applicationURLs: [], errorDomain: NSOSStatusErrorDomain, errorCode: -10814).failureCategory, .applicationNotFound)
        XCTAssertEqual(StartupLookup(applicationURLs: [], errorDomain: NSOSStatusErrorDomain, errorCode: -10827).failureCategory, .missingExecutable)
    }
    func testPassingPreflightDoesNotClaimAppKitRegistrationOrAuthorization() throws {
        let context = GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: StartupLookup(applicationURLs: ["/Finder.app"]))
        XCTAssertEqual(context.diagnostic.status, "preflightPassed")
        let data = try JSONEncoder().encode(context.diagnostic)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(report["appKitRegistrationVerified"] as? Bool, false)
        XCTAssertNil(report["permissions"])
        let blocked = GUIContext(sessionStatus: -60500, graphicalAccess: true, finderLookup: context.finderLookup)
        XCTAssertEqual(blocked.diagnostic.status, "blockedGraphicalSession")
        XCTAssertThrowsError(try blocked.requireAvailable())
    }
    func testExecutionIdentityReportsActualSymlinkDestinationBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("startup-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("old-checkout/JevNative.app")
        let executable = bundle.appendingPathComponent("Contents/MacOS/jev-native")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        let plist: [String: Any] = ["CFBundleIdentifier": "ai.typesafe.jev-native", "CFBundleExecutable": "jev-native", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "7"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let alias = root.appendingPathComponent("jev-native")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: executable)
        let identity = StartupExecutionIdentity(executablePath: alias.path)
        XCTAssertEqual(identity.canonicalExecutable, executable.resolvingSymlinksInPath().path)
        XCTAssertEqual(identity.bundlePath, bundle.resolvingSymlinksInPath().path)
        XCTAssertEqual(identity.version, "0.5.0"); XCTAssertEqual(identity.build, "7")
        let failure = GUIContext(sessionStatus: 0, graphicalAccess: true, finderLookup: StartupLookup(applicationURLs: [], errorDomain: NSOSStatusErrorDomain, errorCode: -10661), execution: identity)
        XCTAssertThrowsError(try failure.requireAvailable()) { error in
            XCTAssertTrue(String(describing: error).contains(identity.canonicalExecutable))
            XCTAssertTrue(String(describing: error).contains("0.5.0/build 7"))
        }
    }
    func testUnavailableLoadedPathIsNotGuessedFromArguments() throws {
        XCTAssertNil(StartupExecutionIdentity.current(pathProvider: { nil }))
        let loaded = try XCTUnwrap(StartupExecutionIdentity.current())
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: loaded.canonicalExecutable))
        XCTAssertNotNil(StartupExecutionIdentity.current(pathProvider: { loaded.canonicalExecutable }))
    }
}
