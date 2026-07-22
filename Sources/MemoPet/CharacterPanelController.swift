import AppKit
import MemoPetCore

private final class CharacterPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class CharacterPanelController: NSWindowController {
  static let defaultSize: CGFloat = 80

  let characterView: CharacterView

  private(set) var size: CGFloat

  private(set) var asset: CharacterAsset?
  private var systemSuspended = false
  private var shown = false

  var currentFrame: NSRect {
    window?.frame ?? NSRect(origin: .zero, size: NSSize(width: size, height: size))
  }

  init(size: CGFloat = CharacterPanelController.defaultSize) {
    self.size = size
    let windowSize = NSSize(width: size, height: size)
    characterView = CharacterView(
      frame: NSRect(origin: .zero, size: windowSize)
    )

    let panel = CharacterPanel(
      contentRect: NSRect(origin: .zero, size: windowSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]
    panel.acceptsMouseMovedEvents = true
    panel.contentView = characterView

    super.init(window: panel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func setAsset(_ asset: CharacterAsset?) throws {
    self.asset = asset
    guard let asset else {
      let defaultURL = Bundle.main.url(
        forResource: "default-character",
        withExtension: "gif"
      ) ?? Bundle.module.url(
        forResource: "default-character",
        withExtension: "gif"
      )
      if let defaultURL, let defaultImage = NSImage(contentsOf: defaultURL) {
        characterView.setImage(defaultImage, animated: true)
        updatePlayback()
      } else {
        characterView.setImage(nil, animated: false)
      }
      return
    }

    guard let image = NSImage(contentsOf: asset.url) else {
      throw CharacterImageValidationError.unreadable
    }
    characterView.setImage(image, animated: asset.metadata.isAnimated)
    updatePlayback()
  }

  func setOrigin(_ origin: NSPoint) {
    window?.setFrameOrigin(origin)
  }

  func setSize(_ newSize: CGFloat) {
    guard let window else { return }
    let clampedSize = min(max(newSize, 40), 160)
    let oldFrame = window.frame
    let center = NSPoint(x: oldFrame.midX, y: oldFrame.midY)
    let newFrame = NSRect(
      x: center.x - (clampedSize / 2),
      y: center.y - (clampedSize / 2),
      width: clampedSize,
      height: clampedSize
    )
    size = clampedSize
    window.setFrame(newFrame, display: true)
    characterView.frame = NSRect(origin: .zero, size: newFrame.size)
  }

  func show() {
    shown = true
    showWindow(nil)
    window?.orderFrontRegardless()
    updatePlayback()
  }

  func hide() {
    shown = false
    updatePlayback()
    window?.orderOut(nil)
  }

  func setSystemSuspended(_ suspended: Bool) {
    systemSuspended = suspended
    updatePlayback()
  }

  private func updatePlayback() {
    characterView.setPlaybackEnabled(
      shown && !systemSuspended
    )
  }
}
