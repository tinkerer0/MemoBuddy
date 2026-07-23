import Foundation

public enum MemoDrawingEraser {
  public static func erasing(
    strokes: [MemoStroke],
    from start: MemoPoint,
    to end: MemoPoint,
    radius: Double
  ) -> [MemoStroke] {
    let radiusSquared = radius * radius
    guard radius.isFinite,
      radius > 0,
      radiusSquared.isFinite,
      start.x.isFinite,
      start.y.isFinite,
      end.x.isFinite,
      end.y.isFinite
    else {
      return strokes
    }

    return strokes.flatMap { stroke in
      erase(
        stroke: stroke,
        from: start,
        to: end,
        radiusSquared: radiusSquared
      )
    }
  }

  private static func erase(
    stroke: MemoStroke,
    from eraserStart: MemoPoint,
    to eraserEnd: MemoPoint,
    radiusSquared: Double
  ) -> [MemoStroke] {
    guard let firstPoint = stroke.points.first else { return [] }

    var fragments: [MemoStroke] = []
    var currentPoints: [MemoPoint] = []

    if pointToSegmentDistanceSquared(
      firstPoint,
      segmentStart: eraserStart,
      segmentEnd: eraserEnd
    ) > radiusSquared {
      currentPoints.append(firstPoint)
    }

    for pointIndex in stroke.points.indices.dropFirst() {
      let previousPoint = stroke.points[pointIndex - 1]
      let point = stroke.points[pointIndex]
      let pointIsErased = pointToSegmentDistanceSquared(
        point,
        segmentStart: eraserStart,
        segmentEnd: eraserEnd
      ) <= radiusSquared
      let connectingLineIsErased = segmentDistanceSquared(
        previousPoint,
        point,
        eraserStart,
        eraserEnd
      ) <= radiusSquared

      if pointIsErased || connectingLineIsErased {
        appendFragment(from: &currentPoints, to: &fragments)
        if !pointIsErased {
          currentPoints.append(point)
        }
      } else {
        currentPoints.append(point)
      }
    }

    appendFragment(from: &currentPoints, to: &fragments)
    return fragments
  }

  private static func appendFragment(
    from points: inout [MemoPoint],
    to fragments: inout [MemoStroke]
  ) {
    guard !points.isEmpty else { return }
    fragments.append(MemoStroke(points: points))
    points.removeAll(keepingCapacity: true)
  }

  private static func segmentDistanceSquared(
    _ firstStart: MemoPoint,
    _ firstEnd: MemoPoint,
    _ secondStart: MemoPoint,
    _ secondEnd: MemoPoint
  ) -> Double {
    if segmentsIntersect(
      firstStart,
      firstEnd,
      secondStart,
      secondEnd
    ) {
      return 0
    }

    return min(
      pointToSegmentDistanceSquared(
        firstStart,
        segmentStart: secondStart,
        segmentEnd: secondEnd
      ),
      pointToSegmentDistanceSquared(
        firstEnd,
        segmentStart: secondStart,
        segmentEnd: secondEnd
      ),
      pointToSegmentDistanceSquared(
        secondStart,
        segmentStart: firstStart,
        segmentEnd: firstEnd
      ),
      pointToSegmentDistanceSquared(
        secondEnd,
        segmentStart: firstStart,
        segmentEnd: firstEnd
      )
    )
  }

  private static func pointToSegmentDistanceSquared(
    _ point: MemoPoint,
    segmentStart: MemoPoint,
    segmentEnd: MemoPoint
  ) -> Double {
    let segmentX = segmentEnd.x - segmentStart.x
    let segmentY = segmentEnd.y - segmentStart.y
    let lengthSquared = (segmentX * segmentX) + (segmentY * segmentY)
    guard lengthSquared > 0 else {
      return squaredDistance(point, segmentStart)
    }

    let projection = (
      ((point.x - segmentStart.x) * segmentX)
        + ((point.y - segmentStart.y) * segmentY)
    ) / lengthSquared
    let clampedProjection = min(max(projection, 0), 1)
    let closestPoint = MemoPoint(
      x: segmentStart.x + (clampedProjection * segmentX),
      y: segmentStart.y + (clampedProjection * segmentY)
    )
    return squaredDistance(point, closestPoint)
  }

  private static func segmentsIntersect(
    _ firstStart: MemoPoint,
    _ firstEnd: MemoPoint,
    _ secondStart: MemoPoint,
    _ secondEnd: MemoPoint
  ) -> Bool {
    let firstToSecondStart = crossProduct(
      firstStart,
      firstEnd,
      secondStart
    )
    let firstToSecondEnd = crossProduct(
      firstStart,
      firstEnd,
      secondEnd
    )
    let secondToFirstStart = crossProduct(
      secondStart,
      secondEnd,
      firstStart
    )
    let secondToFirstEnd = crossProduct(
      secondStart,
      secondEnd,
      firstEnd
    )
    let epsilon = 0.000_000_001

    if ((firstToSecondStart > epsilon && firstToSecondEnd < -epsilon)
      || (firstToSecondStart < -epsilon && firstToSecondEnd > epsilon)),
      ((secondToFirstStart > epsilon && secondToFirstEnd < -epsilon)
        || (secondToFirstStart < -epsilon && secondToFirstEnd > epsilon))
    {
      return true
    }

    return
      (abs(firstToSecondStart) <= epsilon
        && point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd))
      || (abs(firstToSecondEnd) <= epsilon
        && point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd))
      || (abs(secondToFirstStart) <= epsilon
        && point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd))
      || (abs(secondToFirstEnd) <= epsilon
        && point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd))
  }

  private static func crossProduct(
    _ segmentStart: MemoPoint,
    _ segmentEnd: MemoPoint,
    _ point: MemoPoint
  ) -> Double {
    ((segmentEnd.x - segmentStart.x) * (point.y - segmentStart.y))
      - ((segmentEnd.y - segmentStart.y) * (point.x - segmentStart.x))
  }

  private static func point(
    _ point: MemoPoint,
    liesOnSegmentFrom start: MemoPoint,
    to end: MemoPoint
  ) -> Bool {
    let epsilon = 0.000_000_001
    return point.x >= min(start.x, end.x) - epsilon
      && point.x <= max(start.x, end.x) + epsilon
      && point.y >= min(start.y, end.y) - epsilon
      && point.y <= max(start.y, end.y) + epsilon
  }

  private static func squaredDistance(
    _ first: MemoPoint,
    _ second: MemoPoint
  ) -> Double {
    let x = second.x - first.x
    let y = second.y - first.y
    return (x * x) + (y * y)
  }
}
