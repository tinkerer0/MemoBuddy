import Foundation
import XCTest

@testable import MemoPetCore

final class ScratchpadStoreTests: XCTestCase {
  func testMissingNoteLoadsAsEmptyText() throws {
    let directory = try makeTemporaryDirectory()
    let store = try ScratchpadStore(directoryURL: directory)

    XCTAssertEqual(try store.load(), "")
  }

  func testSaveAndLoadPreservesUnicodeAndNewlines() throws {
    let directory = try makeTemporaryDirectory()
    let store = try ScratchpadStore(directoryURL: directory)
    let text = "Check after the agent finishes\nSecond line 🐈"

    try store.save(text)

    XCTAssertEqual(try store.load(), text)
    XCTAssertEqual(
      try String(contentsOf: store.noteURL, encoding: .utf8),
      text
    )
    XCTAssertEqual(try permissions(at: directory), 0o700)
    XCTAssertEqual(try permissions(at: store.noteURL), 0o600)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MemoPetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(
      attributes[.posixPermissions] as? NSNumber
    ).intValue & 0o777
  }
}
