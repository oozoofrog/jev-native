import Foundation

@MainActor final class Workflow {
    let native = Native(); let jev = Jev()
    var observeOverride: (@MainActor (String?, Bool) async throws -> Observation)?
    var decideOverride: (@MainActor (String, Observation, [Candidate], [Step], [String:String]?) async throws -> Decision)?
    var performOverride: (@MainActor (Action, Observation, [String]) async throws -> Void)?
    private func observe(directory: String?, images: Bool = true) async throws -> Observation {
        if let observeOverride { return try await observeOverride(directory, images) }
        return try await native.observe(directory:directory, images:images)
    }
    private func decide(goal: String, observation: Observation, candidates: [Candidate], history: [Step], advisory: [String:String]?) async throws -> Decision {
        if let decideOverride { return try await decideOverride(goal,observation,candidates,history,advisory) }
        return try await jev.decide(goal:goal,observation:observation,candidates:candidates,history:history,advisory:advisory)
    }
    private func perform(_ action: Action, observation: Observation, allowedApps: [String]) async throws {
        if let performOverride { return try await performOverride(action,observation,allowedApps) }
        try await native.execute(action,observation:observation,allowedApps:allowedApps)
    }
    func candidates(_ spec: TaskSpec, _ obs: Observation, texts: [String], generated: Bool, inspected: Bool, extra: [Action]) -> [Candidate] {
        var result: [Candidate] = []
        if (!spec.generateText || generated) && (!spec.inspectImage || inspected) { result.append(Candidate(id: "done", description: "All goal requirements are observed complete now", action: nil)) }
        result.append(Candidate(id: "blocked", description: "Cannot advance using available candidates/evidence; needs user or richer candidate coverage", action: nil))
        func add(_ action: Action, _ description: String) { result.append(Candidate(id: "a\(result.count)", description: description, action: action)) }
        let targetApp = obs.target?.bundle ?? obs.front?.bundle
        for app in spec.apps where targetApp != app { add(Action(kind: "launch", app: app), "Select app \(app) as the automation target; launch in background if necessary") }
        if spec.generateText && !generated { result.append(Candidate(id: "delegateText", description: "Generate requested original text using Codex, without UI execution; native workflow resumes afterward", action: nil)) }
        if spec.inspectImage && !inspected { result.append(Candidate(id: "delegateVision", description: "Inspect current desktop screenshot using Codex vision for visual context/coordinate proposals; native workflow resumes afterward", action: nil)) }
        for action in spec.actions where ["openFile", "launch", "activate"].contains(action.kind) { add(action,action.label ?? "\(action.kind) \(action.path ?? action.app ?? "")") }
        guard spec.apps.contains(targetApp ?? "") else { return result }
        for window in obs.windows where window.id != obs.selectedWindow?.id { add(Action(kind: "selectWindow", label: "Select window \(window.title)", windowID: window.id), "Select automation window \(window.id) \(window.title) without activating the user's desktop") }
        for (index,text) in texts.enumerated() { add(Action(kind: "type", text: text), "Type provided/generated payload \(index+1) (\(text.utf16.count) UTF-16 units) into CURRENT focused field. Preview: \(text.prefix(240))") }
        for action in spec.actions.filter({ !["openFile", "launch", "activate"].contains($0.kind) }) + extra { add(action, action.label ?? String(decoding: (try? jsonData(action)) ?? Data(), as: UTF8.self)) }
        for (key, mods, label) in [("n", ["cmd"], "New document/window"), ("a", ["cmd"], "Select all in focused field"), ("f", ["cmd"], "Find"), ("return", [], "Return/confirm"), ("escape", [], "Dismiss/cancel"), ("tab", [], "Next focus"), ("tab", ["shift"], "Previous focus"), ("down", [], "Down"), ("up", [], "Up")] { add(Action(kind: "key", key: key, modifiers: mods), label) }
        add(Action(kind: "scroll", amount: -5), "Scroll down"); add(Action(kind: "scroll", amount: 5), "Scroll up"); add(Action(kind: "wait", amount: 500), "Wait for UI to settle")
        // Choice supports at most 255 options. Prioritize visible actionable nodes, not generic containers.
        for node in obs.nodes where node.enabled {
            if result.count >= 245 { break }
            if let frame = node.frame, frame.width <= 0 || frame.height <= 0 { continue }
            if node.actions.contains("AXPress") { add(Action(kind: "press", target: node.id), "Press \(node.id) \(node.role) \(node.subrole) \(node.title) value=\(node.value.prefix(100))") }
            else if ["AXTextField", "AXTextArea", "AXComboBox"].contains(node.role) { add(Action(kind: "focus", target: node.id), "Focus editable \(node.id) \(node.title)") }
            else if node.actions.contains("AXRaise") { add(Action(kind: "raise", target: node.id), "Raise window \(node.title)") }
        }
        return Array(result.prefix(255))
    }
    func run(spec: TaskSpec, directory: String, model: String?, appSelection: AppResolution? = nil, control: RunControl? = nil) async throws -> RunReport {
        guard !spec.apps.isEmpty, spec.maxSteps > 0, (0...1).contains(spec.confidence), spec.maxRecovery >= 0 else { throw Failure("Invalid task bounds/empty app allowlist") }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); try writeJSON(spec, directory + "/task.json"); try writeJSON([Step](), directory + "/steps.json")
        native.sessionApp = spec.apps.first
        var history: [Step] = [], texts = spec.texts, generated = false, inspected = false, extra: [Action] = [], recovery = 0, status = "step_limit", finalPath = ""
        var visionSnapshot:Observation?; var advisory:[String:String]?
        func cancelled() -> Bool { control?.isCancelled == true || native.preview?.cancelRequested == true || Task.isCancelled }
        func phase(_ text: String) { native.preview?.phase(text); control?.status(text) }
        for index in 0..<spec.maxSteps {
            if cancelled() { status = "cancelled"; break }
            let stepDir = directory + "/step-\(index)"; try FileManager.default.createDirectory(atPath: stepDir, withIntermediateDirectories: true)
            let obs = try await observe(directory: stepDir); let obsPath = stepDir + "/observation.json"; try writeJSON(obs, obsPath); finalPath = obsPath
            if cancelled() { status = "cancelled"; break }
            if let previous=visionSnapshot, !stableTargetState(previous,obs) || previous.windowCapture?.imageSHA256 != obs.windowCapture?.imageSHA256 { inspected=false; extra=[]; advisory=nil; visionSnapshot=nil }
            let choices = candidates(spec, obs, texts: texts, generated: generated, inspected: inspected, extra: extra)
            try writeJSON(choices, stepDir + "/candidates.json")
            var step = Step(index: index, observation: obsPath)
            do {
                var decisionObservation = obs
                if !spec.apps.contains((obs.target ?? obs.front)?.bundle ?? "") { decisionObservation.nodes = []; decisionObservation.displays = [] }
                phase("JEV deciding · step \(index + 1)")
                var decision = try await decide(goal: spec.goal, observation: decisionObservation, candidates: choices, history: history,advisory:advisory); step.decision = decision
                try writeJSON(decision, stepDir + "/decision.json")
                if cancelled() { status = "cancelled"; history.append(step); break }
                if decision.choice == "blocked" { status = "blocked"; history.append(step); break }
                if decision.confidence < spec.confidence {
                    let selected = choices.first { $0.id == decision.choice }!
                    let (probability, verifyMS, usage) = try await jev.verifyProgress(goal:spec.goal,observation:decisionObservation,candidate:selected,history:history,directory:stepDir)
                    decision.progressProbability=probability; decision.verificationApiMS=verifyMS
                    for (key,value) in usage { decision.usage[key,default:0] += value }
                    step.decision=decision; try writeJSON(decision,stepDir+"/decision.json")
                    if cancelled() { status = "cancelled"; history.append(step); break }
                    if probability < 0.85 { step.error="Uncertain selection: Choice confidence \(decision.confidence), progress probability \(probability). No identical-state retry."; status="uncertain"; history.append(step); break }
                }
                if decision.choice == "done" {
                    let appOK = spec.expectApp.map { obs.target?.bundle == $0 } ?? true
                    let evidence = obs.nodes.map { $0.title + "\n" + $0.value }.joined(separator: "\n") + "\n" + (obs.windowCapture?.ocr ?? []).joined(separator: "\n")
                    let textOK = spec.expectText.map { evidence.contains($0) } ?? true
                    if appOK && textOK { status = spec.expectApp == nil && spec.expectText == nil ? "jev_observed_complete" : "verified_complete"; history.append(step); break }
                    throw Failure("JEV completion rejected by deterministic postcondition")
                }
                if decision.choice == "delegateText" || decision.choice == "delegateVision" {
                    let image = decision.choice == "delegateVision" ? (obs.windowCapture?.screenshot ?? obs.displays.first?.screenshot) : nil
                    if decision.choice == "delegateVision", image == nil { throw Failure("No screenshot for vision delegate") }
                    let context = "\(spec.goal)\nMode: \(decision.choice).\nTarget window mapping: \(String(decoding: try jsonData(obs.windowCapture), as: UTF8.self)).\nDisplay coordinate mapping: \(String(decoding: try jsonData(obs.displays), as: UTF8.self)).\nAllowed apps: \(spec.apps).\nTarget app: \(obs.target?.bundle ?? "unknown").\nGenerate only requested text when delegateText. For delegateVision inspect the screenshot and propose native actions only if needed; do not generate text."
                    phase("Codex \(decision.choice == "delegateText" ? "writing" : "inspecting image")")
                    let start = Date(); let handoff = try await Codex().invoke(goal: context, image: image, directory: stepDir, model: model); step.executionMS = milliseconds(start)
                    try writeJSON(handoff, stepDir + "/handoff.json")
                    if cancelled() { status = "cancelled"; history.append(step); break }
                    if decision.choice == "delegateText" { if !handoff.text.isEmpty { texts.append(handoff.text) }; generated = true }
                    else { inspected = true; for action in handoff.actions { try validateAction(action, apps: spec.apps) }; extra = handoff.actions; visionSnapshot=obs; advisory=["text":handoff.observation,"sourceObservation":obs.id,"imageSHA256":obs.windowCapture?.imageSHA256 ?? "desktop capture"] }
                    // Delegate observations are advisory. Reobserve before JEV selects any proposal.
                } else {
                    guard let selected = choices.first(where: { $0.id == decision.choice }), var action = selected.action else { throw Failure("Missing selected action") }; action.label = selected.description; step.action = action
                    // Reobserve immediately before execution. Input coordinate proposals expire on UI changes.
                    if !["launch", "activate", "openFile", "selectWindow", "wait"].contains(action.kind) {
                        let pointerAction=["click","doubleClick","rightClick","move","drag","scroll"].contains(action.kind)
                        let fresh = try await observe(directory: nil, images: pointerAction)
                        guard stableTargetState(obs, fresh, action: action) else { throw Failure("Target UI changed during decision; selection discarded") }
                        if pointerAction, obs.windowCapture?.imageSHA256 != fresh.windowCapture?.imageSHA256 { throw Failure("Target image changed during decision; coordinate action discarded") }
                    }
                    if cancelled() { status = "cancelled"; step.action = nil; history.append(step); break }
                    phase("Executing \(action.kind) · step \(index + 1)")
                    let start = Date(); try await perform(action, observation: obs, allowedApps: spec.apps); step.executionMS = milliseconds(start)
                    if action.kind == "type" { texts.removeAll { $0 == action.text } }
                    extra = [] // never retain screenshot-coordinate proposals after an action
                }
                try await Task.sleep(nanoseconds: UInt64(max(0, min(spec.settleMS, 5000))) * 1_000_000)
                let afterDir = stepDir + "/after"; try FileManager.default.createDirectory(atPath: afterDir, withIntermediateDirectories: true)
                let after = try await observe(directory: afterDir); let afterPath = afterDir + "/observation.json"; try writeJSON(after, afterPath); step.afterObservation = afterPath; finalPath = afterPath
                if !["wait", "selectWindow"].contains(step.action?.kind ?? ""), step.action != nil, after.target?.pid == obs.target?.pid, after.nodes == obs.nodes { recovery += 1; step.error = "No AX change observed; result is not proven (screenshot may differ)" } else { recovery = 0 }
            } catch {
                if cancelled() || error is CancellationError { status = "cancelled"; history.append(step); break }
                recovery += 1; step.error = String(describing: error)
            }
            history.append(step); try writeJSON(history, directory + "/steps.json")
            if recovery > spec.maxRecovery { status = "recovery_exhausted"; break }
        }
        phase("Finished: \(status)")
        let report = RunReport(status: status, goal: spec.goal, steps: history, finalObservation: finalPath, directory: directory, apps: spec.apps, appSelection: appSelection); try writeJSON(report, directory + "/report.json"); return report
    }
}
