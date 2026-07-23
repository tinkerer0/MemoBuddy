import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MemoPetCore

final class AnimatedImageValidatorTests: XCTestCase {
  func testValidAnimatedGIFReportsMetadata() throws {
    let directory = try makeTemporaryDirectory()
    let gifURL = directory.appendingPathComponent("pet.gif")
    try writeGIF(to: gifURL, width: 16, height: 12, frameCount: 3)

    let metadata = try AnimatedImageValidator().validate(url: gifURL)

    XCTAssertEqual(metadata.kind, .gif)
    XCTAssertEqual(metadata.fileExtension, "gif")
    XCTAssertEqual(metadata.pixelWidth, 16)
    XCTAssertEqual(metadata.pixelHeight, 12)
    XCTAssertEqual(metadata.frameCount, 3)
    XCTAssertTrue(metadata.isAnimated)
  }

  func testGIFOverDecodedPixelBudgetIsRejected() throws {
    let directory = try makeTemporaryDirectory()
    let gifURL = directory.appendingPathComponent("heavy.gif")
    try writeGIF(to: gifURL, width: 16, height: 16, frameCount: 3)

    let limits = AnimatedImageLimits(
      maxFileSize: 1_000_000,
      maxAnimatedDimension: 100,
      maxStaticDimension: 100,
      maxFrameCount: 10,
      maxTotalFramePixels: 700
    )

    XCTAssertThrowsError(
      try AnimatedImageValidator(limits: limits).validate(url: gifURL)
    ) { error in
      XCTAssertEqual(
        error as? CharacterImageValidationError,
        .decodedImageTooLarge(actual: 768, maximum: 700)
      )
    }
  }

  func testCharacterStoreCopiesImageIntoOwnedDirectory() throws {
    let root = try makeTemporaryDirectory()
    let sourceURL = root.appendingPathComponent("source.gif")
    let storeURL = root.appendingPathComponent("store", isDirectory: true)
    try writeGIF(to: sourceURL, width: 8, height: 8, frameCount: 2)

    let store = try CharacterStore(directoryURL: storeURL)
    let imported = try store.importImage(from: sourceURL)
    try FileManager.default.removeItem(at: sourceURL)
    let loaded = try store.load()

    XCTAssertTrue(FileManager.default.fileExists(atPath: imported.url.path))
    XCTAssertEqual(loaded?.metadata.frameCount, 2)
    XCTAssertEqual(loaded?.url.lastPathComponent, "character.gif")
    XCTAssertEqual(try permissions(at: storeURL), 0o700)
    XCTAssertEqual(try permissions(at: imported.url), 0o600)

    try store.reset()
    XCTAssertNil(try store.load())
  }

  func testUnreadableStoredCharacterIsNotDeletedAutomatically() throws {
    let root = try makeTemporaryDirectory()
    let storeURL = root.appendingPathComponent("store", isDirectory: true)
    let store = try CharacterStore(directoryURL: storeURL)
    let invalidURL = storeURL.appendingPathComponent("character.gif")
    let invalidData = Data("not an image".utf8)
    try invalidData.write(to: invalidURL, options: [.atomic])

    XCTAssertTrue(store.hasStoredImage)
    XCTAssertThrowsError(try store.load())
    XCTAssertEqual(try Data(contentsOf: invalidURL), invalidData)
  }

  func testReplacingCharacterValidatesBeforeAtomicallyReplacingIt() throws {
    let root = try makeTemporaryDirectory()
    let firstURL = root.appendingPathComponent("first.gif")
    let secondURL = root.appendingPathComponent("second.gif")
    let storeURL = root.appendingPathComponent("store", isDirectory: true)
    try writeGIF(to: firstURL, width: 8, height: 8, frameCount: 2)
    try writeGIF(to: secondURL, width: 8, height: 8, frameCount: 4)
    let store = try CharacterStore(directoryURL: storeURL)

    try store.importImage(from: firstURL)
    try store.importImage(from: secondURL)

    XCTAssertEqual(try store.load()?.metadata.frameCount, 4)
    let stagingFiles = try FileManager.default.contentsOfDirectory(
      at: storeURL,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix(".character-import-") }
    XCTAssertTrue(stagingFiles.isEmpty)
  }

  func testLoadSkipsDamagedCandidateWhenAnotherStoredImageIsValid() throws {
    let root = try makeTemporaryDirectory()
    let storeURL = root.appendingPathComponent("store", isDirectory: true)
    let store = try CharacterStore(directoryURL: storeURL)
    try Data("damaged".utf8).write(
      to: storeURL.appendingPathComponent("character.gif"),
      options: [.atomic]
    )
    let validURL = storeURL.appendingPathComponent("character.png")
    try writeGIF(to: validURL, width: 8, height: 8, frameCount: 2)

    let loaded = try store.load()

    XCTAssertEqual(loaded?.url.lastPathComponent, "character.png")
    XCTAssertEqual(loaded?.metadata.frameCount, 2)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MemoPetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(
      attributes[.posixPermissions] as? NSNumber
    ).intValue & 0o777
  }

  private func writeGIF(
    to url: URL,
    width: Int,
    height: Int,
    frameCount: Int
  ) throws {
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.gif.identifier as CFString,
      frameCount,
      nil
    ) else {
      throw TestImageError.couldNotCreateDestination
    }

    let containerProperties: [CFString: Any] = [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
      ]
    ]
    CGImageDestinationSetProperties(destination, containerProperties as CFDictionary)

    for index in 0..<frameCount {
      guard let image = makeImage(width: width, height: height, index: index) else {
        throw TestImageError.couldNotCreateFrame
      }
      let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: 0.1
        ]
      ]
      CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else {
      throw TestImageError.couldNotFinalize
    }
  }

  private func makeImage(width: Int, height: Int, index: Int) -> CGImage? {
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    let red = CGFloat((index + 1) % 3) / 2
    let green = CGFloat((index + 2) % 3) / 2
    context.setFillColor(CGColor(red: red, green: green, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }
}

private enum TestImageError: Error {
  case couldNotCreateDestination
  case couldNotCreateFrame
  case couldNotFinalize
}
