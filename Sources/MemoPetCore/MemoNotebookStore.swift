import Foundation

public enum MemoNotebookStoreError: LocalizedError {
  case unsupportedVersion(Int)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedVersion(version):
      return "These notes were created by a newer MemoPet data format (version \(version))."
    }
  }
}

public final class MemoNotebookStore {
  public let notebookURL: URL
  public let backupURL: URL
  public let legacyNoteURL: URL
  public private(set) var recoveryNotice: String?

  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var lastBackupDate: Date?
  private let backupInterval: TimeInterval = 30

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
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )

    self.notebookURL = directoryURL.appendingPathComponent(
      "notes.json",
      isDirectory: false
    )
    self.backupURL = directoryURL.appendingPathComponent(
      "notes.backup.json",
      isDirectory: false
    )
    self.legacyNoteURL = directoryURL.appendingPathComponent(
      "note.txt",
      isDirectory: false
    )

    encoder.outputFormatting = [.sortedKeys]

    for url in [notebookURL, backupURL, legacyNoteURL]
    where fileManager.fileExists(atPath: url.path)
    {
      try secureFile(at: url)
    }
  }

  public func load() throws -> MemoNotebook {
    recoveryNotice = nil

    if fileManager.fileExists(atPath: notebookURL.path) {
      let data = try Data(contentsOf: notebookURL)
      do {
        return try decodeNotebook(from: data)
      } catch let error as MemoNotebookStoreError {
        throw error
      } catch {
        return try recoverFromDamagedNotebook()
      }
    }

    guard fileManager.fileExists(atPath: legacyNoteURL.path) else {
      return MemoNotebook()
    }

    let legacyText = try String(contentsOf: legacyNoteURL, encoding: .utf8)
    let note = MemoNote(text: legacyText)
    let notebook = MemoNotebook(notes: [note], selectedNoteID: note.id)
    try save(notebook)
    return notebook
  }

  public func save(_ notebook: MemoNotebook) throws {
    var normalized = notebook
    normalized.normalize(sanitizeContent: false)
    let data = try encoder.encode(normalized)

    let shouldRefreshBackup = lastBackupDate.map {
      let elapsed = Date().timeIntervalSince($0)
      return elapsed < 0 || elapsed >= backupInterval
    } ?? true
    if shouldRefreshBackup,
      fileManager.fileExists(atPath: notebookURL.path),
      let existingData = try? Data(contentsOf: notebookURL),
      (try? decodeNotebook(from: existingData)) != nil
    {
      try existingData.write(to: backupURL, options: [.atomic])
      try secureFile(at: backupURL)
      lastBackupDate = Date()
    }

    try data.write(to: notebookURL, options: [.atomic])
    try secureFile(at: notebookURL)
  }

  private func recoverFromDamagedNotebook() throws -> MemoNotebook {
    if fileManager.fileExists(atPath: backupURL.path) {
      let backupData = try Data(contentsOf: backupURL)
      do {
        let recovered = try decodeNotebook(from: backupData)
        try save(recovered)
        recoveryNotice = "The notes file was damaged, so MemoPet restored a recent backup."
        return recovered
      } catch let error as MemoNotebookStoreError {
        throw error
      } catch {
        // Preserve both damaged files below instead of discarding either one.
      }
    }

    let preservedURL = notebookURL
      .deletingLastPathComponent()
      .appendingPathComponent(
        "notes-corrupt-\(UUID().uuidString).json",
        isDirectory: false
      )
    try fileManager.copyItem(at: notebookURL, to: preservedURL)
    try secureFile(at: preservedURL)

    let blankNotebook = MemoNotebook()
    try save(blankNotebook)
    recoveryNotice = "The notes file was damaged. MemoPet started a blank notebook and preserved the damaged file as \(preservedURL.lastPathComponent)."
    return blankNotebook
  }

  private func decodeNotebook(from data: Data) throws -> MemoNotebook {
    var notebook = try decoder.decode(MemoNotebook.self, from: data)
    guard notebook.version <= MemoNotebook.currentVersion else {
      throw MemoNotebookStoreError.unsupportedVersion(notebook.version)
    }
    notebook.normalize()
    return notebook
  }

  private func secureFile(at url: URL) throws {
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }
}
