import AppKit
import MemoPetCore

private final class ScratchpadPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

final class ScratchpadPanelController: NSWindowController, NSTextViewDelegate {
  static let panelSize = NSSize(width: 360, height: 220)

  private let store: MemoNotebookStore
  private let bubbleView: BubbleBackgroundView
  private var notebook: MemoNotebook
  private var saveTimer: Timer?
  private var previousApplication: NSRunningApplication?
  private var isDisplayingNote = false

  var isShowingScratchpad: Bool {
    window?.isVisible == true
  }

  init(store: MemoNotebookStore) throws {
    self.store = store
    self.notebook = try store.load()
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
    bubbleView.onAddNote = { [weak self] kind in
      self?.addNote(kind: kind)
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
    bubbleView.focusActiveEditor(in: panel)
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
    syncVisibleEditorIntoNotebook()
    saveNotebook()
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
    guard notebook.notes[index].kind == .drawing else { return }
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

  private func addNote(kind: MemoNoteKind) {
    commitVisibleEditor()
    notebook.addNote(kind: kind)
    displaySelectedNote(focusEditor: true)
    saveNotebook()
  }

  private func deleteSelectedNote() {
    commitVisibleEditor()
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
    switch notebook.notes[index].kind {
    case .text:
      notebook.notes[index].text = bubbleView.currentText
    case .drawing:
      notebook.notes[index].strokes = bubbleView.currentStrokes
    }
  }

  private func updateSelectedText(_ text: String) {
    let index = notebook.selectedIndex
    guard notebook.notes[index].kind == .text else { return }
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

  private func saveNotebook() {
    do {
      try store.save(notebook)
      bubbleView.showError(nil)
    } catch {
      bubbleView.showError("Could not save: \(error.localizedDescription)")
    }
  }
}
