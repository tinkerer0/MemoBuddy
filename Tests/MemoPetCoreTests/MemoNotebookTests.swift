import Foundation
import XCTest

@testable import MemoPetCore

final class MemoNotebookTests: XCTestCase {
  func testEmptyNotebookNormalizesToOneTextNote() {
    var notebook = MemoNotebook()
    notebook.notes = []

    notebook.normalize()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.kind, .text)
    XCTAssertEqual(notebook.selectedIndex, 0)
  }

  func testAddingNotesSelectsTheNewNote() {
    var notebook = MemoNotebook()
    let originalID = notebook.selectedNoteID

    let drawing = notebook.addNote(kind: .drawing)

    XCTAssertEqual(notebook.notes.count, 2)
    XCTAssertEqual(notebook.selectedNoteID, drawing.id)
    XCTAssertEqual(notebook.selectedNote.kind, .drawing)
    XCTAssertNotEqual(notebook.selectedNoteID, originalID)
  }

  func testDeletingSelectedNoteChoosesTheNextAvailableNote() {
    let first = MemoNote(kind: .text, text: "First")
    let second = MemoNote(kind: .drawing)
    let third = MemoNote(kind: .text, text: "Third")
    var notebook = MemoNotebook(
      notes: [first, second, third],
      selectedNoteID: second.id
    )

    notebook.deleteSelectedNote()

    XCTAssertEqual(notebook.notes.map(\.id), [first.id, third.id])
    XCTAssertEqual(notebook.selectedNoteID, third.id)
  }

  func testDeletingOnlyNoteCreatesBlankTextReplacement() {
    var notebook = MemoNotebook(
      notes: [MemoNote(kind: .drawing)]
    )

    notebook.deleteSelectedNote()

    XCTAssertEqual(notebook.notes.count, 1)
    XCTAssertEqual(notebook.selectedNote.kind, .text)
    XCTAssertEqual(notebook.selectedNote.text, "")
    XCTAssertTrue(notebook.selectedNote.strokes.isEmpty)
  }
}
