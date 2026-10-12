import XCTest
@testable import JevComputerUse

final class ProductIdentityTests: XCTestCase {
    func testRawExecutableNeedsNoInventedBundleMetadata() throws {
        XCTAssertNoThrow(try ProductIdentity.validateBundle(executablePath: "/fixture-workspace/raw/jev-native"))
    }

    func testAppMetadataMustMatchCompiledProduct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("product-identity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("JevNative.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let value = ProductIdentity.compiled
        let resource = contents.appendingPathComponent("Resources/ProductIdentity.json")
        try JSONEncoder().encode(value).write(to: resource)
        var info = ["CFBundleIdentifier": value.bundleIdentifier, "CFBundleExecutable": value.executable,
                    "CFBundleShortVersionString": value.version, "CFBundleVersion": value.build]
        let plist = contents.appendingPathComponent("Info.plist")
        func write() throws { try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist) }
        try write()
        let executable = contents.appendingPathComponent("MacOS/jev-native").path
        XCTAssertNoThrow(try ProductIdentity.validateBundle(executablePath: executable))
        info["CFBundleVersion"] = "0"; try write()
        XCTAssertThrowsError(try ProductIdentity.validateBundle(executablePath: executable))
        info["CFBundleVersion"] = value.build; try write()
        try Data("{}".utf8).write(to: resource)
        XCTAssertThrowsError(try ProductIdentity.validateBundle(executablePath: executable))
    }
}
