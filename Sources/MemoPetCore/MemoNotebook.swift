import Foundation

public struct MemoPoint: Codable, Equatable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct MemoStroke: Codable, Equatable {
  public var points: [MemoPoint]

  public init(points: [MemoPoint] = []) {
    self.points = points
  }
}

public struct MemoNote: Codable, Equatable, Identifiable {
  public var id: UUID
  public var text: String
  public var strokes: [MemoStroke]

  public init(
    id: UUID = UUID(),
    text: String = "",
    strokes: [MemoStroke] = []
  ) {
    self.id = id
    self.text = text
    self.strokes = strokes
  }
}

public struct MemoNotebook: Codable, Equatable {
  public static let currentVersion = 2

  public var version: Int
  public var notes: [MemoNote]
  public var selectedNoteID: UUID

  public init(
    version: Int = MemoNotebook.currentVersion,
    notes: [MemoNote] = [MemoNote()],
    selectedNoteID: UUID? = nil
  ) {
    let resolvedNotes = notes.isEmpty ? [MemoNote()] : notes
    self.version = version
    self.notes = resolvedNotes
    self.selectedNoteID = selectedNoteID
      .flatMap { candidate in
        resolvedNotes.contains(where: { $0.id == candidate }) ? candidate : nil
      }
      ?? resolvedNotes[0].id
  }

  public var selectedIndex: Int {
    notes.firstIndex(where: { $0.id == selectedNoteID }) ?? 0
  }

  public var selectedNote: MemoNote {
    notes[selectedIndex]
  }

  public mutating func normalize(sanitizeContent: Bool = true) {
    version = Self.currentVersion

    if notes.isEmpty {
      let note = MemoNote()
      notes = [note]
      selectedNoteID = note.id
      return
    }

    var seenIDs = Set<UUID>()
    for noteIndex in notes.indices {
      if seenIDs.contains(notes[noteIndex].id) {
        notes[noteIndex].id = UUID()
      }
      seenIDs.insert(notes[noteIndex].id)

      if sanitizeContent {
        for strokeIndex in notes[noteIndex].strokes.indices {
          for pointIndex in notes[noteIndex].strokes[strokeIndex].points.indices {
            notes[noteIndex].strokes[strokeIndex].points[pointIndex].x = min(
              max(
                notes[noteIndex].strokes[strokeIndex].points[pointIndex].x,
                0
              ),
              1
            )
            notes[noteIndex].strokes[strokeIndex].points[pointIndex].y = min(
              max(
                notes[noteIndex].strokes[strokeIndex].points[pointIndex].y,
                0
              ),
              1
            )
          }
        }
      }
    }

    if !notes.contains(where: { $0.id == selectedNoteID }) {
      selectedNoteID = notes[0].id
    }
  }

  public mutating func select(at index: Int) {
    guard notes.indices.contains(index) else { return }
    selectedNoteID = notes[index].id
  }

  @discardableResult
  public mutating func addNote() -> MemoNote {
    let note = MemoNote()
    notes.append(note)
    selectedNoteID = note.id
    return note
  }

  public mutating func deleteSelectedNote() {
    let index = selectedIndex
    notes.remove(at: index)

    if notes.isEmpty {
      let replacement = MemoNote()
      notes = [replacement]
      selectedNoteID = replacement.id
      return
    }

    selectedNoteID = notes[min(index, notes.count - 1)].id
  }
}
