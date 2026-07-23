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

  func testDeletingAnotherNoteKeepsTheCurrentSelection() {
    let first = MemoNote(title: "First")
    let second = MemoNote(title: "Second")
    let third = MemoNote(title: "Third")
    var notebook = MemoNotebook(
      notes: [first, second, third],
      selectedNoteID: second.id
    )

    notebook.deleteNote(at: 0)

    XCTAssertEqual(notebook.notes.map(\.id), [second.id, third.id])
    XCTAssertEqual(notebook.selectedNoteID, second.id)
  }

  func testNoteIsEmptyOnlyWhenItHasNoTitleTextOrDrawing() {
    XCTAssertTrue(MemoNote().isEmpty)
    XCTAssertFalse(MemoNote(title: "Title").isEmpty)
    XCTAssertFalse(MemoNote(text: "Text").isEmpty)
    XCTAssertFalse(
      MemoNote(
        strokes: [
          MemoStroke(points: [MemoPoint(x: 1, y: 1)])
        ]
      ).isEmpty
    )
  }

  func testNormalizeRepairsDuplicateIDsAndNegativeAbsoluteDrawingPoints() {
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
    XCTAssertEqual(notebook.notes[1].strokes[0].points[0], MemoPoint(x: 0, y: 30))
    XCTAssertEqual(notebook.version, MemoNotebook.currentVersion)
    XCTAssertEqual(notebook.selectedNoteID, duplicateID)
  }

  func testNormalizeClampsLegacyNormalizedDrawingPoints() {
    var notebook = MemoNotebook(
      version: 2,
      notes: [
        MemoNote(
          strokes: [
            MemoStroke(
              points: [
                MemoPoint(x: -20, y: 30)
              ]
            )
          ],
          drawingCoordinateSpace: nil
        )
      ]
    )

    notebook.normalize()

    XCTAssertEqual(
      notebook.selectedNote.strokes[0].points[0],
      MemoPoint(x: 0, y: 1)
    )
    XCTAssertNil(notebook.selectedNote.drawingCoordinateSpace)
  }

  func testConvertingLegacyDrawingUsesCanvasSizeOnce() {
    let legacy = [
      MemoStroke(
        points: [
          MemoPoint(x: 0.25, y: 0.5),
          MemoPoint(x: 1, y: 0),
        ]
      )
    ]

    let converted = MemoDrawingCoordinates.convertingLegacyNormalizedStrokes(
      legacy,
      canvasWidth: 320,
      canvasHeight: 180
    )

    XCTAssertEqual(
      converted,
      [
        MemoStroke(
          points: [
            MemoPoint(x: 80, y: 90),
            MemoPoint(x: 320, y: 0),
          ]
        )
      ]
    )
    XCTAssertEqual(legacy[0].points[0], MemoPoint(x: 0.25, y: 0.5))
  }

  func testNormalizePreservesAbsolutePointsOutsideCurrentCanvas() {
    var notebook = MemoNotebook(
      notes: [
        MemoNote(
          strokes: [
            MemoStroke(
              points: [
                MemoPoint(x: 480, y: 310)
              ]
            )
          ]
        )
      ]
    )

    notebook.normalize()

    XCTAssertEqual(
      notebook.selectedNote.strokes[0].points[0],
      MemoPoint(x: 480, y: 310)
    )
    XCTAssertEqual(
      notebook.selectedNote.drawingCoordinateSpace,
      .absolutePoints
    )
  }

  func testEraserDragSplitsAStrokeWithoutJoiningAcrossTheGap() {
    let strokes = [
      MemoStroke(
        points: [
          MemoPoint(x: 0, y: 0),
          MemoPoint(x: 10, y: 0),
          MemoPoint(x: 20, y: 0),
          MemoPoint(x: 30, y: 0),
        ]
      )
    ]

    let erased = MemoDrawingEraser.erasing(
      strokes: strokes,
      from: MemoPoint(x: 15, y: -5),
      to: MemoPoint(x: 15, y: 5),
      radius: 2
    )

    XCTAssertEqual(
      erased,
      [
        MemoStroke(
          points: [
            MemoPoint(x: 0, y: 0),
            MemoPoint(x: 10, y: 0),
          ]
        ),
        MemoStroke(
          points: [
            MemoPoint(x: 20, y: 0),
            MemoPoint(x: 30, y: 0),
          ]
        ),
      ]
    )
  }

  func testEraserRemovesOnlyTouchedDots() {
    let strokes = [
      MemoStroke(points: [MemoPoint(x: 5, y: 5)]),
      MemoStroke(points: [MemoPoint(x: 30, y: 30)]),
    ]

    let erased = MemoDrawingEraser.erasing(
      strokes: strokes,
      from: MemoPoint(x: 5, y: 5),
      to: MemoPoint(x: 5, y: 5),
      radius: 4
    )

    XCTAssertEqual(
      erased,
      [MemoStroke(points: [MemoPoint(x: 30, y: 30)])]
    )
  }

  func testEraserLeavesDistantStrokesUnchanged() {
    let strokes = [
      MemoStroke(
        points: [
          MemoPoint(x: 0, y: 0),
          MemoPoint(x: 20, y: 0),
        ]
      )
    ]

    let erased = MemoDrawingEraser.erasing(
      strokes: strokes,
      from: MemoPoint(x: 100, y: 100),
      to: MemoPoint(x: 120, y: 100),
      radius: 8
    )

    XCTAssertEqual(erased, strokes)
  }
}
