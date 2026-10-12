import Foundation
import Security
import CoreServices
import MachO

enum StartupMode: Equatable { case cli, nativeServices, application }

func startupArguments(_ arguments: [String], inApplicationBundle: Bool) -> [String] {
    // Finder/Dock launch an APPL executable without the explicit terminal --gui flag.
    // Keep a raw, unbundled command-line executable's empty invocation as help.
    arguments.isEmpty && inApplicationBundle ? ["--gui"] : arguments
}

func startupMode(_ arguments: [String]) -> StartupMode {
    switch arguments.first ?? "help" {
    case "--gui", "calendar-list", "calendar-commit", "calendar-inspect", "calendar-test-reset": return .application
    case "run": return arguments.contains("--no-preview") && !arguments.contains("--show-virtual-cursor") ? .nativeServices : .application
    case "act": return arguments.contains("--show-virtual-cursor") ? .application : .nativeServices
    case "observe", "ax-query": return .nativeServices
    default: return .cli
    }
}

struct StartupExecutionIdentity: Codable, Equatable {
    var canonicalExecutable: String
    var bundlePath: String?
    var bundleIdentifier: String?
    var version: String?
    var build: String?

    static func current(pathProvider: () -> String? = loadedExecutablePath) -> Self? {
        guard let path = pathProvider() else { return nil }
        return Self(executablePath: path)
    }

    private static func loadedExecutablePath() -> String? {
        var count: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &count)
        guard count > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(count))
        guard _NSGetExecutablePath(&buffer, &count) == 0 else { return nil }
        return String(cString: buffer)
    }

    init(executablePath: String) {
        let executable = URL(fileURLWithPath: executablePath).standardizedFileURL.resolvingSymlinksInPath()
        canonicalExecutable = executable.path
        let candidate = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // Report the bundle containing this executable, not another checkout or an expected install path.
        if candidate.pathExtension == "app", let bundle = Bundle(url: candidate) {
            bundlePath = candidate.path
            bundleIdentifier = bundle.bundleIdentifier
            version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        }
    }
}

struct StartupLookup: Codable, Equatable {
    enum FailureCategory: String, Codable {
        case incompatibleExecutable, accessRestricted, applicationNotFound, missingExecutable, lookupFailure, noApplicationURLs
    }
    let bundleIdentifier: String
    let applicationURLs: [String]
    let errorDomain: String?
    let errorCode: Int?
    let evaluatorFile: String?
    let evaluatorFunction: String?
    let evaluatorLine: Int?
    let failureCategory: FailureCategory?

    init(bundleIdentifier: String = "com.apple.finder", applicationURLs: [String], errorDomain: String? = nil, errorCode: Int? = nil, evaluatorFile: String? = nil, evaluatorFunction: String? = nil, evaluatorLine: Int? = nil) {
        self.bundleIdentifier = bundleIdentifier; self.applicationURLs = applicationURLs
        self.errorDomain = errorDomain; self.errorCode = errorCode
        self.evaluatorFile = evaluatorFile; self.evaluatorFunction = evaluatorFunction; self.evaluatorLine = evaluatorLine
        if errorDomain != nil || errorCode != nil {
            switch (errorDomain, errorCode) {
            case (NSOSStatusErrorDomain, Int(kLSExecutableIncorrectFormat)): failureCategory = .incompatibleExecutable
            case (NSOSStatusErrorDomain, Int(kLSApplicationNotFoundErr)): failureCategory = .applicationNotFound
            case (NSOSStatusErrorDomain, Int(kLSNoExecutableErr)): failureCategory = .missingExecutable
            case (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)),
                 (NSOSStatusErrorDomain, -54), (NSCocoaErrorDomain, CocoaError.fileReadNoPermission.rawValue): failureCategory = .accessRestricted
            default: failureCategory = .lookupFailure
            }
        } else { failureCategory = applicationURLs.isEmpty ? .noApplicationURLs : nil }
    }

    static func finder() -> Self {
        var error: Unmanaged<CFError>?
        let urls = LSCopyApplicationURLsForBundleIdentifier("com.apple.finder" as CFString, &error)?.takeRetainedValue()
        let paths = (urls as? [URL] ?? []).map(\.path)
        guard let value = error?.takeRetainedValue() else { return Self(applicationURLs: paths) }
        let info = CFErrorCopyUserInfo(value) as NSDictionary
        // Optional OS diagnostic fields are evidence only; they never control authorization.
        return Self(applicationURLs: paths, errorDomain: CFErrorGetDomain(value) as String, errorCode: CFErrorGetCode(value), evaluatorFile: info["_LSFile"] as? String, evaluatorFunction: info["_LSFunction"] as? String, evaluatorLine: (info["_LSLine"] as? NSNumber)?.intValue)
    }
}

struct StartupDiagnostic: Encodable {
    let status: String
    let sessionStatus: OSStatus
    let securitySession: SecuritySessionId?
    let graphicalAccess: Bool
    let finderLookup: StartupLookup?
    let execution: StartupExecutionIdentity?
    // Passing this conservative preflight establishes neither registration nor TCC authorization.
    let appKitRegistrationVerified = false
}

struct GUIContext {
    var sessionStatus: OSStatus
    var graphicalAccess: Bool
    var securitySession: SecuritySessionId? = nil
    var finderLookup: StartupLookup? = nil
    var execution: StartupExecutionIdentity? = nil

    var diagnostic: StartupDiagnostic {
        let status: String
        if sessionStatus != errSecSuccess || !graphicalAccess { status = "blockedGraphicalSession" }
        else if finderLookup == nil { status = "lookupNotChecked" }
        else if finderLookup?.failureCategory != nil { status = "blockedFinderLookup" }
        else { status = "preflightPassed" }
        return StartupDiagnostic(status: status, sessionStatus: sessionStatus, securitySession: securitySession, graphicalAccess: graphicalAccess, finderLookup: finderLookup, execution: execution)
    }

    static func current() -> Self {
        var id = SecuritySessionId(), attributes = SessionAttributeBits()
        let status = SessionGetInfo(callerSecuritySession, &id, &attributes)
        let graphical = attributes.contains(.sessionHasGraphicAccess)
        return Self(sessionStatus: status, graphicalAccess: graphical, securitySession: id,
                    finderLookup: status == errSecSuccess && graphical ? .finder() : nil,
                    execution: StartupExecutionIdentity.current())
    }

    func requireAvailable() throws {
        let identity = execution.map { " Executable: \($0.canonicalExecutable); version: \($0.version ?? "unknown")/build \($0.build ?? "unknown")." } ?? ""
        guard sessionStatus == errSecSuccess, graphicalAccess else {
            throw Failure("Native macOS UI requires a graphical login session (Security session status \(sessionStatus)). Run from Terminal or Codex in the logged-in user's desktop session.\(identity)")
        }
        guard let lookup = finderLookup else { throw Failure("Finder startup lookup was not checked; native startup stopped.\(identity)") }
        if let category = lookup.failureCategory {
            let detail = lookup.errorDomain.map { "\($0) code \(lookup.errorCode.map(String.init) ?? "unknown")" } ?? "no application URLs returned"
            let reason: String
            switch category {
            case .incompatibleExecutable: reason = "Finder lookup found no compatible executable (kLSExecutableIncorrectFormat). This is not an explicit permission-denial code and does not identify the JEV executable as malformed."
            case .accessRestricted: reason = "Finder lookup reported an access restriction. No alternate host or elevated retry will be attempted."
            case .applicationNotFound: reason = "Finder lookup did not resolve an application."
            case .missingExecutable: reason = "Finder lookup reported a missing executable."
            default: reason = "Finder startup lookup failed."
            }
            throw Failure("\(reason) Target: \(lookup.bundleIdentifier); \(detail). Native startup stopped conservatively before AppKit; this lookup does not establish that all LaunchServices or AppKit services are unavailable.\(identity) Run 'startup-check' for read-only details in this same context. Preserve the evidence; do not reset system databases or bypass an access restriction.")
        }
    }
}
