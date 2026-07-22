import AppKit
import MemoPetCore

final class ScratchpadTextView: NSTextView {
  var onEscape: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, !hasMarkedText() {
      onEscape?()
      return
    }
    super.keyDown(with: event)
  }
}

final class BubbleBackgroundView: NSView {
  let textView: ScratchpadTextView

  var tailSide: BubbleTailSide = .left {
    didSet {
      needsDisplay = true
      needsLayout = true
    }
  }

  private let scrollView: NSScrollView
  private let errorLabel = NSTextField(labelWithString: "")
  private let tailWidth: CGFloat = 18

  override init(frame frameRect: NSRect) {
    let scrollView = NSScrollView(frame: .zero)
    let textView = ScratchpadTextView(frame: .zero)
    scrollView.documentView = textView

    self.scrollView = scrollView
    self.textView = textView
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.font = .systemFont(ofSize: 14)
    textView.textColor = .labelColor
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainer?.widthTracksTextView = true

    errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = .systemRed
    errorLabel.lineBreakMode = .byTruncatingTail
    errorLabel.isHidden = true

    addSubview(scrollView)
    addSubview(errorLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()

    let body = bodyRect.insetBy(dx: 12, dy: 10)
    let errorHeight: CGFloat = errorLabel.isHidden ? 0 : 18
    errorLabel.frame = NSRect(
      x: body.minX + 4,
      y: body.minY,
      width: body.width - 8,
      height: errorHeight
    )
    scrollView.frame = NSRect(
      x: body.minX,
      y: body.minY + errorHeight,
      width: body.width,
      height: max(0, body.height - errorHeight)
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let path = bubblePath()

    let fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97)
    fillColor.setFill()
    path.fill()

    NSColor.separatorColor.withAlphaComponent(0.65).setStroke()
    path.lineWidth = 1
    path.lineJoinStyle = .round
    path.stroke()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  func showError(_ message: String?) {
    errorLabel.stringValue = message ?? ""
    errorLabel.isHidden = message == nil
    needsLayout = true
  }

  private var bodyRect: NSRect {
    switch tailSide {
    case .left:
      return NSRect(
        x: tailWidth,
        y: 1,
        width: bounds.width - tailWidth - 1,
        height: bounds.height - 2
      )
    case .right:
      return NSRect(
        x: 1,
        y: 1,
        width: bounds.width - tailWidth - 1,
        height: bounds.height - 2
      )
    }
  }

  private func bubblePath() -> NSBezierPath {
    let rect = bodyRect
    let radius = min(18, min(rect.width / 2, rect.height / 2))
    let cornerControl = radius * 0.552_284_75
    let tailCenterY = bounds.midY
    let tailHalfHeight: CGFloat = 14
    let path = NSBezierPath()

    path.move(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX - radius, y: rect.maxY))

    switch tailSide {
    case .left:
      appendTopRightCorner(to: path, rect: rect, radius: radius, control: cornerControl)
      appendBottomRightCorner(to: path, rect: rect, radius: radius, control: cornerControl)
      appendBottomLeftCorner(to: path, rect: rect, radius: radius, control: cornerControl)

      path.line(to: NSPoint(x: rect.minX, y: tailCenterY - tailHalfHeight))
      path.curve(
        to: NSPoint(x: bounds.minX + 1, y: tailCenterY),
        controlPoint1: NSPoint(x: rect.minX, y: tailCenterY - 8),
        controlPoint2: NSPoint(x: bounds.minX + 4, y: tailCenterY - 3)
      )
      path.curve(
        to: NSPoint(x: rect.minX, y: tailCenterY + tailHalfHeight),
        controlPoint1: NSPoint(x: bounds.minX + 4, y: tailCenterY + 3),
        controlPoint2: NSPoint(x: rect.minX, y: tailCenterY + 8)
      )
      path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
      appendTopLeftCorner(to: path, rect: rect, radius: radius, control: cornerControl)

    case .right:
      appendTopRightCorner(to: path, rect: rect, radius: radius, control: cornerControl)
      path.line(to: NSPoint(x: rect.maxX, y: tailCenterY + tailHalfHeight))
      path.curve(
        to: NSPoint(x: bounds.maxX - 1, y: tailCenterY),
        controlPoint1: NSPoint(x: rect.maxX, y: tailCenterY + 8),
        controlPoint2: NSPoint(x: bounds.maxX - 4, y: tailCenterY + 3)
      )
      path.curve(
        to: NSPoint(x: rect.maxX, y: tailCenterY - tailHalfHeight),
        controlPoint1: NSPoint(x: bounds.maxX - 4, y: tailCenterY - 3),
        controlPoint2: NSPoint(x: rect.maxX, y: tailCenterY - 8)
      )
      path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
      appendBottomRightCorner(to: path, rect: rect, radius: radius, control: cornerControl)
      appendBottomLeftCorner(to: path, rect: rect, radius: radius, control: cornerControl)
      path.line(to: NSPoint(x: rect.minX, y: rect.maxY - radius))
      appendTopLeftCorner(to: path, rect: rect, radius: radius, control: cornerControl)
    }

    path.close()
    return path
  }

  private func appendTopRightCorner(
    to path: NSBezierPath,
    rect: NSRect,
    radius: CGFloat,
    control: CGFloat
  ) {
    path.curve(
      to: NSPoint(x: rect.maxX, y: rect.maxY - radius),
      controlPoint1: NSPoint(x: rect.maxX - radius + control, y: rect.maxY),
      controlPoint2: NSPoint(x: rect.maxX, y: rect.maxY - radius + control)
    )
  }

  private func appendBottomRightCorner(
    to path: NSBezierPath,
    rect: NSRect,
    radius: CGFloat,
    control: CGFloat
  ) {
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
    path.curve(
      to: NSPoint(x: rect.maxX - radius, y: rect.minY),
      controlPoint1: NSPoint(x: rect.maxX, y: rect.minY + radius - control),
      controlPoint2: NSPoint(x: rect.maxX - radius + control, y: rect.minY)
    )
  }

  private func appendBottomLeftCorner(
    to path: NSBezierPath,
    rect: NSRect,
    radius: CGFloat,
    control: CGFloat
  ) {
    path.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
    path.curve(
      to: NSPoint(x: rect.minX, y: rect.minY + radius),
      controlPoint1: NSPoint(x: rect.minX + radius - control, y: rect.minY),
      controlPoint2: NSPoint(x: rect.minX, y: rect.minY + radius - control)
    )
  }

  private func appendTopLeftCorner(
    to path: NSBezierPath,
    rect: NSRect,
    radius: CGFloat,
    control: CGFloat
  ) {
    path.curve(
      to: NSPoint(x: rect.minX + radius, y: rect.maxY),
      controlPoint1: NSPoint(x: rect.minX, y: rect.maxY - radius + control),
      controlPoint2: NSPoint(x: rect.minX + radius - control, y: rect.maxY)
    )
  }
}
