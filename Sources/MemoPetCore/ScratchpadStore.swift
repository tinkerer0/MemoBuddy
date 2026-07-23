import Foundation

public final class ScratchpadStore {
  public let noteURL: URL

  private let fileManager: FileManager

  public init(
    directoryURL: URL,
    fileManager: FileManager = .default
  ) throws {
    self.fileManager = fileManager
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )
    self.noteURL = directoryURL.appendingPathComponent("note.txt", isDirectory: false)
    if fileManager.fileExists(atPath: noteURL.path) {
      try fileManager.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: noteURL.path
      )
    }
  }

  public func load() throws -> String {
    guard fileManager.fileExists(atPath: noteURL.path) else {
      return ""
    }
    return try String(contentsOf: noteURL, encoding: .utf8)
  }

  public func save(_ text: String) throws {
    guard let data = text.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    try data.write(to: noteURL, options: [.atomic])
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: noteURL.path
    )
  }
}
