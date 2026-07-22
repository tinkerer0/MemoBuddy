import AppKit
import MemoPetCore

private final class ScratchpadPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ScratchpadPanelController: NSWindowController, NSTextViewDelegate {
  static let panelSize = NSSize(width: 360, height: 220)

  private let store: ScratchpadStore
  private let bubbleView: BubbleBackgroundView
  private var saveTimer: Timer?
  private var previousApplication: NSRunningApplication?

  var isShowingScratchpad: Bool {
    window?.isVisible == true
  }

  init(store: ScratchpadStore) throws {
    self.store = store
    self.bubbleView = BubbleBackgroundView(
      frame: NSRect(origin: .zero, size: Self.panelSize)
    )

    let panel = ScratchpadPanel(
      contentRect: NSRect(origin: .zero, size: Self.panelSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .transient,
      .ignoresCycle,
    ]
    panel.contentView = bubbleView

    super.init(window: panel)

    bubbleView.textView.delegate = self
    bubbleView.textView.string = try store.load()
    bubbleView.textView.onEscape = { [weak self] in
      self?.closeAndRestoreFocus()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    saveTimer?.invalidate()
  }

  func open(characterFrame: NSRect, visibleFrame: NSRect) {
    guard let panel = window else { return }

    let placement = WindowPlacement.bubblePlacement(
      characterFrame: characterFrame,
      bubbleSize: Self.panelSize,
      visibleFrame: visibleFrame
    )
    bubbleView.tailSide = placement.tailSide
    bubbleView.tailCenterY = placement.tailCenterY
    panel.setFrameOrigin(placement.origin)

    let currentApplication = NSWorkspace.shared.frontmostApplication
    if currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previousApplication = currentApplication
    }

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(bubbleView.textView)

    let end = (bubbleView.textView.string as NSString).length
    bubbleView.textView.setSelectedRange(NSRange(location: end, length: 0))
    bubbleView.textView.scrollRangeToVisible(NSRange(location: end, length: 0))
  }

  func closeAndRestoreFocus() {
    flushSave()
    window?.orderOut(nil)

    if let previousApplication, !previousApplication.isTerminated {
      previousApplication.activate(options: [.activateIgnoringOtherApps])
    }
    previousApplication = nil
  }

  func reposition(characterFrame: NSRect, visibleFrame: NSRect) {
    guard isShowingScratchpad else { return }
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: characterFrame,
      bubbleSize: Self.panelSize,
      visibleFrame: visibleFrame
    )
    bubbleView.tailSide = placement.tailSide
    bubbleView.tailCenterY = placement.tailCenterY
    window?.setFrameOrigin(placement.origin)
  }

  func flushSave() {
    saveTimer?.invalidate()
    saveTimer = nil
    saveCurrentText()
  }

  func textDidChange(_ notification: Notification) {
    bubbleView.showError(nil)
    saveTimer?.invalidate()

    let timer = Timer(
      timeInterval: 0.3,
      target: self,
      selector: #selector(saveTimerFired),
      userInfo: nil,
      repeats: false
    )
    RunLoop.main.add(timer, forMode: .common)
    saveTimer = timer
  }

  @objc private func saveTimerFired() {
    saveTimer = nil
    saveCurrentText()
  }

  private func saveCurrentText() {
    do {
      try store.save(bubbleView.textView.string)
      bubbleView.showError(nil)
    } catch {
      bubbleView.showError("Could not save: \(error.localizedDescription)")
    }
  }
}
