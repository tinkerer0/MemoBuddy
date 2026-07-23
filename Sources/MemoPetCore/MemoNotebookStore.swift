import Foundation

public final class MemoNotebookStore {
  public let notebookURL: URL
  public let legacyNoteURL: URL

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    directoryURL: URL,
    fileManager: FileManager = .default
  ) throws {
    self.fileManager = fileManager
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()

    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    self.notebookURL = directoryURL.appendingPathComponent(
      "notes.json",
      isDirectory: false
    )
    self.legacyNoteURL = directoryURL.appendingPathComponent(
      "note.txt",
      isDirectory: false
    )

    encoder.outputFormatting = [.sortedKeys]
  }

  public func load() throws -> MemoNotebook {
    if fileManager.fileExists(atPath: notebookURL.path) {
      let data = try Data(contentsOf: notebookURL)
      var notebook = try decoder.decode(MemoNotebook.self, from: data)
      notebook.normalize()
      return notebook
    }

    guard fileManager.fileExists(atPath: legacyNoteURL.path) else {
      return MemoNotebook()
    }

    let legacyText = try String(contentsOf: legacyNoteURL, encoding: .utf8)
    let note = MemoNote(kind: .text, text: legacyText)
    let notebook = MemoNotebook(notes: [note], selectedNoteID: note.id)
    try save(notebook)
    return notebook
  }

  public func save(_ notebook: MemoNotebook) throws {
    var normalized = notebook
    normalized.normalize()
    let data = try encoder.encode(normalized)
    try data.write(to: notebookURL, options: [.atomic])
  }
}
