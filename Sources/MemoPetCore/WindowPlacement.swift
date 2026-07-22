import Foundation

public enum BubbleTailSide: Equatable, Sendable {
  case left
  case right
}

public struct BubblePlacement: Equatable, Sendable {
  public let origin: CGPoint
  public let tailSide: BubbleTailSide
  public let tailCenterY: CGFloat

  public init(
    origin: CGPoint,
    tailSide: BubbleTailSide,
    tailCenterY: CGFloat
  ) {
    self.origin = origin
    self.tailSide = tailSide
    self.tailCenterY = tailCenterY
  }
}

public enum WindowPlacement {
  public static func bubblePlacement(
    characterFrame: CGRect,
    bubbleSize: CGSize,
    visibleFrame: CGRect,
    gap: CGFloat = 8
  ) -> BubblePlacement {
    let rightOriginX = characterFrame.maxX + gap
    let leftOriginX = characterFrame.minX - gap - bubbleSize.width

    let originX: CGFloat
    let tailSide: BubbleTailSide
    if rightOriginX + bubbleSize.width <= visibleFrame.maxX {
      originX = rightOriginX
      tailSide = .left
    } else if leftOriginX >= visibleFrame.minX {
      originX = leftOriginX
      tailSide = .right
    } else {
      originX = clamp(
        rightOriginX,
        minimum: visibleFrame.minX,
        maximum: visibleFrame.maxX - bubbleSize.width
      )
      tailSide = characterFrame.midX < visibleFrame.midX ? .left : .right
    }

    let originY = clamp(
      characterFrame.midY - (bubbleSize.height / 2),
      minimum: visibleFrame.minY,
      maximum: visibleFrame.maxY - bubbleSize.height
    )

    return BubblePlacement(
      origin: CGPoint(x: originX, y: originY),
      tailSide: tailSide,
      tailCenterY: characterFrame.midY - originY
    )
  }

  public static func clampedOrigin(
    _ origin: CGPoint,
    windowSize: CGSize,
    visibleFrame: CGRect
  ) -> CGPoint {
    CGPoint(
      x: clamp(
        origin.x,
        minimum: visibleFrame.minX,
        maximum: visibleFrame.maxX - windowSize.width
      ),
      y: clamp(
        origin.y,
        minimum: visibleFrame.minY,
        maximum: visibleFrame.maxY - windowSize.height
      )
    )
  }

  private static func clamp(
    _ value: CGFloat,
    minimum: CGFloat,
    maximum: CGFloat
  ) -> CGFloat {
    guard maximum >= minimum else { return minimum }
    return min(max(value, minimum), maximum)
  }
}
