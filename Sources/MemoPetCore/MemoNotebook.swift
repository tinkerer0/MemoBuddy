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

public enum MemoDrawingCoordinateSpace: String, Codable, Equatable {
  case absolutePoints
}

public enum MemoDrawingCoordinates {
  public static func convertingLegacyNormalizedStrokes(
    _ strokes: [MemoStroke],
    canvasWidth: Double,
    canvasHeight: Double
  ) -> [MemoStroke] {
    guard canvasWidth.isFinite,
      canvasHeight.isFinite,
      canvasWidth > 0,
      canvasHeight > 0
    else {
      return strokes
    }

    return strokes.map { stroke in
      MemoStroke(
        points: stroke.points.map { point in
          MemoPoint(
            x: point.x * canvasWidth,
            y: point.y * canvasHeight
          )
        }
      )
    }
  }
}

public struct MemoNote: Codable, Equatable, Identifiable {
  public var id: UUID
  public var title: String?
  public var text: String
  public var strokes: [MemoStroke]
  public var drawingCoordinateSpace: MemoDrawingCoordinateSpace?

  public init(
    id: UUID = UUID(),
    title: String? = nil,
    text: String = "",
    strokes: [MemoStroke] = [],
    drawingCoordinateSpace: MemoDrawingCoordinateSpace? = .absolutePoints
  ) {
    self.id = id
    self.title = title
    self.text = text
    self.strokes = strokes
    self.drawingCoordinateSpace = drawingCoordinateSpace
  }

  public var isEmpty: Bool {
    title?.isEmpty != false
      && text.isEmpty
      && strokes.isEmpty
  }
}

public struct MemoNotebook: Codable, Equatable {
  public static let currentVersion = 4

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
        let coordinateMaximum: Double? =
          notes[noteIndex].drawingCoordinateSpace == nil ? 1 : nil
        for strokeIndex in notes[noteIndex].strokes.indices {
          for pointIndex in notes[noteIndex].strokes[strokeIndex].points.indices {
            let x = max(
              notes[noteIndex].strokes[strokeIndex].points[pointIndex].x,
              0
            )
            let y = max(
              notes[noteIndex].strokes[strokeIndex].points[pointIndex].y,
              0
            )
            notes[noteIndex].strokes[strokeIndex].points[pointIndex].x =
              coordinateMaximum.map { min(x, $0) } ?? x
            notes[noteIndex].strokes[strokeIndex].points[pointIndex].y =
              coordinateMaximum.map { min(y, $0) } ?? y
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
    deleteNote(at: selectedIndex)
  }

  public mutating func deleteNote(at index: Int) {
    guard notes.indices.contains(index) else { return }
    let deletedNoteID = notes[index].id
    notes.remove(at: index)

    if notes.isEmpty {
      let replacement = MemoNote()
      notes = [replacement]
      selectedNoteID = replacement.id
      return
    }

    if selectedNoteID == deletedNoteID {
      selectedNoteID = notes[min(index, notes.count - 1)].id
    }
  }
}
