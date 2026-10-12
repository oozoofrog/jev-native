import AppKit
import Foundation
import Darwin

enum GUIEntry: Equatable { case command, activateApplication, applicationHost }

struct GUIActivation {
    static let originKey = "JEV_GUI_LAUNCH_ORIGIN"
    static let originValue = "launchservices"
    static let optionsKey = "JEV_GUI_START_OPTIONS"

    // The signed LSEnvironment value distinguishes a default app launch from a bare CLI.
    // It is a routing hint, not an authorization token; explicit --gui always uses the OS.
    static func entry(_ arguments:[String], bundled:Bool, environment:[String:String]) -> GUIEntry {
        if arguments.first == "--gui" { return .activateApplication }
        if arguments.isEmpty && bundled {
            return environment[originKey] == originValue ? .applicationHost : .activateApplication
        }
        return .command
    }

    static func consumeLaunchEnvironment() -> [String:String] {
        let environment=ProcessInfo.processInfo.environment
        unsetenv(originKey);unsetenv(optionsKey)
        return environment
    }

    static func activationOptions(arguments:[String],workingDirectory:String) throws -> GUIOptions {
        var options=try GUIOptions(arguments:arguments.isEmpty ? ["--gui"] : arguments)
        if let directory=options.workingDirectory {
            let expanded=(directory as NSString).expandingTildeInPath
            options.workingDirectory=URL(fileURLWithPath:expanded,relativeTo:URL(fileURLWithPath:workingDirectory,isDirectory:true)).standardizedFileURL.path
        }
        return options
    }

    struct LaunchContext: Codable, Equatable {
        let schema:Int
        let options:GUIOptions
        let workingDirectory:String
    }
    static func startContext(environment:[String:String]) throws -> LaunchContext? {
        guard let payload=environment[optionsKey] else { return nil }
        let context=try JSONDecoder().decode(LaunchContext.self,from:Data(payload.utf8))
        guard context.schema==1,context.workingDirectory.hasPrefix("/") else { throw Failure("Invalid GUI launch working-directory context") }
        return context
    }
    static func startOptions(environment:[String:String]) throws -> GUIOptions {
        if let context=try startContext(environment:environment) { return context.options }
        return try GUIOptions(arguments:["--gui"])
    }

    static func hostOptions(environment:[String:String]) throws -> GUIOptions {
        guard let context=try startContext(environment:environment) else { return try GUIOptions(arguments:["--gui"]) }
        var options=context.options
        options.launchWorkingDirectory=context.workingDirectory
        return options
    }

    struct Target: Equatable {
        let bundleURL:URL
        let executableURL:URL
        init(execution:StartupExecutionIdentity) throws {
            let executable=URL(fileURLWithPath:execution.canonicalExecutable).standardizedFileURL.resolvingSymlinksInPath()
            guard let path=execution.bundlePath, execution.bundleIdentifier == CompiledProduct.bundleIdentifier else { throw Failure("--gui requires the installed JevNative application bundle") }
            let bundle=URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
            guard bundle.pathExtension == "app", executable == bundle.appendingPathComponent("Contents/MacOS/"+CompiledProduct.executable) else { throw Failure("GUI bundle and executable differ") }
            bundleURL=bundle;executableURL=executable
        }
        func validate(pid:Int32,bundle:String?,bundleURL:URL?,executableURL:URL?,caller:Int32,expectedOwner:Int32? = nil) throws {
            guard pid>0,pid != caller,(expectedOwner == nil || pid == expectedOwner),bundle == CompiledProduct.bundleIdentifier,
                  bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == self.bundleURL,
                  executableURL?.standardizedFileURL.resolvingSymlinksInPath() == self.executableURL else { throw Failure("GUI activation returned another app or the CLI launcher; no new instance retry") }
        }
    }

    struct Result: Encodable {
        let pid:Int32
        let bundlePath:String
        let executablePath:String
        let createsNewApplicationInstance=false
        let allowsRunningApplicationSubstitution=false
        let optionsScope="new-application-launch-only; existing draft and work preserved"
    }

    static func launchEnvironment(options:GUIOptions,workingDirectory:String = FileManager.default.currentDirectoryPath) throws -> [String:String] {
        let payload=try JSONEncoder().encode(LaunchContext(schema:1,options:options,workingDirectory:workingDirectory))
        return [originKey:originValue,optionsKey:String(decoding:payload,as:UTF8.self)]
    }

    @MainActor static func activate(execution:StartupExecutionIdentity,options:GUIOptions) async throws -> Result {
        let target=try Target(execution:execution)
        let expectedOwner=try ownerPID(execution:execution)
        let config=NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance=false
        config.allowsRunningApplicationSubstitution=false
        config.activates=true
        config.hides=false;config.hidesOthers=false
        config.arguments=[]
        config.environment=try launchEnvironment(options:options)
        let app=try await NSWorkspace.shared.openApplication(at:target.bundleURL,configuration:config)
        try target.validate(pid:app.processIdentifier,bundle:app.bundleIdentifier,bundleURL:app.bundleURL,executableURL:app.executableURL,caller:getpid(),expectedOwner:expectedOwner)
        // Re-read the returned PID: an accessory CLI helper is never accepted as the workshop.
        // No child is killed on an unknown/late startup, and no new-instance fallback is used.
        let deadline=Date().addingTimeInterval(10)
        while Date()<deadline {
            guard let current=NSRunningApplication(processIdentifier:app.processIdentifier),!current.isTerminated else { throw Failure("GUI application exited during activation") }
            try target.validate(pid:current.processIdentifier,bundle:current.bundleIdentifier,bundleURL:current.bundleURL,executableURL:current.executableURL,caller:getpid(),expectedOwner:expectedOwner)
            guard processRole(pid:current.processIdentifier) == .workshop else { throw Failure("GUI activation returned a non-workshop command process; its work is preserved") }
            if current.activationPolicy == .regular {
                return Result(pid:current.processIdentifier,bundlePath:target.bundleURL.path,executablePath:target.executableURL.path)
            }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        throw Failure("GUI activation remains unverified; inspect the existing process before retrying")
    }

    enum ProcessRole: Equatable { case workshop, command, unavailable }
    static func processRole(argumentCount:Int?) -> ProcessRole {
        guard let count=argumentCount,count>0,count<256 else { return .unavailable }
        // The GUI host always has only argv[0]. Preview/calendar/run/native commands
        // retain their explicit command arguments and cannot impersonate its role.
        return count == 1 ? .workshop : .command
    }
    static func processRole(pid:pid_t) -> ProcessRole {
        var mib:[Int32]=[CTL_KERN,KERN_PROCARGS2,pid],length=0
        guard sysctl(&mib,3,nil,&length,nil,0)==0,length>=4 else { return .unavailable }
        var bytes=[UInt8](repeating:0,count:length)
        guard sysctl(&mib,3,&bytes,&length,nil,0)==0 else { return .unavailable }
        // Read only argc, never arguments, goals, keys or the environment from this buffer.
        let argc=bytes.withUnsafeBytes { $0.loadUnaligned(as:Int32.self) }
        return processRole(argumentCount:Int(argc))
    }
    static func validatedOwner(_ roles:[(pid:Int32,role:ProcessRole)]) throws -> Int32? {
        guard !roles.contains(where:{$0.role != .workshop}),roles.count<=1 else { throw Failure("Existing JevNative app role is ambiguous or non-workshop; preserve its work and close it normally before GUI activation") }
        return roles.first?.pid
    }
    @MainActor static func ownerPID(execution:StartupExecutionIdentity) throws -> Int32? {
        let target=try Target(execution:execution)
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:CompiledProduct.bundleIdentifier).filter {
            $0.processIdentifier != getpid() && !$0.isTerminated && $0.activationPolicy != .prohibited &&
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == target.bundleURL &&
            $0.executableURL?.standardizedFileURL.resolvingSymlinksInPath() == target.executableURL
        }
        return try validatedOwner(apps.map { (pid:$0.processIdentifier,role:processRole(pid:$0.processIdentifier)) })
    }
}
