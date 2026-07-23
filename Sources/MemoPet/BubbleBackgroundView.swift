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
  let drawingView: DrawingNoteView

  var onPreviousNote: (() -> Void)?
  var onNextNote: (() -> Void)?
  var onAddNote: ((MemoNoteKind) -> Void)?
  var onDeleteNote: (() -> Void)?

  var tailSide: BubbleTailSide = .left {
    didSet {
      needsDisplay = true
      needsLayout = true
    }
  }

  var tailCenterY: CGFloat? {
    didSet {
      needsDisplay = true
    }
  }

  private let scrollView: NSScrollView
  private let toolbarView = NSView(frame: .zero)
  private let toolbarSeparator = NSBox(frame: .zero)
  private let errorLabel = NSTextField(labelWithString: "")
  private let noteCountLabel = NSTextField(labelWithString: "1 / 1")
  private let previousButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "chevron.left",
    accessibilityLabel: "Previous note"
  )
  private let nextButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "chevron.right",
    accessibilityLabel: "Next note"
  )
  private let addButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "plus.circle",
    accessibilityLabel: "Add note"
  )
  private let moreButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "ellipsis",
    accessibilityLabel: "More note actions"
  )
  private let tailWidth: CGFloat = 18
  private let tailHalfHeight: CGFloat = 14
  private let cornerRadius: CGFloat = 18
  private var activeKind: MemoNoteKind = .text

  override init(frame frameRect: NSRect) {
    let scrollView = NSScrollView(frame: .zero)
    let textView = ScratchpadTextView(frame: .zero)
    let drawingView = DrawingNoteView(frame: .zero)
    scrollView.documentView = textView

    self.scrollView = scrollView
    self.textView = textView
    self.drawingView = drawingView
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

    drawingView.isHidden = true

    noteCountLabel.font = .monospacedDigitSystemFont(
      ofSize: 11,
      weight: .regular
    )
    noteCountLabel.textColor = .secondaryLabelColor
    noteCountLabel.alignment = .center
    noteCountLabel.lineBreakMode = .byClipping
    noteCountLabel.setAccessibilityLabel("Current note")

    toolbarSeparator.boxType = .separator

    previousButton.target = self
    previousButton.action = #selector(showPreviousNote)
    nextButton.target = self
    nextButton.action = #selector(showNextNote)
    addButton.target = self
    addButton.action = #selector(showAddMenu)
    moreButton.target = self
    moreButton.action = #selector(showMoreMenu)

    errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = .systemRed
    errorLabel.lineBreakMode = .byTruncatingTail
    errorLabel.isHidden = true

    toolbarView.addSubview(previousButton)
    toolbarView.addSubview(noteCountLabel)
    toolbarView.addSubview(nextButton)
    toolbarView.addSubview(addButton)
    toolbarView.addSubview(moreButton)

    addSubview(scrollView)
    addSubview(drawingView)
    addSubview(toolbarSeparator)
    addSubview(toolbarView)
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
    let toolbarHeight: CGFloat = 26
    let editorBottom = body.minY + errorHeight

    errorLabel.frame = NSRect(
      x: body.minX + 4,
      y: body.minY,
      width: body.width - 8,
      height: errorHeight
    )

    toolbarView.frame = NSRect(
      x: body.minX + 4,
      y: body.maxY - toolbarHeight,
      width: body.width - 8,
      height: toolbarHeight
    )
    toolbarSeparator.frame = NSRect(
      x: body.minX + 4,
      y: toolbarView.frame.minY - 4,
      width: body.width - 8,
      height: 1
    )

    previousButton.frame = NSRect(x: 0, y: 1, width: 24, height: 24)
    noteCountLabel.frame = NSRect(x: 25, y: 4, width: 48, height: 18)
    nextButton.frame = NSRect(x: 74, y: 1, width: 24, height: 24)
    moreButton.frame = NSRect(
      x: toolbarView.bounds.maxX - 24,
      y: 1,
      width: 24,
      height: 24
    )
    addButton.frame = NSRect(
      x: moreButton.frame.minX - 28,
      y: 1,
      width: 24,
      height: 24
    )

    let editorFrame = NSRect(
      x: body.minX + 4,
      y: editorBottom,
      width: body.width - 8,
      height: max(0, toolbarSeparator.frame.minY - 5 - editorBottom)
    )
    scrollView.frame = editorFrame
    drawingView.frame = editorFrame
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

  func display(note: MemoNote, index: Int, total: Int) {
    activeKind = note.kind
    textView.string = note.text
    drawingView.strokes = note.strokes

    scrollView.isHidden = note.kind != .text
    drawingView.isHidden = note.kind != .drawing
    noteCountLabel.stringValue = "\(index + 1) / \(total)"
    previousButton.isEnabled = index > 0
    nextButton.isEnabled = index + 1 < total
    showError(nil)
  }

  func focusActiveEditor(in window: NSWindow) {
    switch activeKind {
    case .text:
      window.makeFirstResponder(textView)
      let end = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: end, length: 0))
      textView.scrollRangeToVisible(NSRange(location: end, length: 0))
    case .drawing:
      window.makeFirstResponder(drawingView)
    }
  }

  var currentText: String {
    textView.string
  }

  var currentStrokes: [MemoStroke] {
    drawingView.strokes
  }

  @objc private func showPreviousNote() {
    onPreviousNote?()
  }

  @objc private func showNextNote() {
    onNextNote?()
  }

  @objc private func showAddMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let textItem = NSMenuItem(
      title: "Text Note",
      action: #selector(addTextNote),
      keyEquivalent: ""
    )
    textItem.target = self
    textItem.image = NSImage(
      systemSymbolName: "note.text",
      accessibilityDescription: nil
    )
    menu.addItem(textItem)

    let drawingItem = NSMenuItem(
      title: "Drawing Note",
      action: #selector(addDrawingNote),
      keyEquivalent: ""
    )
    drawingItem.target = self
    drawingItem.image = NSImage(
      systemSymbolName: "pencil.and.outline",
      accessibilityDescription: nil
    )
    menu.addItem(drawingItem)

    popUp(menu, from: addButton)
  }

  @objc private func showMoreMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false

    if activeKind == .drawing {
      let undoItem = NSMenuItem(
        title: "Undo Last Stroke",
        action: #selector(undoLastStroke),
        keyEquivalent: ""
      )
      undoItem.target = self
      undoItem.isEnabled = !drawingView.strokes.isEmpty
      undoItem.image = NSImage(
        systemSymbolName: "arrow.uturn.backward",
        accessibilityDescription: nil
      )
      menu.addItem(undoItem)

      let clearItem = NSMenuItem(
        title: "Clear Drawing",
        action: #selector(clearDrawing),
        keyEquivalent: ""
      )
      clearItem.target = self
      clearItem.isEnabled = !drawingView.strokes.isEmpty
      clearItem.image = NSImage(
        systemSymbolName: "eraser",
        accessibilityDescription: nil
      )
      menu.addItem(clearItem)
      menu.addItem(.separator())
    }

    let deleteItem = NSMenuItem(
      title: "Delete Note",
      action: #selector(deleteNote),
      keyEquivalent: ""
    )
    deleteItem.target = self
    deleteItem.image = NSImage(
      systemSymbolName: "trash",
      accessibilityDescription: nil
    )
    menu.addItem(deleteItem)

    popUp(menu, from: moreButton)
  }

  @objc private func addTextNote() {
    onAddNote?(.text)
  }

  @objc private func addDrawingNote() {
    onAddNote?(.drawing)
  }

  @objc private func undoLastStroke() {
    drawingView.undoLastStroke()
  }

  @objc private func clearDrawing() {
    drawingView.clearDrawing()
  }

  @objc private func deleteNote() {
    onDeleteNote?()
  }

  private func popUp(_ menu: NSMenu, from button: NSButton) {
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: button.bounds.minX, y: button.bounds.minY - 4),
      in: button
    )
  }

  private static func makeToolbarButton(
    symbolName: String,
    accessibilityLabel: String
  ) -> NSButton {
    let button = NSButton(frame: .zero)
    let configuration = NSImage.SymbolConfiguration(
      pointSize: 12,
      weight: .medium
    )
    button.image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: accessibilityLabel
    )?.withSymbolConfiguration(configuration)
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.isBordered = false
    button.bezelStyle = .inline
    button.focusRingType = .none
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = accessibilityLabel
    button.setAccessibilityLabel(accessibilityLabel)
    return button
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
    let radius = min(cornerRadius, min(rect.width / 2, rect.height / 2))
    let cornerControl = radius * 0.552_284_75
    let tailCenterY = resolvedTailCenterY(
      rect: rect,
      radius: radius
    )
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

  private func resolvedTailCenterY(rect: NSRect, radius: CGFloat) -> CGFloat {
    let minimum = rect.minY + radius + tailHalfHeight
    let maximum = rect.maxY - radius - tailHalfHeight
    guard maximum >= minimum else { return rect.midY }
    return min(max(tailCenterY ?? rect.midY, minimum), maximum)
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
