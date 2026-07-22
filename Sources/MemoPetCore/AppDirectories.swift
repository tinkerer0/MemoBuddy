import Foundation

public enum AppDirectories {
  public static func applicationSupportURL(
    fileManager: FileManager = .default
  ) throws -> URL {
    let baseURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directoryURL = baseURL.appendingPathComponent("MemoPet", isDirectory: true)
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    return directoryURL
  }
}
