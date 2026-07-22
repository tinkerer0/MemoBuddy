import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CharacterImageKind: String, Sendable {
  case gif
  case staticImage
}

public struct CharacterImageMetadata: Equatable, Sendable {
  public let kind: CharacterImageKind
  public let typeIdentifier: String
  public let fileExtension: String
  public let fileSize: Int64
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let frameCount: Int

  public var isAnimated: Bool {
    kind == .gif && frameCount > 1
  }

  public init(
    kind: CharacterImageKind,
    typeIdentifier: String,
    fileExtension: String,
    fileSize: Int64,
    pixelWidth: Int,
    pixelHeight: Int,
    frameCount: Int
  ) {
    self.kind = kind
    self.typeIdentifier = typeIdentifier
    self.fileExtension = fileExtension
    self.fileSize = fileSize
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.frameCount = frameCount
  }
}

public struct AnimatedImageLimits: Equatable, Sendable {
  public var maxFileSize: Int64
  public var maxAnimatedDimension: Int
  public var maxStaticDimension: Int
  public var maxFrameCount: Int
  public var maxTotalFramePixels: Int64

  public static let `default` = AnimatedImageLimits(
    maxFileSize: 20 * 1024 * 1024,
    maxAnimatedDimension: 1_024,
    maxStaticDimension: 4_096,
    maxFrameCount: 600,
    maxTotalFramePixels: 32_000_000
  )

  public init(
    maxFileSize: Int64,
    maxAnimatedDimension: Int,
    maxStaticDimension: Int,
    maxFrameCount: Int,
    maxTotalFramePixels: Int64
  ) {
    self.maxFileSize = maxFileSize
    self.maxAnimatedDimension = maxAnimatedDimension
    self.maxStaticDimension = maxStaticDimension
    self.maxFrameCount = maxFrameCount
    self.maxTotalFramePixels = maxTotalFramePixels
  }
}

public enum CharacterImageValidationError: LocalizedError, Equatable {
  case unreadable
  case incompleteData
  case unsupportedType(String?)
  case unsupportedAnimation
  case fileTooLarge(actual: Int64, maximum: Int64)
  case invalidDimensions
  case dimensionsTooLarge(width: Int, height: Int, maximum: Int)
  case tooManyFrames(actual: Int, maximum: Int)
  case decodedImageTooLarge(actual: Int64, maximum: Int64)

  public var errorDescription: String? {
    switch self {
    case .unreadable:
      return "The selected file could not be read as an image."
    case .incompleteData:
      return "The selected image is incomplete or damaged."
    case .unsupportedType(let type):
      return "Unsupported image type: \(type ?? "unknown"). Use GIF, PNG, JPEG, or WebP."
    case .unsupportedAnimation:
      return "Animated images other than GIF are not supported yet."
    case .fileTooLarge(let actual, let maximum):
      return "The image is too large (\(actual) bytes). The limit is \(maximum) bytes."
    case .invalidDimensions:
      return "The image has invalid pixel dimensions."
    case .dimensionsTooLarge(let width, let height, let maximum):
      return "The image is \(width)×\(height). Each side must be at most \(maximum) pixels."
    case .tooManyFrames(let actual, let maximum):
      return "The GIF has \(actual) frames. The limit is \(maximum)."
    case .decodedImageTooLarge(let actual, let maximum):
      return "The GIF is too expensive to animate (\(actual) frame-pixels; limit \(maximum))."
    }
  }
}

public struct AnimatedImageValidator: Sendable {
  public let limits: AnimatedImageLimits

  public init(limits: AnimatedImageLimits = .default) {
    self.limits = limits
  }

  public func validate(url: URL) throws -> CharacterImageMetadata {
    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard resourceValues.isRegularFile == true else {
      throw CharacterImageValidationError.unreadable
    }

    let fileSize = Int64(resourceValues.fileSize ?? 0)
    guard fileSize <= limits.maxFileSize else {
      throw CharacterImageValidationError.fileTooLarge(
        actual: fileSize,
        maximum: limits.maxFileSize
      )
    }

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw CharacterImageValidationError.unreadable
    }
    guard CGImageSourceGetStatus(source) == .statusComplete else {
      throw CharacterImageValidationError.incompleteData
    }
    guard let sourceTypeIdentifier = CGImageSourceGetType(source) as String?,
      let sourceType = UTType(sourceTypeIdentifier)
    else {
      throw CharacterImageValidationError.unsupportedType(nil)
    }

    let isGIF = sourceType.conforms(to: .gif)
    let isSupportedStatic = sourceType.conforms(to: .png)
      || sourceType.conforms(to: .jpeg)
      || sourceType.conforms(to: .webP)
    guard isGIF || isSupportedStatic else {
      throw CharacterImageValidationError.unsupportedType(sourceTypeIdentifier)
    }

    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else {
      throw CharacterImageValidationError.incompleteData
    }
    if !isGIF && frameCount > 1 {
      throw CharacterImageValidationError.unsupportedAnimation
    }

    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
      let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
      throw CharacterImageValidationError.invalidDimensions
    }

    let width = widthNumber.intValue
    let height = heightNumber.intValue
    guard width > 0, height > 0 else {
      throw CharacterImageValidationError.invalidDimensions
    }

    let maximumDimension = isGIF
      ? limits.maxAnimatedDimension
      : limits.maxStaticDimension
    guard width <= maximumDimension, height <= maximumDimension else {
      throw CharacterImageValidationError.dimensionsTooLarge(
        width: width,
        height: height,
        maximum: maximumDimension
      )
    }

    if isGIF {
      guard frameCount <= limits.maxFrameCount else {
        throw CharacterImageValidationError.tooManyFrames(
          actual: frameCount,
          maximum: limits.maxFrameCount
        )
      }

      let (framePixels, firstOverflow) = Int64(width).multipliedReportingOverflow(by: Int64(height))
      let (totalFramePixels, secondOverflow) = framePixels.multipliedReportingOverflow(
        by: Int64(frameCount)
      )
      guard !firstOverflow, !secondOverflow else {
        throw CharacterImageValidationError.decodedImageTooLarge(
          actual: .max,
          maximum: limits.maxTotalFramePixels
        )
      }
      guard totalFramePixels <= limits.maxTotalFramePixels else {
        throw CharacterImageValidationError.decodedImageTooLarge(
          actual: totalFramePixels,
          maximum: limits.maxTotalFramePixels
        )
      }
    }

    let fileExtension: String
    if isGIF {
      fileExtension = "gif"
    } else if sourceType.conforms(to: .png) {
      fileExtension = "png"
    } else if sourceType.conforms(to: .jpeg) {
      fileExtension = "jpg"
    } else {
      fileExtension = "webp"
    }

    return CharacterImageMetadata(
      kind: isGIF ? .gif : .staticImage,
      typeIdentifier: sourceTypeIdentifier,
      fileExtension: fileExtension,
      fileSize: fileSize,
      pixelWidth: width,
      pixelHeight: height,
      frameCount: frameCount
    )
  }
}
