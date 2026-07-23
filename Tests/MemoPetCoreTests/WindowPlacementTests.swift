import Foundation
import XCTest

@testable import MemoPetCore

final class WindowPlacementTests: XCTestCase {
  func testBubbleUsesRightSideWhenThereIsRoom() {
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: 100, y: 100, width: 80, height: 80),
      bubbleSize: CGSize(width: 300, height: 200),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
    )

    XCTAssertEqual(placement.tailSide, .left)
    XCTAssertEqual(placement.origin.x, 188)
    XCTAssertEqual(placement.origin.y, 40)
    XCTAssertEqual(placement.tailCenterY, 100)
  }

  func testBubbleFlipsLeftNearRightEdge() {
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: 900, y: 300, width: 80, height: 80),
      bubbleSize: CGSize(width: 300, height: 200),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
    )

    XCTAssertEqual(placement.tailSide, .right)
    XCTAssertEqual(placement.origin.x, 592)
  }

  func testBubbleTailTracksCharacterNearBottomEdge() {
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: 100, y: 0, width: 80, height: 80),
      bubbleSize: CGSize(width: 300, height: 200),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
    )

    XCTAssertEqual(placement.origin.y, 0)
    XCTAssertEqual(placement.tailCenterY, 40)
  }

  func testBubbleTailTracksCharacterNearTopEdge() {
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: 100, y: 720, width: 80, height: 80),
      bubbleSize: CGSize(width: 300, height: 200),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
    )

    XCTAssertEqual(placement.origin.y, 600)
    XCTAssertEqual(placement.tailCenterY, 160)
  }

  func testClampedOriginKeepsWindowInsideVisibleFrame() {
    let origin = WindowPlacement.clampedOrigin(
      CGPoint(x: -500, y: 900),
      windowSize: CGSize(width: 80, height: 80),
      visibleFrame: CGRect(x: 0, y: 24, width: 1_000, height: 776)
    )

    XCTAssertEqual(origin, CGPoint(x: 0, y: 720))
  }

  func testBubblePlacementSupportsASecondaryScreenWithNegativeCoordinates() {
    let visibleFrame = CGRect(x: -1_920, y: -120, width: 1_920, height: 1_080)
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: -110, y: 200, width: 80, height: 80),
      bubbleSize: CGSize(width: 360, height: 220),
      visibleFrame: visibleFrame
    )

    XCTAssertEqual(placement.tailSide, .right)
    XCTAssertGreaterThanOrEqual(placement.origin.x, visibleFrame.minX)
    XCTAssertLessThanOrEqual(placement.origin.x + 360, visibleFrame.maxX)
    XCTAssertGreaterThanOrEqual(placement.origin.y, visibleFrame.minY)
    XCTAssertLessThanOrEqual(placement.origin.y + 220, visibleFrame.maxY)
  }

  func testOversizedBubbleUsesStableVisibleFrameOrigin() {
    let visibleFrame = CGRect(x: 40, y: 25, width: 240, height: 160)
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: CGRect(x: 120, y: 70, width: 60, height: 60),
      bubbleSize: CGSize(width: 300, height: 180),
      visibleFrame: visibleFrame
    )

    XCTAssertEqual(placement.origin, visibleFrame.origin)
    XCTAssertTrue(placement.tailCenterY.isFinite)
  }

  func testBubbleRemainsInsideScreenAcrossManyDragPositions() {
    let visibleFrame = CGRect(x: 0, y: 24, width: 1_440, height: 876)
    let bubbleSize = CGSize(width: 360, height: 220)

    for x in stride(from: -80, through: 1_440, by: 40) {
      for y in stride(from: -40, through: 900, by: 60) {
        let placement = WindowPlacement.bubblePlacement(
          characterFrame: CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: 80,
            height: 80
          ),
          bubbleSize: bubbleSize,
          visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(placement.origin.x, visibleFrame.minX)
        XCTAssertLessThanOrEqual(
          placement.origin.x + bubbleSize.width,
          visibleFrame.maxX
        )
        XCTAssertGreaterThanOrEqual(placement.origin.y, visibleFrame.minY)
        XCTAssertLessThanOrEqual(
          placement.origin.y + bubbleSize.height,
          visibleFrame.maxY
        )
        XCTAssertTrue(placement.tailCenterY.isFinite)
      }
    }
  }
}
