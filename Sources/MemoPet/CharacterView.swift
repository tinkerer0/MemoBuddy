import AppKit
import MemoPetCore

final class CharacterView: NSView {
  var onClick: (() -> Void)?
  var onMove: ((NSPoint) -> Void)?
  var onMoveEnded: ((NSPoint) -> Void)?
  var onImageDropped: ((URL) -> Void)?
  var contextMenuProvider: (() -> NSMenu?)?

  private let imageView = NSImageView()
  private var dragStartMouseLocation: NSPoint?
  private var dragStartWindowOrigin: NSPoint?
  private var didDrag = false
  private var isAnimatedImage = false
  private var playbackEnabled = true

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    imageView.frame = bounds
    imageView.autoresizingMask = [.width, .height]
    imageView.imageAlignment = .alignCenter
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true
    addSubview(imageView)

    registerForDraggedTypes([.fileURL])
    setAccessibilityRole(.button)
    setAccessibilityLabel("MemoPet character")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  func setImage(_ image: NSImage?, animated: Bool) {
    isAnimatedImage = animated
    imageView.image = image

    if animated {
      for case let representation as NSBitmapImageRep in image?.representations ?? [] {
        representation.setProperty(.loopCount, withValue: 0)
      }
    }

    updatePlayback()
    needsDisplay = true
  }

  func setPlaybackEnabled(_ enabled: Bool) {
    playbackEnabled = enabled
    updatePlayback()
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard imageView.image == nil else { return }

    let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let backgroundColor: NSColor = isDarkMode ? .white : .black
    let foregroundColor: NSColor = isDarkMode ? .black : .white
    let circleRect = bounds.insetBy(dx: 5, dy: 5)
    backgroundColor.setFill()
    NSBezierPath(ovalIn: circleRect).fill()

    let iconWidth = min(bounds.width, bounds.height) * 0.28
    let iconHeight = iconWidth * 1.18
    let iconRect = NSRect(
      x: bounds.midX - (iconWidth / 2),
      y: bounds.midY - (iconHeight / 2),
      width: iconWidth,
      height: iconHeight
    )
    let outline = NSBezierPath(roundedRect: iconRect, xRadius: 2.5, yRadius: 2.5)
    outline.lineWidth = 2
    foregroundColor.setStroke()
    outline.stroke()

    for offset in [0.68, 0.5, 0.32] {
      let line = NSBezierPath()
      let y = iconRect.minY + (iconRect.height * offset)
      line.move(to: NSPoint(x: iconRect.minX + 4, y: y))
      line.line(to: NSPoint(x: iconRect.maxX - 4, y: y))
      line.lineWidth = 1.5
      line.stroke()
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func mouseDown(with event: NSEvent) {
    dragStartMouseLocation = NSEvent.mouseLocation
    dragStartWindowOrigin = window?.frame.origin
    didDrag = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window,
      let dragStartMouseLocation,
      let dragStartWindowOrigin
    else {
      return
    }

    let currentLocation = NSEvent.mouseLocation
    let deltaX = currentLocation.x - dragStartMouseLocation.x
    let deltaY = currentLocation.y - dragStartMouseLocation.y
    let distance = hypot(deltaX, deltaY)
    guard didDrag || distance >= 5 else { return }

    didDrag = true
    let newOrigin = NSPoint(
      x: dragStartWindowOrigin.x + deltaX,
      y: dragStartWindowOrigin.y + deltaY
    )
    window.setFrameOrigin(newOrigin)
    onMove?(newOrigin)
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      dragStartMouseLocation = nil
      dragStartWindowOrigin = nil
      didDrag = false
    }

    if didDrag {
      if let origin = window?.frame.origin {
        onMoveEnded?(origin)
      }
    } else {
      onClick?()
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let menu = contextMenuProvider?() else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    droppedFileURL(from: sender) == nil ? [] : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let url = droppedFileURL(from: sender) else { return false }
    onImageDropped?(url)
    return true
  }

  private func droppedFileURL(from sender: NSDraggingInfo) -> URL? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    return sender.draggingPasteboard
      .readObjects(forClasses: [NSURL.self], options: options)?
      .first as? URL
  }

  private func updatePlayback() {
    imageView.animates = isAnimatedImage && playbackEnabled
  }
}
