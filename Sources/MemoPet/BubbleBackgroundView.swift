import AppKit
import MemoPetCore

final class ScratchpadTextView: NSTextView {
  var onEscape: (() -> Void)?
  var canvasCursor: NSCursor? {
    didSet {
      window?.invalidateCursorRects(for: self)
    }
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, !hasMarkedText() {
      onEscape?()
      return
    }

    let modifiers = event.modifierFlags.intersection([
      .command,
      .shift,
      .option,
      .control,
    ])
    if !hasMarkedText(),
      event.charactersIgnoringModifiers?.lowercased() == "z"
    {
      if modifiers == .command {
        undoManager?.undo()
        return
      }
      if modifiers == [.command, .shift] {
        undoManager?.redo()
        return
      }
    }

    super.keyDown(with: event)
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    if let canvasCursor {
      addCursorRect(visibleRect, cursor: canvasCursor)
    }
  }
}

final class BubbleBackgroundView: NSView, NSPopoverDelegate {
  let textView: ScratchpadTextView
  let drawingView: DrawingNoteView

  var onSelectNote: ((Int) -> Void)?
  var onRenameNote: ((Int, String) -> Void)?
  var onDeleteNote: ((Int) -> Void)?
  var onAddNote: (() -> Void)?
  var onNoteListVisibilityChanged: ((Bool) -> Void)?

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
  private let noteListController = NoteListPopoverController()
  private let toolbarView = NSView(frame: .zero)
  private let toolbarSeparator = NSBox(frame: .zero)
  private let errorLabel = NSTextField(labelWithString: "")
  private let notePickerButton = NSButton(
    title: "1 / 1",
    target: nil,
    action: nil
  )
  private let previousNoteButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "chevron.left",
    accessibilityLabel: "Previous note"
  )
  private let nextNoteButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "chevron.right",
    accessibilityLabel: "Next note"
  )
  private let drawingButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "pencil.tip",
    accessibilityLabel: "Draw on note"
  )
  private let eraserButton = BubbleBackgroundView.makeToolbarButton(
    symbolName: "eraser",
    accessibilityLabel: "Erase drawing"
  )
  private let tailWidth: CGFloat = 18
  private let tailHalfHeight: CGFloat = 14
  private let cornerRadius: CGFloat = 18
  private var activeDrawingTool: DrawingNoteTool = .inactive
  private var notesForList: [MemoNote] = []
  private var selectedNoteIndex = 0
  private lazy var noteListPopover: NSPopover = {
    let popover = NSPopover()
    popover.contentViewController = noteListController
    popover.behavior = .transient
    popover.delegate = self
    return popover
  }()

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

    drawingView.frame = textView.bounds
    drawingView.autoresizingMask = [.width, .height]
    textView.addSubview(drawingView, positioned: .above, relativeTo: nil)

    notePickerButton.image = NSImage(
      systemSymbolName: "list.bullet",
      accessibilityDescription: "Open memo list"
    )
    notePickerButton.imagePosition = .imageLeading
    notePickerButton.font = .monospacedDigitSystemFont(
      ofSize: 11,
      weight: .regular
    )
    notePickerButton.alignment = .center
    notePickerButton.isBordered = false
    notePickerButton.bezelStyle = .inline
    notePickerButton.focusRingType = .none
    notePickerButton.contentTintColor = .secondaryLabelColor
    notePickerButton.toolTip = "Open memo list"
    notePickerButton.setAccessibilityLabel("Open memo list")
    notePickerButton.target = self
    notePickerButton.action = #selector(showNotePicker)

    toolbarSeparator.boxType = .separator

    previousNoteButton.target = self
    previousNoteButton.action = #selector(showPreviousNote)
    nextNoteButton.target = self
    nextNoteButton.action = #selector(showNextNote)
    drawingButton.target = self
    drawingButton.action = #selector(toggleDrawingMode)
    eraserButton.target = self
    eraserButton.action = #selector(toggleEraserMode)
    noteListController.onSelectNote = { [weak self] index in
      self?.onSelectNote?(index)
    }
    noteListController.onRenameNote = { [weak self] index, title in
      self?.onRenameNote?(index, title)
    }
    noteListController.onDeleteNote = { [weak self] index in
      self?.onDeleteNote?(index)
    }
    noteListController.onAddNote = { [weak self] in
      self?.onAddNote?()
      self?.noteListPopover.performClose(nil)
    }

    errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = .systemRed
    errorLabel.lineBreakMode = .byTruncatingTail
    errorLabel.isHidden = true

    toolbarView.addSubview(previousNoteButton)
    toolbarView.addSubview(notePickerButton)
    toolbarView.addSubview(nextNoteButton)
    toolbarView.addSubview(drawingButton)
    toolbarView.addSubview(eraserButton)

    addSubview(scrollView)
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

    previousNoteButton.frame = NSRect(x: 0, y: 1, width: 20, height: 24)
    notePickerButton.frame = NSRect(x: 24, y: 1, width: 70, height: 24)
    nextNoteButton.frame = NSRect(x: 98, y: 1, width: 20, height: 24)
    eraserButton.frame = NSRect(
      x: toolbarView.bounds.maxX - 24,
      y: 1,
      width: 24,
      height: 24
    )
    drawingButton.frame = NSRect(
      x: eraserButton.frame.minX - 28,
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
    drawingView.frame = textView.bounds
    drawingView.migrateLegacyCoordinatesIfPossible()
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

  func display(notes: [MemoNote], index: Int) {
    guard notes.indices.contains(index) else { return }
    let note = notes[index]
    let total = notes.count
    setDrawingTool(.inactive, focusEditor: false)
    textView.string = note.text
    textView.undoManager?.removeAllActions()
    drawingView.display(
      strokes: note.strokes,
      coordinateSpace: note.drawingCoordinateSpace
    )

    selectedNoteIndex = index
    notesForList = notes
    notePickerButton.title = "\(index + 1)/\(total)"
    previousNoteButton.isEnabled = index > 0
    nextNoteButton.isEnabled = index + 1 < total
    notePickerButton.setAccessibilityLabel(
      "Open memo list, \(index + 1) of \(total)"
    )
    if noteListPopover.isShown {
      noteListController.display(
        notes: notes,
        selectedIndex: index
      )
    }
    showError(nil)
  }

  func focusActiveEditor(in window: NSWindow) {
    if activeDrawingTool != .inactive {
      window.makeFirstResponder(drawingView)
    } else {
      window.makeFirstResponder(textView)
      let end = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: end, length: 0))
      textView.scrollRangeToVisible(NSRange(location: end, length: 0))
    }
  }

  var currentText: String {
    textView.string
  }

  var currentStrokes: [MemoStroke] {
    drawingView.strokes
  }

  var currentDrawingCoordinateSpace: MemoDrawingCoordinateSpace? {
    drawingView.coordinateSpace
  }

  func updateCachedNoteTitle(at index: Int, title: String?) {
    guard notesForList.indices.contains(index) else { return }
    notesForList[index].title = title
  }

  @objc private func showPreviousNote() {
    guard selectedNoteIndex > 0 else { return }
    onSelectNote?(selectedNoteIndex - 1)
  }

  @objc private func showNextNote() {
    guard selectedNoteIndex + 1 < notesForList.count else { return }
    onSelectNote?(selectedNoteIndex + 1)
  }

  @objc private func showNotePicker() {
    if noteListPopover.isShown {
      noteListPopover.performClose(nil)
      return
    }

    var currentNotes = notesForList
    if currentNotes.indices.contains(selectedNoteIndex) {
      currentNotes[selectedNoteIndex].text = textView.string
      currentNotes[selectedNoteIndex].strokes = drawingView.strokes
    }
    noteListController.display(
      notes: currentNotes,
      selectedIndex: selectedNoteIndex
    )
    onNoteListVisibilityChanged?(true)
    noteListPopover.show(
      relativeTo: notePickerButton.bounds,
      of: notePickerButton,
      preferredEdge: .minY
    )
  }

  @objc private func toggleDrawingMode() {
    setDrawingTool(
      activeDrawingTool == .draw ? .inactive : .draw,
      focusEditor: true
    )
  }

  @objc private func toggleEraserMode() {
    setDrawingTool(
      activeDrawingTool == .erase ? .inactive : .erase,
      focusEditor: true
    )
  }

  func popoverDidClose(_ notification: Notification) {
    noteListController.dismissDeleteConfirmation()
    onNoteListVisibilityChanged?(false)
  }

  private func setDrawingTool(
    _ tool: DrawingNoteTool,
    focusEditor: Bool
  ) {
    activeDrawingTool = tool
    let usesDrawingTool = tool != .inactive
    textView.isEditable = !usesDrawingTool
    textView.isSelectable = !usesDrawingTool
    drawingView.activeTool = tool
    textView.canvasCursor = drawingView.cursorForActiveTool
    if let window {
      window.invalidateCursorRects(for: textView)
      window.invalidateCursorRects(for: drawingView)
    }
    drawingButton.state = tool == .draw ? .on : .off
    drawingButton.contentTintColor = tool == .draw
      ? .controlAccentColor
      : .secondaryLabelColor
    drawingButton.toolTip = tool == .draw
      ? "Return to text"
      : "Draw on note"
    drawingButton.setAccessibilityLabel(
      tool == .draw ? "Return to text" : "Draw on note"
    )
    eraserButton.state = tool == .erase ? .on : .off
    eraserButton.contentTintColor = tool == .erase
      ? .controlAccentColor
      : .secondaryLabelColor
    eraserButton.toolTip = tool == .erase
      ? "Return to text"
      : "Erase drawing"
    eraserButton.setAccessibilityLabel(
      tool == .erase ? "Return to text" : "Erase drawing"
    )

    if focusEditor, let window {
      focusActiveEditor(in: window)
    }
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
