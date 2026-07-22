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
}
