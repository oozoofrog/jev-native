import Foundation
import Darwin

struct LocalCLIOptions {
    var goal:String
    var workspace:String
    var directory:String
    var model:String?
    var planPath:String?
    init(_ arguments:[String]) throws {
        var values:[String:String] = [:],index = 0
        let flags:Set<String> = ["--goal","--directory","--out","--plan","--codex-model"]
        while index < arguments.count {
            let flag = arguments[index]
            guard flags.contains(flag),values[flag] == nil,index+1 < arguments.count else { throw Failure("지원하지 않거나 값이 없는 local 옵션입니다: \(flag)") }
            values[flag] = arguments[index+1]; index += 2
        }
        guard let request = values["--goal"],!request.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,request.utf16.count <= 6000 else { throw Failure("local --goal에는 1~6,000 UTF-16 코드 단위의 요청이 필요합니다.") }
        goal = request
        workspace = try LocalWorkspace.select(request:values["--directory"] == nil ? request : "",defaultDirectory:values["--directory"] ?? FileManager.default.currentDirectoryPath)
        directory = LocalCommandPolicy.canonical(values["--out"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runs/"+UUID().uuidString).path,relativeTo:FileManager.default.currentDirectoryPath)
        model = values["--codex-model"]; planPath = values["--plan"]
    }
}

@MainActor enum LocalCLI {
    static func run(_ arguments:[String]) async throws -> RunReport {
        let options = try LocalCLIOptions(arguments),control = RunControl()
        control.onStatus = { fputs($0+"\n",stderr) }; control.emit(.request(options.goal))
        let priorINT = signal(SIGINT,SIG_IGN),priorTERM = signal(SIGTERM,SIG_IGN)
        let sources = [SIGINT,SIGTERM].map { number -> DispatchSourceSignal in
            let source = DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { Task { @MainActor in control.stop() } }; source.resume(); return source
        }
        defer { sources.forEach { $0.cancel() }; _ = signal(SIGINT,priorINT); _ = signal(SIGTERM,priorTERM) }
        let plan = try options.planPath.map { try JSONDecoder().decode(LocalTaskPlan.self,from:Data(contentsOf:URL(fileURLWithPath:$0))) }
        return try await LocalTaskRunner().run(request:options.goal,workspace:options.workspace,directory:options.directory,model:options.model,control:control,suppliedPlan:plan)
    }
}
