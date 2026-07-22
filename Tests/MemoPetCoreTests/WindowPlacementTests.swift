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

  func testClampedOriginKeepsWindowInsideVisibleFrame() {
    let origin = WindowPlacement.clampedOrigin(
      CGPoint(x: -500, y: 900),
      windowSize: CGSize(width: 80, height: 80),
      visibleFrame: CGRect(x: 0, y: 24, width: 1_000, height: 776)
    )

    XCTAssertEqual(origin, CGPoint(x: 0, y: 720))
  }
}
