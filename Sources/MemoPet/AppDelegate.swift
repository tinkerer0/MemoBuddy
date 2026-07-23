import AppKit
import MemoPetCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let settings = AppSettings()
  private let updateChecker = GitHubReleaseChecker()

  private var applicationSupportURL: URL?
  private var characterStore: CharacterStore?
  private var characterController: CharacterPanelController?
  private var scratchpadController: ScratchpadPanelController?
  private var statusMenuController: StatusMenuController?
  private var animationLifecycle: AnimationLifecycle?
  private var selectedCharacter: CharacterChoice = .memoWriter
  private var customCharacterAsset: CharacterAsset?
  private var isCheckingForUpdates = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      try configureApplication()
    } catch {
      showFatalError(error)
    }
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    guard let scratchpadController else {
      return .terminateNow
    }
    guard !scratchpadController.flushSave() else { return .terminateNow }

    if let error = scratchpadController.lastSaveError {
      showError(
        title: "MemoPet could not save your notes",
        error: error
      )
    }
    return .terminateCancel
  }

  private func configureApplication() throws {
    let applicationSupportURL = try AppDirectories.applicationSupportURL()
    let characterStore = try CharacterStore(directoryURL: applicationSupportURL)
    let scratchpadStore = try MemoNotebookStore(directoryURL: applicationSupportURL)
    let characterController = CharacterPanelController(size: settings.characterSize)
    let scratchpadController = try ScratchpadPanelController(
      store: scratchpadStore,
      size: settings.memoSize
    )
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersDidChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
    scratchpadController.onSizeChanged = { [weak self] size in
      self?.settings.memoSize = size
    }
    scratchpadController.onVisibilityChanged = { [weak self] _ in
      self?.rebuildMenu()
    }

    animationLifecycle.onSuspensionChanged = { [weak characterController] suspended in
      characterController?.setSystemSuspended(suspended)
    }

    let origin = initialCharacterOrigin()
    characterController.setOrigin(origin)

    let customCharacterAsset: CharacterAsset?
    do {
      customCharacterAsset = try characterStore.load()
    } catch {
      customCharacterAsset = nil
      showError(
        title: "Could not load the saved character",
        error: error
      )
    }

    let requestedCharacter = settings.characterChoice
      ?? (customCharacterAsset == nil ? .memoWriter : .custom)
    let initialCharacter: CharacterChoice = requestedCharacter == .custom
      && customCharacterAsset == nil
      ? .memoWriter
      : requestedCharacter
    try characterController.setCharacter(
      initialCharacter,
      customAsset: customCharacterAsset
    )
    self.customCharacterAsset = customCharacterAsset
    selectedCharacter = initialCharacter
    settings.characterChoice = initialCharacter

    if settings.isCharacterVisible {
      characterController.show()
    } else {
      characterController.hide()
    }
    rebuildMenu()
    if let recoveryNotice = scratchpadStore.recoveryNotice {
      DispatchQueue.main.async { [weak self] in
        self?.showMessage(
          title: "MemoPet recovered your notes",
          message: recoveryNotice
        )
      }
    }
    checkForUpdatesAutomaticallyIfNeeded()
  }

  private func configureCharacterCallbacks() {
    characterController?.characterView.onClick = { [weak self] in
      self?.toggleScratchpad()
    }
    characterController?.characterView.onMove = { [weak self] origin in
      self?.moveCharacter(origin: origin)
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
    statusMenuController?.onSelectCharacter = { [weak self] choice in
      self?.selectCharacter(choice)
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
    statusMenuController?.onDeleteCurrentNote = { [weak self] in
      self?.scratchpadController?.deleteSelectedNote()
    }
    statusMenuController?.onOpenDataFolder = { [weak self] in
      self?.openDataFolder()
    }
    statusMenuController?.onCheckForUpdates = { [weak self] in
      self?.checkForUpdates(manual: true)
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
    panel.title = "Choose a custom character"
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
      try characterController.setCharacter(.custom, customAsset: asset)
      customCharacterAsset = asset
      selectedCharacter = .custom
      settings.characterChoice = .custom

      if !settings.isCharacterVisible {
        settings.isCharacterVisible = true
        characterController.show()
      }
      rebuildMenu()
    } catch {
      showError(title: "Could not use that character", error: error)
    }
  }

  private func selectCharacter(_ choice: CharacterChoice) {
    guard choice != .custom,
      choice != selectedCharacter,
      let characterController
    else {
      return
    }

    do {
      try characterController.setCharacter(choice)
      selectedCharacter = choice
      settings.characterChoice = choice

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
      customCharacterAsset = nil
      if selectedCharacter == .custom {
        try characterController.setCharacter(.memoWriter)
        selectedCharacter = .memoWriter
        settings.characterChoice = .memoWriter
      }
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

    if settings.isCharacterVisible {
      guard scratchpadController?.closeAndRestoreFocus() != false else {
        return
      }
      settings.isCharacterVisible = false
      characterController.hide()
    } else {
      settings.isCharacterVisible = true
      characterController.show()
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

  private func moveCharacter(origin: NSPoint) {
    guard let characterController, let scratchpadController else { return }
    let frame = NSRect(
      origin: origin,
      size: characterController.currentFrame.size
    )
    scratchpadController.reposition(
      characterFrame: frame,
      visibleFrame: screen(containing: frame).visibleFrame
    )
  }

  @objc private func screenParametersDidChange() {
    guard let characterController else { return }
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

  private func checkForUpdatesAutomaticallyIfNeeded() {
    guard UpdateCheckSchedule.shouldCheck(
      lastCheck: settings.lastUpdateCheckDate
    ) else { return }
    checkForUpdates(manual: false)
  }

  private func checkForUpdates(manual: Bool) {
    guard !isCheckingForUpdates else {
      if manual {
        showMessage(
          title: "Already checking for updates",
          message: "MemoPet is waiting for GitHub to respond."
        )
      }
      return
    }
    guard let currentVersion = currentAppVersion else {
      if manual {
        showMessage(
          title: "Could not check for updates",
          message: "This build does not include version information."
        )
      }
      return
    }

    isCheckingForUpdates = true
    settings.lastUpdateCheckDate = Date()
    updateChecker.check(currentVersion: currentVersion) { [weak self] result in
      DispatchQueue.main.async {
        self?.handleUpdateCheckResult(
          result,
          currentVersion: currentVersion,
          manual: manual
        )
      }
    }
  }

  private func handleUpdateCheckResult(
    _ result: Result<UpdateCheckResult, Error>,
    currentVersion: String,
    manual: Bool
  ) {
    isCheckingForUpdates = false

    switch result {
    case let .failure(error):
      if manual {
        showError(title: "Could not check for updates", error: error)
      }

    case .success(.upToDate):
      if manual {
        showMessage(
          title: "MemoPet is up to date",
          message: "You are using MemoPet \(currentVersion)."
        )
      }

    case let .success(.updateAvailable(update)):
      if !manual, settings.lastNotifiedUpdateVersion == update.version {
        return
      }
      settings.lastNotifiedUpdateVersion = update.version
      showAvailableUpdate(update, currentVersion: currentVersion)
    }
  }

  private var currentAppVersion: String? {
    guard let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String,
      AppVersion(version) != nil
    else {
      return nil
    }
    return version
  }

  private func showAvailableUpdate(
    _ update: AvailableUpdate,
    currentVersion: String
  ) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "MemoPet \(update.version) is available"
    alert.informativeText = "You are using \(currentVersion). View the release to download the update."
    alert.addButton(withTitle: "View Release")
    alert.addButton(withTitle: "Later")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(update.releaseURL)
    }
  }

  private func showMessage(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
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
    let screens = NSScreen.screens
    if let intersecting = screens.max(by: { lhs, rhs in
      intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
    }), intersectionArea(intersecting.frame, frame) > 0 {
      return intersecting
    }

    let center = NSPoint(x: frame.midX, y: frame.midY)
    return screens.min { lhs, rhs in
      squaredDistance(from: center, to: lhs.frame)
        < squaredDistance(from: center, to: rhs.frame)
    } ?? NSScreen.main ?? screens[0]
  }

  private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
  }

  private func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
    let dx = max(max(rect.minX - point.x, 0), point.x - rect.maxX)
    let dy = max(max(rect.minY - point.y, 0), point.y - rect.maxY)
    return (dx * dx) + (dy * dy)
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
      hasCustomCharacter: characterStore?.hasStoredImage == true,
      selectedCharacter: selectedCharacter,
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
