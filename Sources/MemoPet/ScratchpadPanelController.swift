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
  private var lastCharacterFrame: NSRect?
  private var lastVisibleFrame: NSRect?

  var onSizeChanged: ((NSSize) -> Void)?
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
    bubbleView.onPreviousNote = { [weak self] in
      self?.showPreviousNote()
    }
    bubbleView.onNextNote = { [weak self] in
      self?.showNextNote()
    }
    bubbleView.onAddNote = { [weak self] in
      self?.addNote()
    }
    bubbleView.onDeleteNote = { [weak self] in
      self?.deleteSelectedNote()
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
  }

  @discardableResult
  func closeAndRestoreFocus() -> Bool {
    guard flushSave() else { return false }
    window?.orderOut(nil)

    if let previousApplication, !previousApplication.isTerminated {
      previousApplication.activate(options: [.activateIgnoringOtherApps])
    }
    previousApplication = nil
    return true
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
    scheduleSave()
  }

  private func showPreviousNote() {
    selectNote(at: notebook.selectedIndex - 1)
  }

  private func showNextNote() {
    selectNote(at: notebook.selectedIndex + 1)
  }

  private func selectNote(at index: Int) {
    guard notebook.notes.indices.contains(index),
      index != notebook.selectedIndex
    else {
      return
    }

    commitVisibleEditor()
    notebook.select(at: index)
    displaySelectedNote(focusEditor: true)
    saveNotebook()
  }

  private func addNote() {
    commitVisibleEditor()
    notebook.addNote()
    displaySelectedNote(focusEditor: true)
    saveNotebook()
  }

  private func deleteSelectedNote() {
    commitVisibleEditor()
    let selectedNote = notebook.selectedNote
    if !selectedNote.text.isEmpty || !selectedNote.strokes.isEmpty {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = "Delete this note?"
      alert.informativeText = "The note's text and drawing will be removed."
      alert.addButton(withTitle: "Delete Note")
      alert.addButton(withTitle: "Cancel")
      alert.buttons.first?.hasDestructiveAction = true
      guard alert.runModal() == .alertFirstButtonReturn else {
        saveNotebook()
        return
      }
    }

    notebook.deleteSelectedNote()
    displaySelectedNote(focusEditor: true)
    saveNotebook()
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
  }

  private func updateSelectedText(_ text: String) {
    let index = notebook.selectedIndex
    notebook.notes[index].text = text
  }

  private func displaySelectedNote(focusEditor: Bool) {
    isDisplayingNote = true
    bubbleView.display(
      note: notebook.selectedNote,
      index: notebook.selectedIndex,
      total: notebook.notes.count
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
