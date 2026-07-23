import AppKit
import MemoPetCore

enum DrawingNoteTool {
  case inactive
  case draw
  case erase
}

final class DrawingNoteView: NSView {
  var onChange: (([MemoStroke]) -> Void)?
  var onCoordinateMigration: (([MemoStroke]) -> Void)?
  var onEscape: (() -> Void)?

  var activeTool: DrawingNoteTool = .inactive {
    didSet {
      guard activeTool != oldValue else { return }
      currentStroke = nil
      resetEraserGesture()
      setAccessibilityEnabled(activeTool != .inactive)
      setAccessibilityLabel(
        activeTool == .erase ? "Erase drawing" : "Drawing note"
      )
      window?.invalidateCursorRects(for: self)
    }
  }

  var strokes: [MemoStroke] = [] {
    didSet {
      needsDisplay = true
    }
  }

  private(set) var coordinateSpace: MemoDrawingCoordinateSpace? = .absolutePoints

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var currentStroke: MemoStroke?
  private var lastEraserPoint: MemoPoint?
  private var eraserStartStrokes: [MemoStroke]?
  private var eraserDidChange = false
  private var undoHistory: [[MemoStroke]] = []
  private var cursorTrackingArea: NSTrackingArea?
  private let lineWidth: CGFloat = 2.75
  private let minimumPointDistance: CGFloat = 1.5
  private let maximumUndoDepth = 20
  private static let eraserRadius = 9.0
  private static let eraserCursor = makeEraserCursor()

  var cursorForActiveTool: NSCursor? {
    switch activeTool {
    case .inactive:
      return nil
    case .draw:
      return .crosshair
    case .erase:
      return Self.eraserCursor
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    setAccessibilityElement(true)
    setAccessibilityLabel("Drawing note")
    setAccessibilityEnabled(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    activeTool != .inactive && bounds.contains(point) ? self : nil
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: bounds).addClip()

    NSColor.textColor.setStroke()
    NSColor.textColor.setFill()
    for stroke in strokes {
      draw(stroke)
    }
    if let currentStroke {
      draw(currentStroke)
    }

    NSGraphicsContext.restoreGraphicsState()
  }

  override func mouseDown(with event: NSEvent) {
    guard activeTool != .inactive else { return }
    cursorForActiveTool?.set()
    migrateLegacyCoordinatesIfPossible()
    window?.makeFirstResponder(self)
    let point = drawingPoint(from: event)

    switch activeTool {
    case .inactive:
      break
    case .draw:
      currentStroke = MemoStroke(points: [point])
      needsDisplay = true
    case .erase:
      lastEraserPoint = point
      eraserStartStrokes = strokes
      eraserDidChange = false
      erase(from: point, to: point)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard activeTool != .inactive else { return }
    cursorForActiveTool?.set()

    switch activeTool {
    case .inactive:
      break
    case .draw:
      appendPoint(from: event)
    case .erase:
      let point = drawingPoint(from: event)
      erase(from: lastEraserPoint ?? point, to: point)
      lastEraserPoint = point
    }
  }

  override func mouseUp(with event: NSEvent) {
    switch activeTool {
    case .inactive:
      return
    case .draw:
      appendPoint(from: event)

      guard let currentStroke, !currentStroke.points.isEmpty else {
        self.currentStroke = nil
        return
      }

      recordUndoState(strokes)
      strokes.append(currentStroke)
      self.currentStroke = nil
      needsDisplay = true
      onChange?(strokes)
    case .erase:
      let point = drawingPoint(from: event)
      erase(from: lastEraserPoint ?? point, to: point)
      if eraserDidChange, let eraserStartStrokes {
        recordUndoState(eraserStartStrokes)
        onChange?(strokes)
      }
      resetEraserGesture()
    }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onEscape?()
      return
    }

    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == .command,
      event.charactersIgnoringModifiers?.lowercased() == "z"
    {
      undoLastStroke()
      return
    }

    super.keyDown(with: event)
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    if let cursorForActiveTool {
      addCursorRect(bounds, cursor: cursorForActiveTool)
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let cursorTrackingArea {
      removeTrackingArea(cursorTrackingArea)
    }

    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [
        .activeAlways,
        .cursorUpdate,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved,
      ],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    cursorTrackingArea = trackingArea
  }

  override func cursorUpdate(with event: NSEvent) {
    if let cursorForActiveTool {
      cursorForActiveTool.set()
    } else {
      super.cursorUpdate(with: event)
    }
  }

  override func mouseEntered(with event: NSEvent) {
    if let cursorForActiveTool {
      cursorForActiveTool.set()
    } else {
      super.mouseEntered(with: event)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    if let cursorForActiveTool {
      cursorForActiveTool.set()
    } else {
      super.mouseMoved(with: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    if activeTool != .inactive {
      NSCursor.arrow.set()
    } else {
      super.mouseExited(with: event)
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  func undoLastStroke() {
    guard let previousStrokes = undoHistory.popLast() else { return }
    strokes = previousStrokes
    onChange?(strokes)
  }

  func display(
    strokes: [MemoStroke],
    coordinateSpace: MemoDrawingCoordinateSpace?
  ) {
    self.coordinateSpace = coordinateSpace
    self.strokes = strokes
    undoHistory.removeAll()
    migrateLegacyCoordinatesIfPossible()
  }

  func migrateLegacyCoordinatesIfPossible() {
    guard coordinateSpace == nil,
      bounds.width.isFinite,
      bounds.height.isFinite,
      bounds.width > 0,
      bounds.height > 0
    else {
      return
    }

    strokes = MemoDrawingCoordinates.convertingLegacyNormalizedStrokes(
      strokes,
      canvasWidth: Double(bounds.width),
      canvasHeight: Double(bounds.height)
    )
    coordinateSpace = .absolutePoints
    onCoordinateMigration?(strokes)
  }

  private func appendPoint(from event: NSEvent) {
    guard var currentStroke else { return }

    let point = drawingPoint(from: event)
    if let previous = currentStroke.points.last,
      distance(from: previous, to: point) < minimumPointDistance
    {
      return
    }

    currentStroke.points.append(point)
    self.currentStroke = currentStroke
    needsDisplay = true
  }

  private func erase(from start: MemoPoint, to end: MemoPoint) {
    let erasedStrokes = MemoDrawingEraser.erasing(
      strokes: strokes,
      from: start,
      to: end,
      radius: Self.eraserRadius
    )
    guard erasedStrokes != strokes else { return }
    strokes = erasedStrokes
    eraserDidChange = true
  }

  private func resetEraserGesture() {
    lastEraserPoint = nil
    eraserStartStrokes = nil
    eraserDidChange = false
  }

  private func recordUndoState(_ previousStrokes: [MemoStroke]) {
    undoHistory.append(previousStrokes)
    if undoHistory.count > maximumUndoDepth {
      undoHistory.removeFirst(undoHistory.count - maximumUndoDepth)
    }
  }

  private func drawingPoint(from event: NSEvent) -> MemoPoint {
    let point = convert(event.locationInWindow, from: nil)
    let x = min(max(point.x, 0), bounds.width)
    let y = min(max(point.y, 0), bounds.height)

    return MemoPoint(
      x: quantized(x),
      y: quantized(y)
    )
  }

  private func quantized(_ value: CGFloat) -> Double {
    (Double(value) * 10_000).rounded() / 10_000
  }

  private func distance(from lhs: MemoPoint, to rhs: MemoPoint) -> CGFloat {
    let dx = CGFloat(rhs.x - lhs.x)
    let dy = CGFloat(rhs.y - lhs.y)
    return hypot(dx, dy)
  }

  private func draw(_ stroke: MemoStroke) {
    let points = stroke.points.map(canvasPoint)
    guard let first = points.first else { return }

    if points.count == 1 {
      let dotRect = NSRect(
        x: first.x - (lineWidth / 2),
        y: first.y - (lineWidth / 2),
        width: lineWidth,
        height: lineWidth
      )
      NSBezierPath(ovalIn: dotRect).fill()
      return
    }

    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
      path.line(to: point)
    }
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
  }

  private func canvasPoint(_ point: MemoPoint) -> NSPoint {
    NSPoint(
      x: CGFloat(point.x),
      y: CGFloat(point.y)
    )
  }

  private static func makeEraserCursor() -> NSCursor {
    let padding: CGFloat = 2
    let diameter = CGFloat(eraserRadius * 2)
    let imageSize = NSSize(
      width: diameter + (padding * 2),
      height: diameter + (padding * 2)
    )
    let image = NSImage(size: imageSize, flipped: false) { rect in
      let circle = NSBezierPath(
        ovalIn: rect.insetBy(dx: padding, dy: padding)
      )
      NSColor.white.withAlphaComponent(0.95).setStroke()
      circle.lineWidth = 3
      circle.stroke()
      NSColor.black.withAlphaComponent(0.9).setStroke()
      circle.lineWidth = 1
      circle.stroke()
      return true
    }
    return NSCursor(
      image: image,
      hotSpot: NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
    )
  }
}
