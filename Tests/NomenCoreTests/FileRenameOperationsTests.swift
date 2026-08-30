import Foundation
import Testing
@testable import NomenCore

@Test func uniquifyReturnsDesiredWhenFree() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nomen-uniquify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("a.pdf")
    try Data().write(to: source)
    let name = FileRenameOperations.uniquifyFilename(
        desiredName: "b.pdf",
        directory: dir,
        ignoreIfSameAs: source
    )
    #expect(name == "b.pdf")
}

@Test func uniquifyAddsIndexWhenTaken() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nomen-uniquify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("old.pdf")
    let taken = dir.appendingPathComponent("Neu.pdf")
    try Data().write(to: source)
    try Data().write(to: taken)
    let name = FileRenameOperations.uniquifyFilename(
        desiredName: "Neu.pdf",
        directory: dir,
        ignoreIfSameAs: source
    )
    #expect(name == "Neu (2).pdf")
}

@Test func uniquifyIgnoresWhenTargetIsSource() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nomen-uniquify-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("same.pdf")
    try Data().write(to: source)
    let name = FileRenameOperations.uniquifyFilename(
        desiredName: "same.pdf",
        directory: dir,
        ignoreIfSameAs: source
    )
    #expect(name == "same.pdf")
}
