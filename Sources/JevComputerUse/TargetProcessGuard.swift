import Foundation

// Diagnostics for the existing target/allowlist/lookup/liveness predicate.
// Identity comparisons never add a new acceptance or rejection condition.
enum TargetProcessGuard {
    struct State {
        var pid: Int32
        var bundle: String?
        var launchDate: Date?
        var terminated: Bool
    }

    enum Reason: String {
        case targetMissing = "observed_target_missing"
        case outsideAllowlist = "target_outside_allowlist"
        case lookupUnavailable = "process_lookup_unavailable"
        case terminated = "process_terminated"
        case allowed = "existing_guard_allowed"
    }

    struct Diagnostic {
        var reason: Reason
        var source: String
        var pid: Int32?
        var allowlisted: Bool?
        var process: State?
        var observed: AppInfo?

        var pidMatches: Bool? { process.flatMap { current in observed.map { current.pid == $0.pid } } }
        var bundleMatches: Bool? {
            guard let current = process, let observed else { return nil }
            return (current.bundle ?? "pid:\(current.pid)") == observed.bundle
        }
        var generationMatches: Bool? {
            guard pidMatches == true, let earlier = observed?.processLaunchDate,
                  let current = process?.launchDate else { return nil }
            return earlier == current
        }
        var identityChanged: Bool { pidMatches == false || bundleMatches == false || generationMatches == false }
        private func flag(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "unknown" }
        var record: String {
            // Only fixed tokens, numeric PID and comparison flags. Never log app names,
            // arbitrary bundle strings, paths, titles, input, arguments or environment.
            "native_target_guard reason=\(reason.rawValue) target_source=\(source) pid=\(pid.map(String.init) ?? "unknown") allowlisted=\(flag(allowlisted)) lookup=\(process == nil ? (reason == .lookupUnavailable ? "unavailable" : "not_attempted") : "resolved") terminated=\(flag(process?.terminated)) pid_matches=\(flag(pidMatches)) bundle_matches=\(flag(bundleMatches)) generation_matches=\(flag(generationMatches)) pid_reuse=\(generationMatches.map { $0 ? "not_observed" : "detected" } ?? "unknown")"
        }
        var failureMessage: String { "Target app changed or outside allowlist; reobserve [\(record)]" }
        var notice: String? { reason == .allowed && identityChanged ? "\(record) decision=allowed_by_existing_guard; identity comparison is diagnostic only" : nil }
    }

    enum Resolution<Process> {
        case allowed(AppInfo, Process, Diagnostic)
        case rejected(Diagnostic)
    }

    static func resolve<Process>(target: AppInfo?, front: AppInfo?, allowedApps: [String],
                                 lookup: (Int32) -> Process?, state: (Process) -> State) -> Resolution<Process> {
        let observed = target ?? front
        var diagnostic = Diagnostic(reason: .targetMissing, source: target == nil ? (front == nil ? "missing" : "front") : "target",
                                    pid: observed?.pid, allowlisted: nil, process: nil, observed: observed)
        guard let observed else { return .rejected(diagnostic) }
        diagnostic.allowlisted = allowedApps.contains(observed.bundle)
        guard diagnostic.allowlisted == true else { diagnostic.reason = .outsideAllowlist; return .rejected(diagnostic) }
        guard let process = lookup(observed.pid) else { diagnostic.reason = .lookupUnavailable; return .rejected(diagnostic) }
        diagnostic.process = state(process)
        guard diagnostic.process?.terminated == false else { diagnostic.reason = .terminated; return .rejected(diagnostic) }
        diagnostic.reason = .allowed
        return .allowed(observed, process, diagnostic)
    }
}
