import Foundation

@MainActor final class RunControl {
    private(set) var isCancelled = false
    var onStatus: (String) -> Void = { _ in }
    func stop() { isCancelled = true; onStatus("Stopping after current operation") }
    func check() throws { if isCancelled || Task.isCancelled { throw CancellationError() } }
    func status(_ text: String) { if !isCancelled { onStatus(text) } }
}

@MainActor final class TaskRunner {
    typealias AppSelection = @MainActor ([AppCandidate]) async throws -> [String]?
    typealias Resolve = @MainActor (TaskSpec, Bool, Bool, String, RunControl, AppSelection?) async -> AppResolution
    typealias Execute = @MainActor (TaskSpec, String, String?, AppResolution, RunControl, PreviewController?) async throws -> RunReport
    var resolve: Resolve
    var execute: Execute
    var requireCredential: () throws -> Void

    init(resolve: Resolve? = nil, execute: Execute? = nil, requireCredential: (() throws -> Void)? = nil, showVirtualPointer: Bool = false) {
        self.resolve = resolve ?? { spec, simple, fallback, directory, control, selection in
            await AppResolver().resolve(spec: spec, simple: simple, allowFallback: fallback, directory: directory, control: control, selection: selection)
        }
        self.execute = execute ?? { spec, directory, model, resolution, control, preview in
            let workflow = Workflow(); workflow.native.preview = preview; workflow.native.showVirtualPointer = showVirtualPointer
            return try await workflow.run(spec: spec, directory: directory, model: model, appSelection: resolution, control: control)
        }
        self.requireCredential = requireCredential ?? {
            guard (try? credential()) != nil else { throw Failure("TypeSafe API key missing. Use Import Key from Clipboard or Open Key Management, then run again.") }
        }
    }

    func run(request: RunRequest, directory: String, model: String?, control: RunControl,
             selection: AppSelection? = nil, preview: PreviewController? = nil, makePreview: (() -> PreviewController?)? = nil) async throws -> RunReport {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try writeJSON(request.spec, directory + "/requested-task.json")
        var resolution: AppResolution?
        var workflowStarted = false
        do {
            try control.check()
            if request.spec.apps.isEmpty && !request.chooseApps { try requireCredential() }
            control.status(request.chooseApps ? "Choose target apps" : "Selecting target apps")
            resolution = await resolve(request.spec, request.chooseApps, request.allowInteractiveFallback, directory, control, selection)
            try writeJSON(resolution, directory + "/app-selection.json")
            try control.check()
            guard let resolved = resolution, resolved.status == "resolved" else {
                let result = RunReport(status: "app_selection_" + (resolution?.status ?? "error"), goal: request.spec.goal,
                    steps: [], finalObservation: "", directory: directory, apps: [], appSelection: resolution)
                try writeJSON(result, directory + "/report.json"); return result
            }
            try requireCredential(); try control.check()
            var spec = request.spec; spec.apps = resolved.apps
            control.status("Running in " + resolved.apps.joined(separator: ", "))
            let runPreview = preview ?? makePreview?()
            try control.check()
            workflowStarted = true
            return try await execute(spec, directory, model, resolved, control, runPreview)
        } catch {
            let cancelled = control.isCancelled || error is CancellationError || Task.isCancelled
            let savedSteps = workflowStarted ? ((try? JSONDecoder().decode([Step].self, from: Data(contentsOf:URL(fileURLWithPath:directory + "/steps.json")))) ?? []) : []
            let final = savedSteps.last?.afterObservation ?? savedSteps.last?.observation ?? ""
            let result = RunReport(status: cancelled ? "cancelled" : "error", goal: request.spec.goal,
                steps: savedSteps, finalObservation: final, directory: directory, apps: resolution?.apps ?? [], appSelection: resolution,
                error: cancelled ? nil : String(describing: error))
            try writeJSON(result, directory + "/report.json"); return result
        }
    }
}

/// Owns one GUI run; UI and tests use the same duplicate-run and reset behavior.
@MainActor final class RunSession {
    private(set) var active = false
    private(set) var control: RunControl?
    private(set) var report: RunReport?
    private(set) var error: String?
    var onChange: () -> Void = {}
    private var task: Task<Void, Never>?

    @discardableResult func start(status: @escaping (String) -> Void,
        operation: @escaping @MainActor (RunControl) async throws -> RunReport) throws -> Task<Void, Never> {
        guard !active else { throw Failure("A run is already active. Stop it or wait for completion.") }
        let control = RunControl(); control.onStatus = status
        self.control = control; active = true; report = nil; error = nil; onChange()
        let task = Task { @MainActor in
            defer { self.active = false; self.control = nil; self.task = nil; self.onChange() }
            do { self.report = try await operation(control) }
            catch { self.error = String(describing: error) }
        }
        self.task = task
        return task
    }
    func stop() { control?.stop() }
}
