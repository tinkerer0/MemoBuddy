import AppKit
import MemoPetCore

final class DrawingNoteView: NSView {
  var onChange: (([MemoStroke]) -> Void)?
  var onCoordinateMigration: (([MemoStroke]) -> Void)?
  var onEscape: (() -> Void)?

  var isDrawingEnabled = false {
    didSet {
      guard isDrawingEnabled != oldValue else { return }
      setAccessibilityEnabled(isDrawingEnabled)
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
  private var cursorTrackingArea: NSTrackingArea?
  private let lineWidth: CGFloat = 2.75
  private let minimumPointDistance: CGFloat = 1.5

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
    isDrawingEnabled && bounds.contains(point) ? self : nil
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
    guard isDrawingEnabled else { return }
    migrateLegacyCoordinatesIfPossible()
    window?.makeFirstResponder(self)
    currentStroke = MemoStroke(
      points: [drawingPoint(from: event)]
    )
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDrawingEnabled else { return }
    appendPoint(from: event)
  }

  override func mouseUp(with event: NSEvent) {
    guard isDrawingEnabled else { return }
    appendPoint(from: event)

    guard let currentStroke, !currentStroke.points.isEmpty else {
      self.currentStroke = nil
      return
    }

    strokes.append(currentStroke)
    self.currentStroke = nil
    needsDisplay = true
    onChange?(strokes)
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
    if isDrawingEnabled {
      addCursorRect(bounds, cursor: .crosshair)
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
      ],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    cursorTrackingArea = trackingArea
  }

  override func cursorUpdate(with event: NSEvent) {
    if isDrawingEnabled {
      NSCursor.crosshair.set()
    } else {
      super.cursorUpdate(with: event)
    }
  }

  override func mouseEntered(with event: NSEvent) {
    if isDrawingEnabled {
      NSCursor.crosshair.set()
    } else {
      super.mouseEntered(with: event)
    }
  }

  override func mouseExited(with event: NSEvent) {
    if isDrawingEnabled {
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
    guard !strokes.isEmpty else { return }
    strokes.removeLast()
    onChange?(strokes)
  }

  func clearDrawing() {
    guard !strokes.isEmpty else { return }
    strokes.removeAll()
    onChange?(strokes)
  }

  func display(
    strokes: [MemoStroke],
    coordinateSpace: MemoDrawingCoordinateSpace?
  ) {
    self.coordinateSpace = coordinateSpace
    self.strokes = strokes
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
}
