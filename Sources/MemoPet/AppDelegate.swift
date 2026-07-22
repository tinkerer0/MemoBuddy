import AppKit
import MemoPetCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = AppSettings()

  private var applicationSupportURL: URL?
  private var characterStore: CharacterStore?
  private var characterController: CharacterPanelController?
  private var scratchpadController: ScratchpadPanelController?
  private var statusMenuController: StatusMenuController?
  private var animationLifecycle: AnimationLifecycle?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      try configureApplication()
    } catch {
      showFatalError(error)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    scratchpadController?.flushSave()
  }

  private func configureApplication() throws {
    let applicationSupportURL = try AppDirectories.applicationSupportURL()
    let characterStore = try CharacterStore(directoryURL: applicationSupportURL)
    let scratchpadStore = try ScratchpadStore(directoryURL: applicationSupportURL)
    let characterController = CharacterPanelController(size: settings.characterSize)
    let scratchpadController = try ScratchpadPanelController(store: scratchpadStore)
    let statusMenuController = StatusMenuController()
    let animationLifecycle = AnimationLifecycle()

    self.applicationSupportURL = applicationSupportURL
    self.characterStore = characterStore
    self.characterController = characterController
    self.scratchpadController = scratchpadController
    self.statusMenuController = statusMenuController
    self.animationLifecycle = animationLifecycle

    configureCharacterCallbacks()
    configureStatusMenuCallbacks()

    animationLifecycle.onSuspensionChanged = { [weak characterController] suspended in
      characterController?.setSystemSuspended(suspended)
    }

    let origin = initialCharacterOrigin()
    characterController.setOrigin(origin)

    do {
      try characterController.setAsset(characterStore.load())
    } catch {
      try? characterStore.reset()
      try characterController.setAsset(nil)
      showError(
        title: "Could not load the saved character",
        error: error
      )
    }

    if settings.isCharacterVisible {
      characterController.show()
    } else {
      characterController.hide()
    }
    rebuildMenu()
  }

  private func configureCharacterCallbacks() {
    characterController?.characterView.onClick = { [weak self] in
      self?.toggleScratchpad()
    }
    characterController?.characterView.onMoveEnded = { [weak self] origin in
      self?.finishCharacterMove(origin: origin)
    }
    characterController?.characterView.onImageDropped = { [weak self] url in
      self?.importCharacter(from: url)
    }
    characterController?.characterView.contextMenuProvider = { [weak self] in
      self?.makeCharacterContextMenu()
    }
  }

  private func configureStatusMenuCallbacks() {
    statusMenuController?.onToggleScratchpad = { [weak self] in
      self?.toggleScratchpad()
    }
    statusMenuController?.onChooseCharacter = { [weak self] in
      self?.chooseCharacter()
    }
    statusMenuController?.onResetCharacter = { [weak self] in
      self?.resetCharacter()
    }
    statusMenuController?.onCenterCharacter = { [weak self] in
      self?.centerCharacter()
    }
    statusMenuController?.onToggleCharacter = { [weak self] in
      self?.toggleCharacterVisibility()
    }
    statusMenuController?.onSetCharacterSize = { [weak self] size in
      self?.setCharacterSize(size)
    }
    statusMenuController?.onOpenDataFolder = { [weak self] in
      self?.openDataFolder()
    }
    statusMenuController?.onQuit = {
      NSApp.terminate(nil)
    }
  }

  private func toggleScratchpad() {
    guard let characterController, let scratchpadController else { return }

    if scratchpadController.isShowingScratchpad {
      scratchpadController.closeAndRestoreFocus()
    } else {
      let characterFrame = characterController.currentFrame
      scratchpadController.open(
        characterFrame: characterFrame,
        visibleFrame: screen(containing: characterFrame).visibleFrame
      )
    }
    rebuildMenu()
  }

  private func chooseCharacter() {
    let panel = NSOpenPanel()
    panel.title = "Choose an animated GIF"
    panel.prompt = "Use Character"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.gif, .png, .jpeg, .webP]

    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    importCharacter(from: url)
  }

  private func importCharacter(from sourceURL: URL) {
    guard let characterStore, let characterController else { return }

    let accessed = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let asset = try characterStore.importImage(from: sourceURL)
      try characterController.setAsset(asset)

      if !settings.isCharacterVisible {
        settings.isCharacterVisible = true
        characterController.show()
      }
      rebuildMenu()
    } catch {
      showError(title: "Could not use that character", error: error)
    }
  }

  private func resetCharacter() {
    guard let characterStore, let characterController else { return }
    do {
      try characterStore.reset()
      try characterController.setAsset(nil)
      rebuildMenu()
    } catch {
      showError(title: "Could not reset the character", error: error)
    }
  }

  private func centerCharacter() {
    guard let characterController else { return }
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let visibleFrame = screen.visibleFrame
    let size = characterController.currentFrame.size
    let origin = NSPoint(
      x: visibleFrame.midX - (size.width / 2),
      y: visibleFrame.midY - (size.height / 2)
    )
    characterController.setOrigin(origin)
    settings.characterOrigin = origin
    repositionScratchpad()
  }

  private func toggleCharacterVisibility() {
    guard let characterController else { return }
    settings.isCharacterVisible.toggle()

    if settings.isCharacterVisible {
      characterController.show()
    } else {
      scratchpadController?.closeAndRestoreFocus()
      characterController.hide()
    }
    rebuildMenu()
  }

  private func setCharacterSize(_ size: CGFloat) {
    guard let characterController else { return }
    characterController.setSize(size)
    settings.characterSize = characterController.size

    let frame = characterController.currentFrame
    let visibleFrame = screen(containing: frame).visibleFrame
    let clampedOrigin = WindowPlacement.clampedOrigin(
      frame.origin,
      windowSize: frame.size,
      visibleFrame: visibleFrame
    )
    characterController.setOrigin(clampedOrigin)
    settings.characterOrigin = clampedOrigin
    repositionScratchpad()
    rebuildMenu()
  }

  private func finishCharacterMove(origin: NSPoint) {
    guard let characterController else { return }
    let size = characterController.currentFrame.size
    let frame = NSRect(origin: origin, size: size)
    let visibleFrame = screen(containing: frame).visibleFrame
    let clampedOrigin = WindowPlacement.clampedOrigin(
      origin,
      windowSize: size,
      visibleFrame: visibleFrame
    )
    characterController.setOrigin(clampedOrigin)
    settings.characterOrigin = clampedOrigin
    repositionScratchpad()
  }

  private func repositionScratchpad() {
    guard let characterController, let scratchpadController else { return }
    let characterFrame = characterController.currentFrame
    scratchpadController.reposition(
      characterFrame: characterFrame,
      visibleFrame: screen(containing: characterFrame).visibleFrame
    )
  }

  private func openDataFolder() {
    guard let applicationSupportURL else { return }
    NSWorkspace.shared.open(applicationSupportURL)
  }

  private func initialCharacterOrigin() -> NSPoint {
    let side = settings.characterSize
    let size = NSSize(width: side, height: side)
    let fallbackScreen = NSScreen.main ?? NSScreen.screens[0]

    guard let savedOrigin = settings.characterOrigin else {
      return NSPoint(
        x: fallbackScreen.visibleFrame.maxX - size.width - 24,
        y: fallbackScreen.visibleFrame.minY + 24
      )
    }

    let savedFrame = NSRect(origin: savedOrigin, size: size)
    let targetScreen = screen(containing: savedFrame)
    return WindowPlacement.clampedOrigin(
      savedOrigin,
      windowSize: size,
      visibleFrame: targetScreen.visibleFrame
    )
  }

  private func screen(containing frame: NSRect) -> NSScreen {
    NSScreen.screens.max { lhs, rhs in
      intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
    } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
  }

  private func rebuildMenu() {
    statusMenuController?.rebuild(state: currentMenuState())
  }

  private func makeCharacterContextMenu() -> NSMenu? {
    statusMenuController?.makeCharacterMenu(state: currentMenuState())
  }

  private func currentMenuState() -> StatusMenuState {
    StatusMenuState(
      characterVisible: settings.isCharacterVisible,
      hasCustomCharacter: characterController?.asset != nil,
      scratchpadVisible: scratchpadController?.isShowingScratchpad == true,
      characterSize: characterController?.size ?? settings.characterSize
    )
  }

  private func showError(title: String, error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }

  private func showFatalError(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "MemoPet could not start"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "Quit")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    NSApp.terminate(nil)
  }
}
