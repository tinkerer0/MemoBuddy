import AppKit
import MemoPetCore

private final class ScratchpadPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ScratchpadPanelController:
  NSWindowController,
  NSTextViewDelegate,
  NSWindowDelegate
{
  static let defaultSize = NSSize(width: 360, height: 220)
  static let minimumSize = NSSize(width: 300, height: 180)
  static let maximumSize = NSSize(width: 720, height: 560)

  private let store: MemoNotebookStore
  private let bubbleView: BubbleBackgroundView
  private var notebook: MemoNotebook
  private var saveTimer: Timer?
  private var previousApplication: NSRunningApplication?
  private var isDisplayingNote = false
  private var isApplyingPlacement = false
  private var isClosing = false
  private var isPresentingNoteList = false
  private var lastCharacterFrame: NSRect?
  private var lastVisibleFrame: NSRect?

  var onSizeChanged: ((NSSize) -> Void)?
  var onVisibilityChanged: ((Bool) -> Void)?
  private(set) var lastSaveError: Error?

  var isShowingScratchpad: Bool {
    window?.isVisible == true
  }

  init(
    store: MemoNotebookStore,
    size: NSSize = ScratchpadPanelController.defaultSize
  ) throws {
    let initialSize = Self.clampedSize(size)
    self.store = store
    self.notebook = try store.load()
    self.bubbleView = BubbleBackgroundView(
      frame: NSRect(origin: .zero, size: initialSize)
    )

    let panel = ScratchpadPanel(
      contentRect: NSRect(origin: .zero, size: initialSize),
      styleMask: [.borderless, .resizable],
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
    panel.minSize = Self.minimumSize
    panel.maxSize = Self.maximumSize
    panel.contentMinSize = Self.minimumSize
    panel.contentMaxSize = Self.maximumSize
    panel.contentView = bubbleView

    super.init(window: panel)
    panel.delegate = self

    bubbleView.textView.delegate = self
    bubbleView.textView.onEscape = { [weak self] in
      self?.closeAndRestoreFocus()
    }
    bubbleView.drawingView.onEscape = { [weak self] in
      self?.closeAndRestoreFocus()
    }
    bubbleView.drawingView.onChange = { [weak self] strokes in
      self?.drawingDidChange(strokes)
    }
    bubbleView.drawingView.onCoordinateMigration = { [weak self] strokes in
      self?.drawingCoordinatesDidMigrate(strokes)
    }
    bubbleView.onSelectNote = { [weak self] index in
      self?.selectNote(at: index)
    }
    bubbleView.onRenameNote = { [weak self] index, title in
      self?.renameNote(at: index, title: title)
    }
    bubbleView.onAddNote = { [weak self] in
      self?.addNote()
    }
    bubbleView.onDeleteNote = { [weak self] index in
      self?.deleteNote(at: index)
    }
    bubbleView.onNoteListVisibilityChanged = { [weak self] isVisible in
      self?.noteListVisibilityDidChange(isVisible)
    }

    displaySelectedNote(focusEditor: false)
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

    lastCharacterFrame = characterFrame
    lastVisibleFrame = visibleFrame
    applyPlacement(
      characterFrame: characterFrame,
      visibleFrame: visibleFrame,
      panel: panel
    )

    let currentApplication = NSWorkspace.shared.frontmostApplication
    if currentApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previousApplication = currentApplication
    }

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    bubbleView.focusActiveEditor(in: panel)
    onVisibilityChanged?(true)
  }

  @discardableResult
  func closeAndRestoreFocus() -> Bool {
    close(restorePreviousApplication: true)
  }

  func reposition(characterFrame: NSRect, visibleFrame: NSRect) {
    lastCharacterFrame = characterFrame
    lastVisibleFrame = visibleFrame
    guard isShowingScratchpad else { return }
    guard let panel = window else { return }
    applyPlacement(
      characterFrame: characterFrame,
      visibleFrame: visibleFrame,
      panel: panel
    )
  }

  @discardableResult
  func flushSave() -> Bool {
    saveTimer?.invalidate()
    saveTimer = nil
    syncVisibleEditorIntoNotebook()
    return saveNotebook()
  }

  func textDidChange(_ notification: Notification) {
    guard !isDisplayingNote else { return }
    updateSelectedText(bubbleView.currentText)
    scheduleSave()
  }

  @objc private func saveTimerFired() {
    saveTimer = nil
    syncVisibleEditorIntoNotebook()
    saveNotebook()
  }

  private func scheduleSave() {
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

  private func drawingDidChange(_ strokes: [MemoStroke]) {
    guard !isDisplayingNote else { return }
    let index = notebook.selectedIndex
    notebook.notes[index].strokes = strokes
    notebook.notes[index].drawingCoordinateSpace = .absolutePoints
    scheduleSave()
  }

  private func drawingCoordinatesDidMigrate(_ strokes: [MemoStroke]) {
    let index = notebook.selectedIndex
    notebook.notes[index].strokes = strokes
    notebook.notes[index].drawingCoordinateSpace = .absolutePoints
    if !isDisplayingNote {
      scheduleSave()
    }
  }

  private func selectNote(at index: Int) {
    guard notebook.notes.indices.contains(index),
      index != notebook.selectedIndex
    else {
      return
    }

    commitVisibleEditor()
    notebook.select(at: index)
    displaySelectedNote(focusEditor: !isPresentingNoteList)
    saveNotebook()
  }

  private func addNote() {
    commitVisibleEditor()
    notebook.addNote()
    displaySelectedNote(focusEditor: true)
    saveNotebook()
  }

  private func renameNote(at index: Int, title: String) {
    guard notebook.notes.indices.contains(index) else { return }
    let trimmedTitle = title.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let normalizedTitle = trimmedTitle.isEmpty
      ? nil
      : String(trimmedTitle.prefix(80))
    notebook.notes[index].title = normalizedTitle
    bubbleView.updateCachedNoteTitle(
      at: index,
      title: normalizedTitle
    )
    scheduleSave()
  }

  private func deleteNote(at index: Int) {
    guard notebook.notes.indices.contains(index) else { return }
    commitVisibleEditor()

    guard notebook.notes.count > 1 || !notebook.notes[index].isEmpty else {
      return
    }
    notebook.deleteNote(at: index)
    displaySelectedNote(focusEditor: true)
    saveNotebook()
  }

  private func noteListVisibilityDidChange(_ isVisible: Bool) {
    isPresentingNoteList = isVisible
    guard !isVisible else { return }

    DispatchQueue.main.async { [weak self] in
      guard let self,
        !self.isPresentingNoteList,
        !self.isClosing,
        let panel = self.window,
        panel.isVisible,
        !panel.isKeyWindow
      else {
        return
      }
      self.close(restorePreviousApplication: false)
    }
  }

  private func commitVisibleEditor() {
    saveTimer?.invalidate()
    saveTimer = nil
    syncVisibleEditorIntoNotebook()
  }

  private func syncVisibleEditorIntoNotebook() {
    let index = notebook.selectedIndex
    notebook.notes[index].text = bubbleView.currentText
    notebook.notes[index].strokes = bubbleView.currentStrokes
    notebook.notes[index].drawingCoordinateSpace =
      bubbleView.currentDrawingCoordinateSpace
  }

  private func updateSelectedText(_ text: String) {
    let index = notebook.selectedIndex
    notebook.notes[index].text = text
  }

  private func displaySelectedNote(focusEditor: Bool) {
    isDisplayingNote = true
    bubbleView.display(
      notes: notebook.notes,
      index: notebook.selectedIndex
    )
    isDisplayingNote = false

    if focusEditor, let window, window.isVisible {
      bubbleView.focusActiveEditor(in: window)
    }
  }

  @discardableResult
  private func saveNotebook() -> Bool {
    do {
      try store.save(notebook)
      lastSaveError = nil
      bubbleView.showError(nil)
      return true
    } catch {
      lastSaveError = error
      bubbleView.showError("Could not save: \(error.localizedDescription)")
      return false
    }
  }

  func windowDidResize(_ notification: Notification) {
    guard !isApplyingPlacement,
      let panel = notification.object as? NSWindow,
      let characterFrame = lastCharacterFrame
    else {
      return
    }

    bubbleView.tailSide = characterFrame.midX <= panel.frame.midX
      ? .left
      : .right
    bubbleView.tailCenterY = characterFrame.midY - panel.frame.minY
    bubbleView.needsLayout = true
    bubbleView.needsDisplay = true
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let panel = notification.object as? NSWindow else { return }

    if let characterFrame = lastCharacterFrame,
      let visibleFrame = lastVisibleFrame
    {
      applyPlacement(
        characterFrame: characterFrame,
        visibleFrame: visibleFrame,
        panel: panel
      )
    }
    onSizeChanged?(panel.frame.size)
  }

  func windowDidResignKey(_ notification: Notification) {
    guard !isClosing,
      !isPresentingNoteList,
      let panel = notification.object as? NSWindow,
      panel.isVisible
    else {
      return
    }

    close(restorePreviousApplication: false)
  }

  @discardableResult
  private func close(restorePreviousApplication: Bool) -> Bool {
    guard !isClosing else { return true }
    guard flushSave() else {
      NSApp.activate(ignoringOtherApps: true)
      window?.makeKeyAndOrderFront(nil)
      return false
    }

    isClosing = true
    window?.orderOut(nil)
    isClosing = false
    onVisibilityChanged?(false)

    let applicationToRestore = previousApplication
    previousApplication = nil
    if restorePreviousApplication,
      let applicationToRestore,
      !applicationToRestore.isTerminated
    {
      applicationToRestore.activate(options: [.activateIgnoringOtherApps])
    }
    return true
  }

  private func applyPlacement(
    characterFrame: NSRect,
    visibleFrame: NSRect,
    panel: NSWindow
  ) {
    let placement = WindowPlacement.bubblePlacement(
      characterFrame: characterFrame,
      bubbleSize: panel.frame.size,
      visibleFrame: visibleFrame
    )
    isApplyingPlacement = true
    bubbleView.tailSide = placement.tailSide
    bubbleView.tailCenterY = placement.tailCenterY
    panel.setFrameOrigin(placement.origin)
    isApplyingPlacement = false
  }

  private static func clampedSize(_ size: NSSize) -> NSSize {
    let width = size.width.isFinite ? size.width : defaultSize.width
    let height = size.height.isFinite ? size.height : defaultSize.height
    return NSSize(
      width: min(max(width, minimumSize.width), maximumSize.width),
      height: min(max(height, minimumSize.height), maximumSize.height)
    )
  }
}
