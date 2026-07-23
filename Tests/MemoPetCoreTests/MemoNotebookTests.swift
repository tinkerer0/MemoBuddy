import Foundation
import XCTest

@testable import MemoPetCore

final class MemoNotebookTests: XCTestCase {
  func testEmptyNotebookNormalizesToOneBlankNote() {
    var notebook = MemoNotebook()
    notebook.notes = []

    notebook.normalize()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.text, "")
    XCTAssertTrue(notebook.selectedNote.strokes.isEmpty)
    XCTAssertEqual(notebook.selectedIndex, 0)
  }

  func testAddingNotesSelectsTheNewNote() {
    var notebook = MemoNotebook()
    let originalID = notebook.selectedNoteID

    let added = notebook.addNote()

    XCTAssertEqual(notebook.notes.count, 2)
    XCTAssertEqual(notebook.selectedNoteID, added.id)
    XCTAssertEqual(notebook.selectedNote.text, "")
    XCTAssertTrue(notebook.selectedNote.strokes.isEmpty)
    XCTAssertNotEqual(notebook.selectedNoteID, originalID)
  }

  func testDeletingSelectedNoteChoosesTheNextAvailableNote() {
    let first = MemoNote(text: "First")
    let second = MemoNote()
    let third = MemoNote(text: "Third")
    var notebook = MemoNotebook(
      notes: [first, second, third],
      selectedNoteID: second.id
    )

    notebook.deleteSelectedNote()

    XCTAssertEqual(notebook.notes.map(\.id), [first.id, third.id])
    XCTAssertEqual(notebook.selectedNoteID, third.id)
  }

  func testDeletingOnlyNoteCreatesBlankReplacement() {
    var notebook = MemoNotebook(
      notes: [MemoNote(strokes: [MemoStroke(points: [MemoPoint(x: 0.5, y: 0.5)])])]
    )

    notebook.deleteSelectedNote()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.text, "")
    XCTAssertTrue(notebook.selectedNote.strokes.isEmpty)
  }

  func testNormalizeRepairsDuplicateIDsAndOutOfBoundsDrawingPoints() {
    let duplicateID = UUID()
    var notebook = MemoNotebook(
      version: 1,
      notes: [
        MemoNote(id: duplicateID),
        MemoNote(
          id: duplicateID,
          strokes: [
            MemoStroke(
              points: [
                MemoPoint(x: -20, y: 30)
              ]
            )
          ]
        ),
      ],
      selectedNoteID: duplicateID
    )

    notebook.normalize()

    XCTAssertEqual(Set(notebook.notes.map(\.id)).count, 2)
    XCTAssertEqual(notebook.notes[1].strokes[0].points[0], MemoPoint(x: 0, y: 1))
    XCTAssertEqual(notebook.version, MemoNotebook.currentVersion)
    XCTAssertEqual(notebook.selectedNoteID, duplicateID)
  }
}
