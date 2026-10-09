import AppKit
@main struct CredentialSetupProbe {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jev-key-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("synthetic_runtime_api_token_731", forType: .string)
        var io = CredentialSetupIO.native()
        io.readPasteboard = { pasteboard.string(forType: .string) }
        io.openKeys = { print("TEST_ONLY_URL_OPEN_ADAPTER"); return true }
        do {
            let result = try setupCredential(environment: [:], home: directory.path, io: io)
            let file = directory.appendingPathComponent(".typesafeai")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let valid = try credential(environment: [:], home: directory.path) == "synthetic_runtime_api_token_731"
            print("result=\(result.rawValue) synthetic_content_matches=\(valid) mode=\(String((attributes[.posixPermissions] as! NSNumber).intValue,radix:8))")
        } catch {
            print("\(error)")
            print("saved_file_exists=\(FileManager.default.fileExists(atPath:directory.appendingPathComponent(".typesafeai").path))")
        }
    }
}
