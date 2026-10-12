import Foundation
import XCTest
@testable import JevComputerUse

final class TargetProcessGuardTests: XCTestCase {
    private let bundle = "com.example.target"
    private var target: AppInfo { AppInfo(pid: 123, bundle: bundle, name: "private app title", processLaunchDate: Date(timeIntervalSince1970: 100)) }
    private var live: TargetProcessGuard.State { .init(pid: 123, bundle: bundle, launchDate: Date(timeIntervalSince1970: 100), terminated: false) }

    private func diagnostic(target: AppInfo?, front: AppInfo? = nil, allowed: [String]? = nil,
                            process: TargetProcessGuard.State?, expected: TargetProcessGuard.Reason,
                            file: StaticString = #filePath, line: UInt = #line) -> TargetProcessGuard.Diagnostic {
        let result = TargetProcessGuard.resolve(target: target, front: front, allowedApps: allowed ?? [bundle], lookup: { _ in process }, state: { $0 })
        switch result {
        case .allowed(_, _, let diagnostic):
            XCTAssertEqual(expected, .allowed, file: file, line: line)
            return diagnostic
        case .rejected(let diagnostic):
            XCTAssertNotEqual(expected, .allowed, file: file, line: line)
            XCTAssertEqual(diagnostic.reason, expected, file: file, line: line)
            return diagnostic
        }
    }

    func testMissingTargetDoesNotLookupOrReadState() {
        let result = TargetProcessGuard.resolve(target: nil, front: nil, allowedApps: [bundle],
            lookup: { _ -> TargetProcessGuard.State? in XCTFail("Lookup must short circuit"); return self.live },
            state: { _ in XCTFail("State must short circuit"); return self.live })
        guard case .rejected(let d) = result else { return XCTFail("Missing target accepted") }
        XCTAssertEqual(d.reason, .targetMissing)
        XCTAssertTrue(d.record.contains("target_source=missing"))
        XCTAssertTrue(d.record.contains("lookup=not_attempted"))
        XCTAssertTrue(d.record.contains("allowlisted=unknown"))
    }

    func testOutsideAllowlistDoesNotLookup() {
        let result = TargetProcessGuard.resolve(target: target, front: nil, allowedApps: [],
            lookup: { _ -> TargetProcessGuard.State? in XCTFail("Outside scope must short circuit"); return self.live }, state: { $0 })
        guard case .rejected(let d) = result else { return XCTFail("Out of scope target accepted") }
        XCTAssertEqual(d.reason, .outsideAllowlist)
        XCTAssertTrue(d.record.contains("allowlisted=false"))
        XCTAssertTrue(d.record.contains("lookup=not_attempted"))
    }

    func testLookupUnavailableIsUnknownLivenessNotProcessAbsent() {
        let d = diagnostic(target: target, process: nil, expected: .lookupUnavailable)
        XCTAssertTrue(d.record.contains("lookup=unavailable"))
        XCTAssertTrue(d.record.contains("terminated=unknown"))
        XCTAssertTrue(d.record.contains("pid_reuse=unknown"))
    }

    func testTerminatedProcessHasSpecificReason() {
        var process = live; process.terminated = true
        let d = diagnostic(target: target, process: process, expected: .terminated)
        XCTAssertTrue(d.record.contains("terminated=true"))
        XCTAssertTrue(d.failureMessage.hasPrefix("Target app changed or outside allowlist; reobserve ["))
        XCTAssertNil(d.notice)
    }

    func testTargetPrecedesFrontAndFrontFallbackRemainsSupported() {
        let other = AppInfo(pid: 999, bundle: "outside", name: "other")
        XCTAssertEqual(diagnostic(target: target, front: other, process: live, expected: .allowed).source, "target")
        XCTAssertEqual(diagnostic(target: nil, front: target, process: live, expected: .allowed).source, "front")
        _ = diagnostic(target: other, front: target, process: live, expected: .outsideAllowlist)
    }

    func testOnlyObservedPIDIsLookedUpExactlyOnce() {
        var calls: [Int32] = []
        let result = TargetProcessGuard.resolve(target: target, front: nil, allowedApps: [bundle],
            lookup: { calls.append($0); return self.live }, state: { $0 })
        guard case .allowed(let observed, let process, _) = result else { return XCTFail("Live target rejected") }
        XCTAssertEqual(calls, [123]); XCTAssertEqual(observed.pid, 123); XCTAssertEqual(process.pid, 123)
    }

    func testChangedGenerationIdentifiesPIDReuseWithoutChangingDecision() {
        var process = live; process.launchDate = Date(timeIntervalSince1970: 200)
        let d = diagnostic(target: target, process: process, expected: .allowed)
        XCTAssertTrue(d.record.contains("generation_matches=false"))
        XCTAssertTrue(d.record.contains("pid_reuse=detected"))
        XCTAssertTrue(d.notice?.contains("decision=allowed_by_existing_guard") == true)
        process.terminated = true
        let rejected = diagnostic(target: target, process: process, expected: .terminated)
        XCTAssertTrue(rejected.record.contains("pid_reuse=detected"))
    }

    func testBundleAndPIDMismatchAreSeparateDiagnosticFlags() {
        var process = live; process.bundle = "different"
        let bundleMismatch = diagnostic(target: target, process: process, expected: .allowed)
        XCTAssertEqual(bundleMismatch.pidMatches, true)
        XCTAssertEqual(bundleMismatch.bundleMatches, false)
        XCTAssertNotNil(bundleMismatch.notice)
        process.pid = 456
        let pidMismatch = diagnostic(target: target, process: process, expected: .allowed)
        XCTAssertEqual(pidMismatch.pidMatches, false)
        XCTAssertNil(pidMismatch.generationMatches)
        XCTAssertTrue(pidMismatch.record.contains("pid_reuse=unknown"))
    }

    func testUnavailableGenerationDoesNotInventPIDReuse() {
        var old = target; old.processLaunchDate = nil
        var process = live; process.launchDate = Date(timeIntervalSince1970: 200)
        XCTAssertNil(diagnostic(target: old, process: process, expected: .allowed).generationMatches)
        process.launchDate = nil
        let d = diagnostic(target: target, process: process, expected: .allowed)
        XCTAssertTrue(d.record.contains("generation_matches=unknown"))
        XCTAssertNil(d.notice)
    }

    func testBundlelessPIDFallbackKeepsExistingIdentityConvention() {
        var observed = target; observed.bundle = "pid:123"
        var process = live; process.bundle = nil
        let d = diagnostic(target: observed, allowed: ["pid:123"], process: process, expected: .allowed)
        XCTAssertEqual(d.bundleMatches, true)
        XCTAssertNil(d.notice)
    }

    func testDecisionMatrixRetainsAllFourOriginalConditions() {
        for hasTarget in [false, true] {
            for allowlisted in [false, true] {
                for lookupAvailable in [false, true] {
                    for terminated in [false, true] {
                        var process = live; process.terminated = terminated
                        let expected: TargetProcessGuard.Reason = !hasTarget ? .targetMissing : !allowlisted ? .outsideAllowlist : !lookupAvailable ? .lookupUnavailable : terminated ? .terminated : .allowed
                        _ = diagnostic(target: hasTarget ? target : nil, allowed: allowlisted ? [bundle] : [],
                                       process: lookupAvailable ? process : nil, expected: expected)
                    }
                }
            }
        }
    }

    func testDiagnosticDoesNotExposeNamesBundlesOrArbitraryInput() {
        let secret = "PRIVATE_SENTINEL\nforged_log=/fixture-workspace/private-document"
        var observed = target; observed.bundle = secret; observed.name = secret
        var process = live; process.bundle = "different " + secret; process.launchDate = Date(timeIntervalSince1970: 200)
        let d = diagnostic(target: observed, allowed: [secret], process: process, expected: .allowed)
        for message in [d.record, d.failureMessage, d.notice ?? ""] {
            XCTAssertFalse(message.contains(secret))
            XCTAssertFalse(message.contains("PRIVATE_SENTINEL"))
            XCTAssertFalse(message.contains("\n"))
            XCTAssertFalse(message.contains("/fixture-workspace/"))
        }
    }

    func testOldObservationAppInfoDecodesWithoutGenerationAndNewInfoRoundTrips() throws {
        let old = try JSONDecoder().decode(AppInfo.self, from: Data(#"{"pid":123,"bundle":"com.example.target","name":"app"}"#.utf8))
        XCTAssertNil(old.processLaunchDate)
        let new = try JSONDecoder().decode(AppInfo.self, from: JSONEncoder().encode(target))
        XCTAssertEqual(new.processLaunchDate, target.processLaunchDate)
        XCTAssertEqual(new.pid, target.pid)
    }
}
