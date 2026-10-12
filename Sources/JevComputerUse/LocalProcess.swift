import Foundation
import Darwin
import CryptoKit

struct LocalFileProof: Codable, Equatable {
    var path:String
    var bytes:Int
    var sha256:String
}

struct LocalCommandResult: Codable, Equatable {
    var index:Int
    var command:LocalCommandSpec
    var executable:String
    var executedArguments:[String]
    var pid:Int32
    var startedAt:Date
    var durationMS:Double
    var exitCode:Int32?
    var signal:Int32?
    var termination:String
    var stdoutPath:String
    var stderrPath:String
    var stdoutBytes:Int
    var stderrBytes:Int
    var verification:String
    var files:[LocalFileProof]
    var succeeded:Bool
    var error:String?
    var trackedDescendantPIDs:[Int32]? = nil
    var remainingProcessPIDs:[Int32]? = nil
}

struct LocalOutputSnapshot:Equatable {
    var stdout:String
    var stderr:String
    var stdoutBytes:Int
    var stderrBytes:Int
    var text:String { "stdout · \(stdoutBytes)바이트\n"+stdout+"\n\nstderr · \(stderrBytes)바이트\n"+stderr }
}

/// XCTest and build tools can create another process group. Track descendants by
/// PID plus kernel start time so cleanup does not signal a recycled PID.
private struct LocalProcessIdentity:Hashable {
    var pid:pid_t
    var seconds:UInt64
    var microseconds:UInt64
    static func info(_ pid:pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return info
    }
    static func read(_ pid:pid_t) -> Self? {
        guard let i = info(pid) else { return nil }
        return .init(pid:pid,seconds:i.pbi_start_tvsec,microseconds:i.pbi_start_tvusec)
    }
    var alive:Bool { guard let i = Self.info(pid) else { return false }; return i.pbi_status != 5 && i.pbi_start_tvsec == seconds && i.pbi_start_tvusec == microseconds }
}
private struct LocalProcessTree {
    var leader:pid_t
    var identities:Set<LocalProcessIdentity> = []
    init(_ pid:pid_t) { leader = pid; if let identity = LocalProcessIdentity.read(pid) { identities.insert(identity) } }
    mutating func capture() {
        var queue = identities.filter { $0.alive }.map(\.pid),visited:Set<pid_t> = []
        while let pid = queue.popLast() {
            guard visited.insert(pid).inserted else { continue }
            let capacity = max(64,Int(proc_listchildpids(pid,nil,0))+32)
            var children = [pid_t](repeating:0,count:capacity)
            let count = children.withUnsafeMutableBytes { proc_listchildpids(pid,$0.baseAddress,Int32($0.count)) }
            guard count > 0 else { continue }
            for child in children.prefix(min(Int(count),capacity)) where child > 0 {
                if let identity = LocalProcessIdentity.read(child) { identities.insert(identity); queue.append(child) }
            }
        }
    }
    func signal(_ number:Int32) {
        _ = kill(-leader,number)
        for identity in identities where identity.alive { _ = kill(identity.pid,number) }
    }
    var remaining:[Int32] { identities.filter { $0.alive }.map(\.pid).sorted() }
}

/// Spawn a process group directly. File-backed output cannot deadlock on a full pipe.
/// Cancellation and timeout terminate descendants even when the group leader exits first.
@MainActor final class LocalProcessRunner {
    var maximumOutputBytes = 8*1024*1024
    var onStart:(Int32) -> Void = { _ in }
    var onOutput:(LocalOutputSnapshot) -> Void = { _ in }
    private func output(_ stdout:String,_ stderr:String) -> LocalOutputSnapshot {
        func read(_ path:String) -> (String,Int) {
            let size = ((try? FileManager.default.attributesOfItem(atPath:path)[.size]) as? NSNumber)?.intValue ?? 0
            guard let file = FileHandle(forReadingAtPath:path) else { return ("",size) }; defer { try? file.close() }
            if size > 16000 { try? file.seek(toOffset:UInt64(size-16000)) }
            let bytes = (try? file.readToEnd()) ?? Data()
            return ((size > 16000 ? "[최근 출력 미리보기 · 전문은 저장된 로그에 보존]\n" : "")+String(decoding:bytes,as:UTF8.self),size)
        }
        let a = read(stdout),b = read(stderr)
        return LocalOutputSnapshot(stdout:a.0,stderr:b.0,stdoutBytes:a.1,stderrBytes:b.1)
    }
    private func stopTree(_ tree:inout LocalProcessTree) async {
        tree.capture(); tree.signal(SIGTERM)
        for _ in 0..<7 {
            try? await Task.sleep(nanoseconds:50_000_000)
            tree.capture(); tree.signal(SIGTERM)
        }
        tree.signal(SIGKILL)
    }
    func run(_ command:ValidatedLocalCommand,index:Int,directory:String,control:RunControl) async throws -> LocalCommandResult {
        try await control.checkpoint()
        try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let stdout = directory+"/stdout.log",stderr = directory+"/stderr.log"
        var actions:posix_spawn_file_actions_t? = nil,attributes:posix_spawnattr_t? = nil
        guard posix_spawn_file_actions_init(&actions) == 0,posix_spawnattr_init(&attributes) == 0 else { throw Failure("프로세스 실행 정보를 만들지 못했습니다.") }
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t(),mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for number in [SIGINT,SIGTERM,SIGHUP,SIGQUIT,SIGPIPE] { sigaddset(&defaults,number) }
        let configuration = [
            posix_spawn_file_actions_addopen(&actions,STDIN_FILENO,"/dev/null",O_RDONLY,0),
            posix_spawn_file_actions_addopen(&actions,STDOUT_FILENO,stdout,O_WRONLY|O_CREAT|O_EXCL,0o600),
            posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,stderr,O_WRONLY|O_CREAT|O_EXCL,0o600),
            posix_spawn_file_actions_addchdir_np(&actions,command.directory),
            posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_CLOEXEC_DEFAULT|POSIX_SPAWN_SETSIGDEF|POSIX_SPAWN_SETSIGMASK)),
            posix_spawnattr_setpgroup(&attributes,0),
            posix_spawnattr_setsigdefault(&attributes,&defaults),posix_spawnattr_setsigmask(&attributes,&mask)
        ]
        guard configuration.allSatisfy({ $0 == 0 }) else { throw Failure("프로세스 입출력과 작업 폴더를 설정하지 못했습니다.") }
        let argv = ([command.executable]+command.arguments).map { strdup($0) }+[nil]
        let env = command.environment.keys.sorted().map { strdup($0+"="+command.environment[$0]!) }+[nil]
        defer { argv.forEach { free($0) }; env.forEach { free($0) } }
        var pid:pid_t = 0
        let started = Date()
        try control.check()
        let spawned = posix_spawn(&pid,command.executable,&actions,&attributes,argv,env)
        guard spawned == 0 else { throw Failure("명령을 시작하지 못했습니다: \(String(cString:strerror(spawned)))") }
        var tree = LocalProcessTree(pid)
        onStart(pid)
        var status:Int32 = 0,reason = "exited",reaped = false,lastOutput:LocalOutputSnapshot?
        while true {
            tree.capture()
            let sample = output(stdout,stderr)
            if sample != lastOutput { lastOutput = sample; onOutput(sample) }
            if control.isCancelled || Task.isCancelled { reason = "cancelled"; break }
            if Date().timeIntervalSince(started) >= command.spec.timeoutSeconds { reason = "timeout"; break }
            if sample.stdoutBytes+sample.stderrBytes > maximumOutputBytes { reason = "output_limit"; break }
            let waited = waitpid(pid,&status,WNOHANG)
            if waited == pid { reaped = true; break }
            if waited < 0 && errno != EINTR { reason = "wait_error"; break }
            try? await Task.sleep(nanoseconds:100_000_000)
        }
        // Reap/clean the whole group, including a child left behind by an exited leader.
        await stopTree(&tree)
        if !reaped { while waitpid(pid,&status,0) < 0 && errno == EINTR {} }
        for _ in 0..<10 where !tree.remaining.isEmpty { try? await Task.sleep(nanoseconds:20_000_000) }
        let remaining = tree.remaining
        let final = output(stdout,stderr); if final != lastOutput { onOutput(final) }
        if reason == "exited",final.stdoutBytes+final.stderrBytes > maximumOutputBytes { reason = "output_limit" }
        let signalled = status & 0x7f != 0
        let signal:Int32? = signalled ? status & 0x7f : nil
        let exit:Int32? = signalled ? nil : (status >> 8)&0xff
        if reason == "exited",signalled { reason = "signal" }
        var files:[LocalFileProof] = [],error:String?
        if reason == "exited",let exit,command.successExitCodes.contains(exit) {
            do {
                for path in command.expectedFiles {
                    let attrs = try FileManager.default.attributesOfItem(atPath:path)
                    guard attrs[.type] as? FileAttributeType == .typeRegular else { throw Failure("검증할 결과가 일반 파일이 아닙니다: \(path)") }
                    let file = try FileHandle(forReadingFrom:URL(fileURLWithPath:path))
                    defer { try? file.close() }
                    var hash = SHA256(),bytes = 0
                    while let chunk = try file.read(upToCount:1024*1024),!chunk.isEmpty {
                        try control.check(); hash.update(data:chunk); bytes += chunk.count
                        await Task.yield()
                    }
                    guard bytes > 0 else { throw Failure("결과 파일이 비어 있습니다: \(path)") }
                    files.append(LocalFileProof(path:path,bytes:bytes,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined()))
                }
                if let expected = command.spec.expectedStdout,!expected.isEmpty {
                    let text = String(decoding:try Data(contentsOf:URL(fileURLWithPath:stdout)),as:UTF8.self)
                    guard text.contains(expected) else { throw Failure("stdout에서 지정한 결과를 찾지 못했습니다.") }
                }
            } catch let failure { error = String(describing:failure) }
        } else { error = reason == "exited" ? "종료 코드 \(exit.map(String.init) ?? "없음")" : reason }
        if !remaining.isEmpty { error = "종료하지 못한 자손 프로세스: \(remaining)" }
        if control.isCancelled || Task.isCancelled { reason = "cancelled"; error = remaining.isEmpty ? "cancelled" : error }
        let succeeded = error == nil
        let verification = succeeded ? "종료 코드 \(exit!) 확인"+(files.isEmpty ? "" : " · 결과 파일 \(files.count)개와 SHA-256 확인")+(command.spec.expectedStdout == nil ? "" : " · 지정한 stdout 확인") : "명령 결과를 완료로 확인하지 못했습니다 · "+(error ?? reason)
        let result = LocalCommandResult(index:index,command:command.spec,executable:command.executable,executedArguments:command.arguments,pid:pid,startedAt:started,durationMS:milliseconds(started),exitCode:exit,signal:signal,termination:reason,stdoutPath:stdout,stderrPath:stderr,stdoutBytes:final.stdoutBytes,stderrBytes:final.stderrBytes,verification:verification,files:files,succeeded:succeeded,error:error,trackedDescendantPIDs:tree.identities.map(\.pid).filter { $0 != pid }.sorted(),remainingProcessPIDs:remaining)
        try writeJSON(result,directory+"/result.json")
        return result
    }
}
