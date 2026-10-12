import Foundation
import CryptoKit
import Darwin

struct LocalTool: Codable, Equatable {
    var name: String
    var executable: String
    var operations: String
}

enum LocalTools {
    static let operations: [String:String] = [
        "pwd":"Print working directory", "ls":"List workspace files", "cat":"Read workspace text files",
        "wc":"Count lines/words/bytes", "head":"Read first lines", "tail":"Read last lines",
        "rg":"Search text or list files; no preprocessors", "git":"Read status/diff/log/show/ls-files/rev-parse; no writes",
        "swift":"Build or test a Swift package; describe/show-dependencies/dump-package",
        "xcodebuild":"List/build/test/analyze a project; no install/archive/export",
        "xcrun":"Find a developer tool or print SDK information; no arbitrary execution",
        "sips":"Convert/resize an image to a new output file", "ffmpeg":"Convert local media to a new output file",
        "ffprobe":"Inspect local media", "shasum":"Compute file SHA digest", "diff":"Compare workspace text files",
        "file":"Inspect workspace file types", "du":"Measure workspace disk usage"
    ]
    static func discover(environment: [String:String] = ProcessInfo.processInfo.environment) -> [LocalTool] {
        let folders = environment["PATH",default:""] .split(separator:":").map(String.init)
            + [NSHomeDirectory()+"/.local/bin","/opt/homebrew/bin","/usr/local/bin","/usr/bin","/bin"]
        return operations.keys.sorted().compactMap { name in
            guard let path = folders.filter({ $0.hasPrefix("/") }).map({ $0+"/"+name }).first(where: { FileManager.default.isExecutableFile(atPath:$0) }) else { return nil }
            return LocalTool(name:name,executable:URL(fileURLWithPath:path).resolvingSymlinksInPath().path,operations:operations[name]!)
        }
    }
}

struct LocalCommandSpec: Codable, Equatable {
    var tool: String
    var arguments: [String]
    var directory: String
    var timeoutSeconds: Double = 300
    var environment: [String:String]? = nil
    var expectedFiles: [String]? = nil
    var expectedStdout: String? = nil
    var successExitCodes: [Int32]? = nil
}

extension LocalCommandSpec {
    init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        tool = try c.decode(String.self,forKey:.tool)
        arguments = try c.decode([String].self,forKey:.arguments)
        directory = try c.decode(String.self,forKey:.directory)
        timeoutSeconds = try c.decodeIfPresent(Double.self,forKey:.timeoutSeconds) ?? 300
        environment = try c.decodeIfPresent([String:String].self,forKey:.environment)
        expectedFiles = try c.decodeIfPresent([String].self,forKey:.expectedFiles)
        expectedStdout = try c.decodeIfPresent(String.self,forKey:.expectedStdout)
        successExitCodes = try c.decodeIfPresent([Int32].self,forKey:.successExitCodes)
    }
}

struct ValidatedLocalCommand {
    var spec: LocalCommandSpec
    var executable: String
    var arguments: [String]
    var directory: String
    var environment: [String:String]
    var expectedFiles: [String]
    var successExitCodes: Set<Int32>
    var label: String { ([spec.tool]+spec.arguments).map { value in
        if value.range(of:"^[A-Za-z0-9_./:=+,-]+$",options:.regularExpression) != nil { return value }
        return "'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"
    }.joined(separator:" ") }
}

/// This is an argument/capability policy, not an operating-system filesystem sandbox.
/// A requested build/test executes that project's own code with the current user's privileges.
struct LocalCommandPolicy {
    var workspace: String
    var runDirectory: String
    var tools: [LocalTool]
    init(workspace:String,runDirectory:String,tools:[LocalTool]) {
        self.workspace = Self.canonical(workspace,relativeTo:FileManager.default.currentDirectoryPath)
        self.runDirectory = Self.canonical(runDirectory,relativeTo:self.workspace)
        self.tools = tools
    }
    static func canonical(_ path:String,relativeTo base:String) -> String { canonical(path,base:base,depth:0) }
    private static func canonical(_ path:String,base:String,depth:Int) -> String {
        guard depth < 32 else { return "/__jev_unresolved_symlink__" }
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : base+"/"+expanded
        var resolved = "/"
        // Resolve existing prefixes even when an output's final component does not exist.
        // Process '..' after resolving preceding links, matching filesystem traversal.
        for part in absolute.split(separator:"/").map(String.init) {
            if part == "." { continue }
            if part == ".." { resolved = URL(fileURLWithPath:resolved).deletingLastPathComponent().path; continue }
            let candidate = (resolved == "/" ? "" : resolved)+"/"+part
            if let pointer = realpath(candidate,nil) { resolved = String(cString:pointer); free(pointer) }
            else if let target = try? FileManager.default.destinationOfSymbolicLink(atPath:candidate) {
                resolved = canonical(target,base:resolved,depth:depth+1)
            } else { resolved = candidate }
        }
        return resolved
    }
    static func inside(_ path:String,_ root:String) -> Bool { path == root || path.hasPrefix(root+"/") }
    func path(_ value:String,cwd:String,mustExist:Bool = false) throws -> String {
        guard !value.isEmpty,!value.contains("\0"),!value.contains("://"),value != "-" else { throw Failure("지원하지 않는 로컬 파일 경로입니다.") }
        let p = Self.canonical(value,relativeTo:cwd)
        guard Self.inside(p,workspace) || Self.inside(p,runDirectory) else { throw Failure("작업 폴더 밖의 경로입니다: \(p)") }
        if mustExist && !FileManager.default.fileExists(atPath:p) { throw Failure("파일이나 폴더가 없습니다: \(p)") }
        return p
    }
    func validate(_ spec:LocalCommandSpec,requireExistingInputs:Bool = true) throws -> ValidatedLocalCommand {
        guard let tool = tools.first(where: { $0.name == spec.tool }),FileManager.default.isExecutableFile(atPath:tool.executable),
              (1...3600).contains(spec.timeoutSeconds),spec.timeoutSeconds.isFinite,
              spec.arguments.count <= 128,spec.arguments.reduce(0,{ $0+$1.utf8.count }) <= 64000,spec.arguments.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 16000 }) else { throw Failure("설치된 도구와 명령 실행 범위를 확인하지 못했습니다.") }
        if let expected = spec.expectedStdout { guard !expected.isEmpty,expected.utf8.count <= 16000 else { throw Failure("stdout 검증 문자열이 비어 있거나 너무 깁니다.") } }
        let cwd = try path(spec.directory,cwd:workspace,mustExist:true)
        var isDirectory:ObjCBool = false
        guard FileManager.default.fileExists(atPath:cwd,isDirectory:&isDirectory),isDirectory.boolValue else { throw Failure("작업 디렉터리가 아닙니다: \(cwd)") }
        let files = try (spec.expectedFiles ?? []).map { try path($0,cwd:cwd) }
        let converting = ["sips","ffmpeg"].contains(spec.tool)
        if converting {
            guard !files.isEmpty,files.allSatisfy({ !FileManager.default.fileExists(atPath:$0) }) else { throw Failure("변환 결과에는 새 파일 경로가 필요합니다. 기존 파일은 덮어쓰지 않습니다.") }
        }
        var args = spec.arguments
        func checked(_ index:Int,_ exists:Bool = false) throws { args[index] = try path(args[index],cwd:cwd,mustExist:exists && requireExistingInputs) }
        func options(_ flags:Set<String>,_ values:Set<String>,_ paths:Set<String> = [],positionals:Bool = true) throws {
            var index = 0,ended = false
            while index < args.count {
                let a = args[index]
                if !ended && a == "--" { ended = true; index += 1; continue }
                if !ended && a.hasPrefix("-") {
                    if flags.contains(a) { index += 1; continue }
                    guard values.contains(a) || paths.contains(a),index+1 < args.count else { throw Failure("지원하지 않는 \(spec.tool) 옵션입니다: \(a)") }
                    if paths.contains(a) { try checked(index+1) }
                    index += 2
                } else {
                    guard positionals else { throw Failure("지원하지 않는 \(spec.tool) 인자입니다: \(a)") }
                    try checked(index); index += 1
                }
            }
        }
        switch spec.tool {
        case "pwd": guard args.isEmpty else { throw Failure("pwd에는 인자를 전달하지 않습니다.") }
        case "ls": try options(["-l","-a","-A","-h","-la","-al","-lh","-lah","-R","-1","-d","-F"],[])
        case "cat": try options(["-n","-b","-s","-v","-e","-t"],[])
        case "wc": try options(["-l","-w","-c","-m"],[])
        case "head","tail": try options([], ["-n","-c"])
        case "file": try options(["-b","--mime","--mime-type","-I"],[])
        case "du": try options(["-h","-s","-k","-sh","-sk"],["-d"])
        case "shasum": try options([], ["-a","--algorithm"])
        case "diff": try options(["-u","-q","-r","-N","-w","-b","--brief"],[])
        case "rg":
            let flags:Set<String> = ["--files","--hidden","--no-ignore","--no-config","--line-number","-n","-i","--ignore-case","-l","--files-with-matches","--count","-c","--fixed-strings","-F","--json","--stats","--no-heading","--with-filename","-H","--multiline","-U"]
            let values:Set<String> = ["-g","--glob","-t","--type","--max-count","-m","--max-depth","-A","-B","-C","--context","--color"]
            var i = 0,pattern = args.contains("--files"),ended = false
            while i < args.count {
                let a = args[i]
                if !ended && a == "--" { ended = true; i += 1; continue }
                if !ended && a.hasPrefix("-") {
                    if flags.contains(a) { i += 1; continue }
                    guard values.contains(a),i+1 < args.count else { throw Failure("지원하지 않는 rg 옵션입니다: \(a)") }
                    i += 2
                } else { if pattern { try checked(i) } else { pattern = true }; i += 1 }
            }
            guard pattern else { throw Failure("검색 패턴이 없습니다.") }; args.insert("--no-config",at:0)
        case "git":
            guard let operation = args.first,["status","diff","log","show","ls-files","rev-parse"].contains(operation) else { throw Failure("git 조회 명령만 지원합니다.") }
            let simple:Set<String> = ["--short","--porcelain","--porcelain=v1","--porcelain=v2","--branch","--stat","--name-only","--name-status","--numstat","--cached","--staged","--oneline","--no-color","--exit-code","--check","--show-toplevel","--show-prefix","--is-inside-work-tree","--verify","--abbrev-ref","--no-ext-diff","--no-textconv"]
            var i = 1,paths = false
            while i < args.count {
                let a = args[i]
                if a == "--" { paths = true; i += 1; continue }
                if paths || a.hasPrefix("/") || a.hasPrefix("~/") || a.hasPrefix("./") || a.hasPrefix("../") { try checked(i) }
                else if a == "-n" { guard i+1 < args.count,Int(args[i+1]) != nil else { throw Failure("git 기록 수가 필요합니다.") }; i += 1 }
                else if a.hasPrefix("-") && !simple.contains(a) && a.range(of:"^--(max-count|format|pretty|untracked-files)=",options:.regularExpression) == nil { throw Failure("지원하지 않는 git 옵션입니다: \(a)") }
                i += 1
            }
            if ["diff","show","log"].contains(operation) { args.insert(contentsOf:["--no-ext-diff","--no-textconv"],at:1) }
            args.insert(contentsOf:["--no-pager","-c","core.fsmonitor=false","-c","core.hooksPath=/dev/null"],at:0)
        case "swift":
            guard let op = args.first,["build","test","package"].contains(op) else { throw Failure("Swift build/test/package 조회만 지원합니다.") }
            var count = 1
            if op == "package" { guard args.count > 1,["describe","show-dependencies","dump-package"].contains(args[1]) else { throw Failure("Swift package 조회만 지원합니다.") }; count = 2 }
            let prefix = Array(args.prefix(count)); args = Array(args.dropFirst(count))
            try options(["--parallel","--skip-build","--enable-code-coverage","--verbose","-v","--disable-automatic-resolution"],["-c","--configuration","--filter","--skip","--jobs","-j"],["--package-path","--scratch-path"],positionals:false)
            args = prefix+args
        case "xcrun":
            guard args.count == 1 && ["--show-sdk-path","--show-sdk-version","--show-sdk-platform-path"].contains(args[0]) || args.count == 2 && args[0] == "--find" && LocalTools.operations[args[1]] != nil else { throw Failure("xcrun의 도구 경로·SDK 조회만 지원합니다.") }
        case "xcodebuild":
            let flags:Set<String> = ["build","test","analyze","-list","-showBuildSettings","-quiet","-json","-disableAutomaticPackageResolution"]
            let values:Set<String> = ["-scheme","-configuration","-destination","-sdk","-jobs","-only-testing","-skip-testing"]
            let paths:Set<String> = ["-project","-workspace","-derivedDataPath","-resultBundlePath","-clonedSourcePackagesDirPath"]
            var i = 0
            while i < args.count {
                let a = args[i]
                if flags.contains(a) || a == "CODE_SIGNING_ALLOWED=NO" { i += 1; continue }
                guard values.contains(a) || paths.contains(a),i+1 < args.count else { throw Failure("지원하지 않는 xcodebuild 인자입니다: \(a)") }
                if paths.contains(a) { try checked(i+1) }; i += 2
            }
            if !args.contains("-derivedDataPath") { args += ["-derivedDataPath",runDirectory+"/DerivedData"] }
        case "sips":
            var i = 0,inputs = 0,out:String?
            while i < args.count {
                let a = args[i]
                if ["-s","--setProperty"].contains(a) {
                    guard i+2 < args.count,args[i+1] == "format",["jpeg","png","tiff","bmp","gif","jp2","heic"].contains(args[i+2]) else { throw Failure("sips format과 지원하는 출력 형식이 필요합니다.") }; i += 3
                } else if ["-Z","--resampleHeightWidthMax","--resampleWidth","--resampleHeight"].contains(a) {
                    guard i+1 < args.count,let size = Int(args[i+1]),(1...100000).contains(size) else { throw Failure("이미지 크기 값이 올바르지 않습니다.") }; i += 2
                } else if a == "--out" {
                    guard i+1 < args.count,out == nil else { throw Failure("이미지 출력 경로가 필요합니다.") }; try checked(i+1); out = args[i+1]; i += 2
                } else {
                    guard !a.hasPrefix("-") else { throw Failure("지원하지 않는 sips 옵션입니다: \(a)") }; try checked(i,true); inputs += 1; i += 1
                }
            }
            guard inputs == 1,let out,files == [out] else { throw Failure("sips --out과 검증할 새 파일이 일치해야 합니다.") }
        case "ffmpeg","ffprobe":
            let flags:Set<String> = ["-n","-hide_banner","-nostats","-vn","-an","-sn","-show_format","-show_streams","-show_entries"]
            let values:Set<String> = ["-c:v","-c:a","-codec:v","-codec:a","-crf","-preset","-b:v","-b:a","-s","-r","-ar","-ac","-pix_fmt","-t","-ss","-to","-f","-map","-frames:v","-vframes","-loglevel","-v","-of","-print_format","-show_entries"]
            var i = 0,outputs:[String] = []
            while i < args.count {
                let a = args[i]
                if a == "-i" { guard i+1 < args.count else { throw Failure("입력 파일이 없습니다.") }; try checked(i+1,true); i += 2 }
                else if values.contains(a) { guard i+1 < args.count else { throw Failure("옵션 값이 없습니다.") }; i += 2 }
                else if flags.contains(a) { i += 1 }
                else if a.hasPrefix("-") { throw Failure("지원하지 않는 미디어 옵션입니다: \(a)") }
                else { try checked(i,spec.tool == "ffprobe"); if spec.tool == "ffmpeg" { outputs.append(args[i]) }; i += 1 }
            }
            if spec.tool == "ffmpeg" { guard Set(outputs) == Set(files) else { throw Failure("미디어 출력 파일과 검증할 파일이 일치해야 합니다.") }; args.insert(contentsOf:["-nostdin","-n","-protocol_whitelist","file,pipe"],at:0) }
        default: throw Failure("지원하지 않는 실행 도구입니다.")
        }
        let allowedEnvironment:Set<String> = ["LANG","LC_ALL","LC_CTYPE","CI","NO_COLOR","TERM"]
        guard (spec.environment ?? [:]).allSatisfy({ allowedEnvironment.contains($0.key) && !$0.value.contains("\0") && $0.value.utf8.count < 1024 }) else { throw Failure("지원하지 않는 명령 환경 변수입니다.") }
        let inherited = ProcessInfo.processInfo.environment
        var env = inherited.filter { ["HOME","USER","LOGNAME","TMPDIR","DEVELOPER_DIR","SDKROOT"].contains($0.key) }
        env["PATH"] = Array(Set(tools.map { URL(fileURLWithPath:$0.executable).deletingLastPathComponent().path })).sorted().joined(separator:":")
        env["LANG"] = "en_US.UTF-8"; env["TERM"] = "dumb"; env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_CONFIG_NOSYSTEM"] = "1"; env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env.merge(spec.environment ?? [:]) { _,new in new }
        let exits = Set(spec.successExitCodes ?? [0]),permitted:Set<Int32> = ["rg","diff"].contains(spec.tool) ? [0,1] : [0]
        guard !exits.isEmpty,exits.isSubset(of:permitted) else { throw Failure("지원하지 않는 정상 종료 코드입니다.") }
        return ValidatedLocalCommand(spec:spec,executable:tool.executable,arguments:args,directory:cwd,environment:env,expectedFiles:files,successExitCodes:exits)
    }
}
