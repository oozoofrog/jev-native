import AppKit
import ApplicationServices
import CryptoKit
import EventKit

struct SetupState: Equatable {
    var checking = false; var permissions:[String:Bool] = [:]
    var codexInstalled = false; var codexAuthenticated = false
    var keyConfigured = false; var keyVerified = false; var calendarAuthorized = false
    var detail = "필요한 설정을 확인하고 있어요."; var failure:String?
    var ready:Bool { codexInstalled && codexAuthenticated && keyVerified && permissions["accessibility"] == true && permissions["screenRecording"] == true && permissions["inputPosting"] == true }
    var canPlan:Bool { codexInstalled && codexAuthenticated && keyVerified }
    var rows:[String] {
        func row(_ ready:Bool,_ label:String) -> String { (ready ? "✓ " : "○ ")+label }
        return [row(permissions["accessibility"] == true,"접근성 · 앱의 버튼과 텍스트 확인"),row(permissions["screenRecording"] == true,"화면 기록 · 대상 창 확인"),row(permissions["inputPosting"] == true,"입력 권한 · 대상 창에 입력"),row(codexInstalled,"Codex 실행 도구"),row(codexAuthenticated,"Codex 로그인 · 원문 해석과 결과 작성"),row(keyVerified,"TypeSafe 연결 · 작업 경로와 다음 동작 선택"),row(calendarAuthorized,"캘린더 · 일정 저장과 저장 결과 재조회")]
    }
}

@MainActor final class SetupCoordinator {
    private(set) var state = SetupState()
    var onChange:() -> Void = {}
    private var task:Task<Void,Never>?
    private var login:Process?
    private let calendar = ResearchCalendar()
    private var connectionVerifiedAt:Date?
    private var credentialFingerprint:String?
    func check(forceConnection:Bool = false) {
        guard task == nil else { return }
        task = Task { @MainActor in
            state.checking = true; state.failure = nil; changed()
            defer { state.checking = false; task = nil; changed() }
            state.permissions = Native().permissions(); state.calendarAuthorized = calendar.authorized
            let loaded = try? credential(); state.keyConfigured = loaded != nil
            let fingerprint = loaded.map { SHA256.hash(data:Data($0.utf8)).map { String(format:"%02x",$0) }.joined() }
            if credentialFingerprint != fingerprint { state.keyVerified = false; connectionVerifiedAt = nil; credentialFingerprint = fingerprint }
            do {
                if (try? Codex()) == nil {
                    state.detail = "공식 Codex 실행 도구를 준비하고 있어요. 다운로드한 파일의 SHA-256을 확인합니다."; changed()
                    try await CodexRuntime.install()
                }
                let codex = try Codex(); state.codexInstalled = true
                state.codexAuthenticated = try await Self.loginStatus(codex.executable)
                if state.keyConfigured, forceConnection || connectionVerifiedAt == nil || Date().timeIntervalSince(connectionVerifiedAt!) > 300 {
                    state.keyVerified = false
                    state.detail = "TypeSafe 연결을 실제 요청으로 확인하고 있어요."; changed()
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jev-connection-"+UUID().uuidString)
                    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); defer { try? FileManager.default.removeItem(at:dir) }
                    let result = try await Jev().researchChoice(request:"Connection verification. Select ready.",criteria:["ready":"Connection verification succeeded"],directory:dir.path,name:"connection")
                    state.keyVerified = result == "ready"; connectionVerifiedAt = Date()
                }
                if !state.keyConfigured { state.keyVerified = false; connectionVerifiedAt = nil }
                state.detail = state.ready ? "준비됐어요. 요청하면 필요한 경로를 자동으로 선택하고 실행합니다." : state.canPlan ? "CLI와 웹 작업은 준비됐어요. 네이티브 앱 작업에는 표시된 macOS 권한이 필요합니다." : "표시된 항목을 준비하면 첫 작업을 시작할 수 있어요. 권한 승인과 로그인은 직접 진행해 주세요."
            } catch { state.failure = String(describing:error); state.detail = "설정을 완료하지 못했어요. 아래 항목을 확인한 뒤 다시 점검해 주세요." }
        }
    }
    private func changed() { onChange() }
    func requestPermissions() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key:true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess() }
        check()
    }
    func openPermissionSettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    func requestCalendar() {
        Task { @MainActor in do { try await calendar.requestAccess(); check() } catch { state.failure = String(describing:error); changed() } }
    }
    func signIn() {
        guard login == nil, let codex = try? Codex() else { return }
        let process = Process(); process.executableURL = URL(fileURLWithPath:codex.executable); process.arguments = ["login"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); login = process; state.detail = "브라우저에서 Codex 로그인을 완료해 주세요. 돌아오면 로그인 상태를 다시 확인합니다."; changed()
            Task { @MainActor in
                while process.isRunning { try? await Task.sleep(nanoseconds:300_000_000) }
                login = nil; check()
            }
        } catch { state.failure = "Codex 로그인 창을 열지 못했습니다."; changed() }
    }
    func cancel() { task?.cancel(); if login?.isRunning == true { login?.terminate() }; login = nil }
    static func loginStatus(_ executable:String) async throws -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = ["login","status"]
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); defer { if p.isRunning { p.terminate() } }; let start = Date()
        while p.isRunning { try Task.checkCancellation(); guard Date().timeIntervalSince(start) < 10 else { throw Failure("Codex 로그인 상태 확인 시간이 초과됐습니다.") }; try await Task.sleep(nanoseconds:100_000_000) }
        return p.terminationStatus == 0
    }
}

/// Install only to the app's private runtime directory. Existing executables/configuration stay intact.
enum CodexRuntime {
    static func install() async throws {
        #if arch(arm64)
        let name = "codex-aarch64-apple-darwin.tar.gz", binary = "codex-aarch64-apple-darwin"
        #else
        let name = "codex-x86_64-apple-darwin.tar.gz", binary = "codex-x86_64-apple-darwin"
        #endif
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/JEV Native/Runtime")
        let target = root.appendingPathComponent("codex")
        if FileManager.default.isExecutableFile(atPath:target.path) { return }
        guard !FileManager.default.fileExists(atPath:target.path) else { throw Failure("앱 전용 Codex 경로에 기존 파일이 있습니다. 해당 파일을 직접 확인해 주세요.") }
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration:configuration)
        var req = URLRequest(url:URL(string:"https://api.github.com/repos/openai/codex/releases/latest")!); req.setValue("JEVNative-setup",forHTTPHeaderField:"User-Agent")
        let (data,response) = try await session.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try JSONSerialization.jsonObject(with:data) as? [String:Any], let assets = release["assets"] as? [[String:Any]],
              let asset = assets.first(where:{$0["name"] as? String == name}), let digest = asset["digest"] as? String, digest.hasPrefix("sha256:"),
              let size = asset["size"] as? Int, size > 0, size <= 200_000_000,
              let value = asset["browser_download_url"] as? String, let url = URL(string:value), url.scheme == "https", url.host == "github.com", url.path.hasPrefix("/openai/codex/releases/download/") else { throw Failure("공식 Codex 다운로드 정보와 해시를 확인하지 못했습니다.") }
        let (download,response2) = try await session.download(from:url)
        defer { try? FileManager.default.removeItem(at:download) }
        guard (response2 as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("Codex 다운로드에 실패했습니다.") }
        let archive = try Data(contentsOf:download,options:.mappedIfSafe)
        let actual = SHA256.hash(data:archive).map { String(format:"%02x",$0) }.joined()
        guard archive.count == size, "sha256:"+actual == digest else { throw Failure("Codex 다운로드 파일의 크기 또는 SHA-256이 일치하지 않습니다.") }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let staging = root.appendingPathComponent(".prepare-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); defer { try? FileManager.default.removeItem(at:staging) }
        // Extract exactly the expected member; never unpack arbitrary archive paths or links.
        let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/bin/tar"); p.arguments = ["-xzf",download.path,"-C",staging.path,binary]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; try p.run(); defer { if p.isRunning { p.terminate() } }
        while p.isRunning { try Task.checkCancellation(); try await Task.sleep(nanoseconds:100_000_000) }
        let extracted = staging.appendingPathComponent(binary)
        let attrs = try FileManager.default.attributesOfItem(atPath:extracted.path)
        guard p.terminationStatus == 0, attrs[.type] as? FileAttributeType == .typeRegular else { throw Failure("Codex 실행 파일을 안전하게 풀지 못했습니다.") }
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:extracted.path)
        try FileManager.default.moveItem(at:extracted,to:target)
    }
}
