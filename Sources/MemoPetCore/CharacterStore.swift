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
  }

  public func load() throws -> CharacterAsset? {
    for fileExtension in supportedExtensions {
      let candidateURL = storedURL(fileExtension: fileExtension)
      guard fileManager.fileExists(atPath: candidateURL.path) else { continue }
      return CharacterAsset(
        url: candidateURL,
        metadata: try validator.validate(url: candidateURL)
      )
    }
    return nil
  }

  @discardableResult
  public func importImage(from sourceURL: URL) throws -> CharacterAsset {
    let metadata = try validator.validate(url: sourceURL)
    let destinationURL = storedURL(fileExtension: metadata.fileExtension)
    let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
    try data.write(to: destinationURL, options: [.atomic])

    for fileExtension in supportedExtensions where fileExtension != metadata.fileExtension {
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

  private func storedURL(fileExtension: String) -> URL {
    directoryURL
      .appendingPathComponent("character", isDirectory: false)
      .appendingPathExtension(fileExtension)
  }
}
