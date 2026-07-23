import Foundation
import XCTest

@testable import MemoPetCore

final class MemoNotebookStoreTests: XCTestCase {
  func testMissingNotebookLoadsOneBlankNote() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)

    let notebook = try store.load()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.text, "")
    XCTAssertTrue(notebook.selectedNote.strokes.isEmpty)
  }

  func testSaveAndLoadPreservesTextDrawingAndSelection() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let text = MemoNote(
      title: "오늘 할 일",
      text: "에이전트 결과 확인 🐈"
    )
    let hybrid = MemoNote(
      text: "Circle this",
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
      notes: [text, hybrid],
      selectedNoteID: hybrid.id
    )

    try store.save(notebook)
    let loaded = try store.load()

    XCTAssertEqual(loaded, notebook)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.notebookURL.path))
    XCTAssertEqual(try permissions(at: directory), 0o700)
    XCTAssertEqual(try permissions(at: store.notebookURL), 0o600)
  }

  func testLegacyTextMigratesWithoutRemovingOriginalFile() throws {
    let directory = try makeTemporaryDirectory()
    let legacyStore = try ScratchpadStore(directoryURL: directory)
    let text = "Keep this existing note\n두 번째 줄"
    try legacyStore.save(text)
    let store = try MemoNotebookStore(directoryURL: directory)

    let notebook = try store.load()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.text, text)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.notebookURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.legacyNoteURL.path))
  }

  func testVersionOneNotebookMigratesTextAndDrawingIntoHybridNotes() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let textID = UUID()
    let drawingID = UUID()
    let json = """
      {
        "version": 1,
        "selectedNoteID": "\(drawingID.uuidString)",
        "notes": [
          {
            "id": "\(textID.uuidString)",
            "kind": "text",
            "text": "Keep me",
            "strokes": []
          },
          {
            "id": "\(drawingID.uuidString)",
            "kind": "drawing",
            "text": "",
            "strokes": [
              {"points": [{"x": 0.25, "y": 0.75}]}
            ]
          }
        ]
      }
      """
    try Data(json.utf8).write(to: store.notebookURL, options: [.atomic])

    let notebook = try store.load()

    XCTAssertEqual(notebook.version, MemoNotebook.currentVersion)
    XCTAssertEqual(notebook.notes.map(\.id), [textID, drawingID])
    XCTAssertEqual(notebook.notes[0].text, "Keep me")
    XCTAssertNil(notebook.notes[0].title)
    XCTAssertEqual(notebook.notes[1].strokes.count, 1)
    XCTAssertNil(notebook.notes[1].drawingCoordinateSpace)
    XCTAssertEqual(notebook.selectedNoteID, drawingID)
  }

  func testDamagedNotebookRestoresLatestValidBackup() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let backedUp = MemoNotebook(notes: [MemoNote(text: "Backed up")])
    let newer = MemoNotebook(notes: [MemoNote(text: "Newer")])
    try store.save(backedUp)
    try store.save(newer)
    try Data("{truncated".utf8).write(
      to: store.notebookURL,
      options: [.atomic]
    )

    let recovered = try store.load()

    XCTAssertEqual(recovered.selectedNote.text, "Backed up")
    XCTAssertNotNil(store.recoveryNotice)
    XCTAssertEqual(try store.load().selectedNote.text, "Backed up")
  }

  func testDamagedNotebookWithoutBackupIsPreservedBeforeStartingBlank() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let damagedData = Data("{not json".utf8)
    try damagedData.write(to: store.notebookURL, options: [.atomic])

    let recovered = try store.load()
    let preservedFiles = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("notes-corrupt-") }

    XCTAssertEqual(recovered.notes, [MemoNote(id: recovered.notes[0].id)])
    XCTAssertEqual(preservedFiles.count, 1)
    XCTAssertEqual(try Data(contentsOf: preservedFiles[0]), damagedData)
    XCTAssertNotNil(store.recoveryNotice)
  }

  func testNewerNotebookVersionIsNotOverwritten() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let noteID = UUID()
    let json = """
      {
        "version": 999,
        "selectedNoteID": "\(noteID.uuidString)",
        "notes": [
          {"id": "\(noteID.uuidString)", "text": "Future", "strokes": []}
        ]
      }
      """
    let originalData = Data(json.utf8)
    try originalData.write(to: store.notebookURL, options: [.atomic])

    XCTAssertThrowsError(try store.load()) { error in
      guard case MemoNotebookStoreError.unsupportedVersion(999) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    XCTAssertEqual(try Data(contentsOf: store.notebookURL), originalData)
  }

  func testLongUnicodeTextAndManyDrawingPointsRoundTrip() throws {
    let directory = try makeTemporaryDirectory()
    let store = try MemoNotebookStore(directoryURL: directory)
    let text = String(repeating: "긴 메모 line 📝\n", count: 10_000)
    let strokes = (0..<50).map { strokeIndex in
      MemoStroke(
        points: (0..<100).map { pointIndex in
          MemoPoint(
            x: Double(pointIndex) / 99,
            y: Double(strokeIndex) / 49
          )
        }
      )
    }
    let note = MemoNote(text: text, strokes: strokes)
    let notebook = MemoNotebook(notes: [note], selectedNoteID: note.id)

    try store.save(notebook)
    let loaded = try store.load()

    XCTAssertEqual(loaded, notebook)
    XCTAssertGreaterThan(try Data(contentsOf: store.notebookURL).count, 100_000)
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

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(
      attributes[.posixPermissions] as? NSNumber
    ).intValue & 0o777
  }
}
