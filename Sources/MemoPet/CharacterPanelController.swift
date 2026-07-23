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

  private(set) var selectedCharacter: CharacterChoice = .memoWriter
  private(set) var customAsset: CharacterAsset?
  private var systemSuspended = false
  private var shown = false

  var currentFrame: NSRect {
    window?.frame ?? NSRect(origin: .zero, size: NSSize(width: size, height: size))
  }

  init(size: CGFloat = CharacterPanelController.defaultSize) {
    let initialSize = min(max(size.isFinite ? size : Self.defaultSize, 40), 160)
    self.size = initialSize
    let windowSize = NSSize(width: initialSize, height: initialSize)
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

  func setCharacter(
    _ choice: CharacterChoice,
    customAsset: CharacterAsset? = nil
  ) throws {
    switch choice {
    case .classic:
      characterView.setImage(nil, animated: false)

    case .memoWriter, .orbitingPlanet:
      guard let resourceName = choice.bundledResourceName,
        let url = bundledResourceURL(named: resourceName),
        let image = NSImage(contentsOf: url)
      else {
        throw CharacterImageValidationError.unreadable
      }
      characterView.setImage(image, animated: true)

    case .custom:
      guard let customAsset,
        let image = NSImage(contentsOf: customAsset.url)
      else {
        throw CharacterImageValidationError.unreadable
      }
      characterView.setImage(image, animated: customAsset.metadata.isAnimated)
    }

    selectedCharacter = choice
    self.customAsset = choice == .custom ? customAsset : nil
    updatePlayback()
  }

  func setOrigin(_ origin: NSPoint) {
    window?.setFrameOrigin(origin)
  }

  func setSize(_ newSize: CGFloat) {
    guard let window else { return }
    let finiteSize = newSize.isFinite ? newSize : Self.defaultSize
    let clampedSize = min(max(finiteSize, 40), 160)
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

  private func bundledResourceURL(named name: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: "gif")
      ?? Bundle.module.url(forResource: name, withExtension: "gif")
  }
}
