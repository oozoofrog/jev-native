import Foundation
import Darwin

@MainActor final class RunControl {
    private(set) var isCancelled = false
    private(set) var pauseRequested = false
    private(set) var isPaused = false
    private var pauseWaiter: CheckedContinuation<Void, Error>?
    private let runID = UUID()
    private var sequence = 0
    private var cycleOffset = 0
    private var highestCycle = 0
    private var journal:FileHandle?
    private var journalError:Error?
    func recordEvents(in directory:String) throws {
        let path=URL(fileURLWithPath:directory).appendingPathComponent("task-events.jsonl")
        guard journal == nil else { throw Failure("한 작업의 단계 기록을 다른 폴더로 분리하지 않았습니다.") }
        let descriptor=open(path.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard descriptor>=0 else { throw Failure("기존 작업 기록을 덮어쓰지 않았습니다. 새 기록 폴더의 쓰기 상태를 확인해 주세요.") }
        journal=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true)
    }
    deinit { try? journal?.close() }
    var onStatus: (String) -> Void = { _ in }
    var onPresentation: (RunPresentationEvent) -> Void = { _ in }
    var onPauseChange: () -> Void = {}
    func emit(_ fact: RunPresentationEvent.Fact) {
        let translated:RunPresentationEvent.Fact
        switch fact {
        case .cycle(let cycle): let value = cycle+cycleOffset; highestCycle = max(highestCycle,value); translated = .cycle(value)
        case .cycleEnd(let cycle): translated = .cycleEnd(cycle+cycleOffset)
        default: translated = fact
        }
        let event=RunPresentationEvent(runID:runID,sequence:sequence,fact:translated)
        if let journal {
            do {
                let object=try JSONSerialization.jsonObject(with:jsonData(event))
                var data=try JSONSerialization.data(withJSONObject:EvidencePrivacy.json(object),options:[.sortedKeys]); data.append(10)
                try journal.write(contentsOf:data)
            } catch { journalError=Failure("작업 단계 기록을 저장하지 못했습니다. 추가 실행을 중단합니다.") }
        }
        onPresentation(event); sequence += 1
    }
    @discardableResult func beginCycle() -> Int { let cycle = highestCycle-cycleOffset+1; emit(.cycle(cycle)); return cycle }
    func withAdditionalCycles<T>(_ operation:() async throws -> T) async rethrows -> T {
        let previous = cycleOffset; cycleOffset = highestCycle
        defer { cycleOffset = previous }; return try await operation()
    }
    func requestPause() { guard !isCancelled else { return }; pauseRequested = true; onPauseChange() }
    func resume() {
        pauseRequested = false; isPaused = false; emit(.pause(false))
        let waiter = pauseWaiter; pauseWaiter = nil; waiter?.resume(); onPauseChange()
    }
    func stop() {
        isCancelled = true; pauseRequested = false; isPaused = false
        let waiter = pauseWaiter; pauseWaiter = nil; waiter?.resume(throwing:CancellationError())
        onStatus("Stopping after current operation"); onPauseChange()
    }
    func check() throws { if isCancelled || Task.isCancelled { throw CancellationError() }; if let journalError { throw journalError } }
    func checkpoint() async throws {
        try check()
        guard pauseRequested else { return }
        isPaused = true; emit(.pause(true)); onPauseChange()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                if isCancelled || Task.isCancelled { waiter.resume(throwing:CancellationError()) }
                else if !pauseRequested { waiter.resume() }
                else { precondition(pauseWaiter == nil); pauseWaiter = waiter }
            }
        }, onCancel: { Task { @MainActor in self.stop() } })
        try check()
    }
    func status(_ text: String) { if !isCancelled { onStatus(text); emit(.phase(text)) } }
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
             selection: AppSelection? = nil, preview: PreviewController? = nil, makePreview: (() -> PreviewController?)? = nil, knownResolution: AppResolution? = nil) async throws -> RunReport {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try writeJSON(request.spec, directory + "/requested-task.json")
        var resolution: AppResolution?
        var workflowStarted = false
        do {
            try await control.checkpoint()
            if request.spec.apps.isEmpty && !request.chooseApps { try requireCredential() }
            control.status(request.chooseApps ? "Choose target apps" : "Selecting target apps")
            if let knownResolution { resolution = knownResolution }
            else { resolution = await resolve(request.spec, request.chooseApps, request.allowInteractiveFallback, directory, control, selection) }
            try writeJSON(resolution, directory + "/app-selection.json")
            try await control.checkpoint()
            guard let resolved = resolution, resolved.status == "resolved" else {
                let result = RunReport(status: "app_selection_" + (resolution?.status ?? "error"), goal: request.spec.goal,
                    steps: [], finalObservation: "", directory: directory, apps: [], appSelection: resolution)
                try writeJSON(result, directory + "/report.json"); return result
            }
            try requireCredential(); try control.check()
            var spec = request.spec; spec.apps = resolved.apps
            control.emit(.target(resolved.apps.joined(separator:", ")))
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
        presentation: @escaping (RunPresentationEvent) -> Void = { _ in }, request: String = "", directory:String? = nil,
        operation: @escaping @MainActor (RunControl) async throws -> RunReport) throws -> Task<Void, Never> {
        guard !active else { throw Failure("A run is already active. Stop it or wait for completion.") }
        let control = RunControl(); control.onStatus = status; control.onPresentation = presentation
        if let directory { try control.recordEvents(in:directory) }
        control.onPauseChange = { [weak self] in self?.onChange() }
        control.emit(.request(request))
        self.control = control; active = true; report = nil; error = nil; onChange()
        let task = Task { @MainActor in
            defer { self.active = false; self.control = nil; self.task = nil; self.onChange() }
            do {
                let report = try await operation(control); self.report = report
                if let response = report.response { control.emit(.result(response)) }
                control.emit(.outcome(report.status))
            }
            catch {
                self.error = String(describing:error)
                if !control.isCancelled && !(error is CancellationError) { control.emit(.failure(String(describing:error))) }
                control.emit(.outcome(control.isCancelled || error is CancellationError ? "cancelled" : "error"))
            }
        }
        self.task = task
        return task
    }
    func stop() { control?.stop() }
}
