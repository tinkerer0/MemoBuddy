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
    self.noteURL = directoryURL.appendingPathComponent("note.txt", isDirectory: false)
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
  }
}
