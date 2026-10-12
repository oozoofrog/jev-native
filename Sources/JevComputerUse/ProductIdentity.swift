import Foundation

struct ProductIdentity: Codable, Equatable {
    let schema: Int
    let product: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let executable: String
    let manifestSHA256: String

    static var compiled: Self {
        Self(schema: CompiledProduct.schema, product: CompiledProduct.product,
             version: CompiledProduct.version, build: CompiledProduct.build,
             bundleIdentifier: CompiledProduct.bundleIdentifier, executable: CompiledProduct.executable,
             manifestSHA256: CompiledProduct.manifestSHA256)
    }

    static func validateBundle(executablePath: String) throws {
        let binary = URL(fileURLWithPath: executablePath).standardizedFileURL.resolvingSymlinksInPath()
        let macOS = binary.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents" else { return }
        let info = contents.appendingPathComponent("Info.plist")
        let resource = contents.appendingPathComponent("Resources/ProductIdentity.json")
        let parsed = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any]
        let identity = try JSONDecoder().decode(Self.self, from: Data(contentsOf: resource))
        let expected = compiled
        guard identity == expected, parsed?["CFBundleIdentifier"] as? String == expected.bundleIdentifier,
              parsed?["CFBundleExecutable"] as? String == expected.executable,
              parsed?["CFBundleShortVersionString"] as? String == expected.version,
              parsed?["CFBundleVersion"] as? String == expected.build,
              binary.lastPathComponent == expected.executable else {
            throw Failure("App metadata and compiled JevNative identity differ. Rebuild the canonical product before running it.")
        }
    }

    struct Report: Encodable {
        let schema: Int
        let product: String
        let version: String
        let build: String
        let bundleIdentifier: String
        let executable: String
        let manifestSHA256: String
        let canonicalExecutable: String
    }

    static func report() throws -> Report {
        guard let execution = StartupExecutionIdentity.current() else { throw Failure("Loaded executable path unavailable") }
        try validateBundle(executablePath: execution.canonicalExecutable)
        let value = compiled
        return Report(schema: value.schema, product: value.product, version: value.version, build: value.build,
                      bundleIdentifier: value.bundleIdentifier, executable: value.executable,
                      manifestSHA256: value.manifestSHA256, canonicalExecutable: execution.canonicalExecutable)
    }
}
