import AppKit
import MemoPetCore

final class DrawingNoteView: NSView {
  var onChange: (([MemoStroke]) -> Void)?
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

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var currentStroke: MemoStroke?
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
    window?.makeFirstResponder(self)
    currentStroke = MemoStroke(
      points: [normalizedPoint(from: event)]
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

  private func appendPoint(from event: NSEvent) {
    guard var currentStroke else { return }

    let point = normalizedPoint(from: event)
    if let previous = currentStroke.points.last,
      distance(from: previous, to: point) < minimumPointDistance
    {
      return
    }

    currentStroke.points.append(point)
    self.currentStroke = currentStroke
    needsDisplay = true
  }

  private func normalizedPoint(from event: NSEvent) -> MemoPoint {
    let point = convert(event.locationInWindow, from: nil)
    let x = bounds.width > 0 ? point.x / bounds.width : 0
    let y = bounds.height > 0 ? point.y / bounds.height : 0

    return MemoPoint(
      x: quantized(min(max(x, 0), 1)),
      y: quantized(min(max(y, 0), 1))
    )
  }

  private func quantized(_ value: CGFloat) -> Double {
    (Double(value) * 10_000).rounded() / 10_000
  }

  private func distance(from lhs: MemoPoint, to rhs: MemoPoint) -> CGFloat {
    let dx = CGFloat(rhs.x - lhs.x) * bounds.width
    let dy = CGFloat(rhs.y - lhs.y) * bounds.height
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
      x: CGFloat(point.x) * bounds.width,
      y: CGFloat(point.y) * bounds.height
    )
  }
}
