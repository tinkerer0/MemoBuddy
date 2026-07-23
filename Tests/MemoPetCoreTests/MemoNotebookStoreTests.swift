import Foundation
import XCTest

@testable import MemoPetCore

final class MemoNotebookStoreTests: XCTestCase {
  func testMissingNotebookLoadsOneBlankTextNote() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)

    let notebook = try store.load()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.kind, .text)
    XCTAssertEqual(notebook.selectedNote.text, "")
  }

  func testSaveAndLoadPreservesTextDrawingAndSelection() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let text = MemoNote(kind: .text, text: "에이전트 결과 확인 🐈")
    let drawing = MemoNote(
      kind: .drawing,
      strokes: [
        MemoStroke(
          points: [
            MemoPoint(x: 0.1, y: 0.2),
            MemoPoint(x: 0.8, y: 0.7),
          ]
        )
      ]
    )
    let notebook = MemoNotebook(
      notes: [text, drawing],
      selectedNoteID: drawing.id
    )

    try store.save(notebook)
    let loaded = try store.load()

    XCTAssertEqual(loaded, notebook)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.notebookURL.path))
  }

  func testLegacyTextMigratesWithoutRemovingOriginalFile() throws {
    let directory = try makeTemporaryDirectory()
    let legacyStore = try ScratchpadStore(directoryURL: directory)
    let text = "Keep this existing note\n두 번째 줄"
    try legacyStore.save(text)
    let store = try MemoNotebookStore(directoryURL: directory)

    let notebook = try store.load()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.kind, .text)
    XCTAssertEqual(notebook.selectedNote.text, text)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.notebookURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyNoteURL.path))
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MemoPetNotebookTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }
}
