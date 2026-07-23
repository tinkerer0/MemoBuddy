import Foundation

public struct CharacterAsset: Equatable, Sendable {
  public let url: URL
  public let metadata: CharacterImageMetadata

  public init(url: URL, metadata: CharacterImageMetadata) {
    self.url = url
    self.metadata = metadata
  }
}

public final class CharacterStore {
  public let directoryURL: URL

  private let fileManager: FileManager
  private let validator: AnimatedImageValidator
  private let supportedExtensions = ["gif", "png", "jpg", "webp"]

  public var hasStoredImage: Bool {
    supportedExtensions.contains { fileExtension in
      fileManager.fileExists(
        atPath: storedURL(fileExtension: fileExtension).path
      )
    }
  }

  public init(
    directoryURL: URL,
    fileManager: FileManager = .default,
    validator: AnimatedImageValidator = AnimatedImageValidator()
  ) throws {
    self.directoryURL = directoryURL
    self.fileManager = fileManager
    self.validator = validator
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try fileManager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )
    for fileExtension in supportedExtensions {
      let url = storedURL(fileExtension: fileExtension)
      if fileManager.fileExists(atPath: url.path) {
        try secureFile(at: url)
      }
    }
  }

  public func load() throws -> CharacterAsset? {
    var firstError: Error?
    for fileExtension in supportedExtensions {
      let candidateURL = storedURL(fileExtension: fileExtension)
      guard fileManager.fileExists(atPath: candidateURL.path) else { continue }
      do {
        return CharacterAsset(
          url: candidateURL,
          metadata: try validator.validate(url: candidateURL)
        )
      } catch {
        firstError = firstError ?? error
      }
    }
    if let firstError { throw firstError }
    return nil
  }

  @discardableResult
  public func importImage(from sourceURL: URL) throws -> CharacterAsset {
    _ = try validator.validate(url: sourceURL)
    let data = try readImageData(from: sourceURL)
    let stagingURL = directoryURL
      .appendingPathComponent(
        ".character-import-\(UUID().uuidString)",
        isDirectory: false
      )
      .appendingPathExtension(sourceURL.pathExtension)

    defer {
      if fileManager.fileExists(atPath: stagingURL.path) {
        try? fileManager.removeItem(at: stagingURL)
      }
    }

    try data.write(to: stagingURL, options: [.atomic])
    let metadata = try validator.validate(url: stagingURL)
    let destinationURL = storedURL(fileExtension: metadata.fileExtension)

    if fileManager.fileExists(atPath: destinationURL.path) {
      _ = try fileManager.replaceItemAt(
        destinationURL,
        withItemAt: stagingURL
      )
    } else {
      try fileManager.moveItem(at: stagingURL, to: destinationURL)
    }
    try secureFile(at: destinationURL)

    for fileExtension in supportedExtensions
    where fileExtension != metadata.fileExtension
    {
      let oldURL = storedURL(fileExtension: fileExtension)
      if fileManager.fileExists(atPath: oldURL.path) {
        try fileManager.removeItem(at: oldURL)
      }
    }

    return CharacterAsset(url: destinationURL, metadata: metadata)
  }

  public func reset() throws {
    for fileExtension in supportedExtensions {
      let url = storedURL(fileExtension: fileExtension)
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
    }
  }

  private func readImageData(from sourceURL: URL) throws -> Data {
    let maximum = validator.limits.maxFileSize
    guard maximum < Int64(Int.max) else {
      throw CharacterImageValidationError.fileTooLarge(
        actual: maximum,
        maximum: maximum
      )
    }

    let handle = try FileHandle(forReadingFrom: sourceURL)
    defer {
      try? handle.close()
    }

    let data = try handle.read(upToCount: Int(maximum) + 1) ?? Data()
    guard Int64(data.count) <= maximum else {
      throw CharacterImageValidationError.fileTooLarge(
        actual: Int64(data.count),
        maximum: maximum
      )
    }
    return data
  }

  private func secureFile(at url: URL) throws {
    try fileManager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  private func storedURL(fileExtension: String) -> URL {
    directoryURL
      .appendingPathComponent("character", isDirectory: false)
      .appendingPathExtension(fileExtension)
  }
}
