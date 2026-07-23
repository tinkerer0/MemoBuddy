import AppKit
import MemoPetCore

final class NoteListPopoverController: NSViewController {
  var onSelectNote: ((Int) -> Void)?
  var onRenameNote: ((Int, String) -> Void)?
  var onDeleteNote: ((Int) -> Void)?
  var onAddNote: (() -> Void)?

  private let titleLabel = NSTextField(labelWithString: "Memo List")
  private let addButton = NoteListPopoverController.makeIconButton(
    symbolName: "plus",
    accessibilityLabel: "Add note"
  )
  private let scrollView = NSScrollView(frame: .zero)
  private let rowsView = FlippedRowsView(frame: .zero)
  private var rowViews: [NoteListRowView] = []
  private var displayedNoteCount = 1
  private var pendingDeleteIndex: Int?

  override func loadView() {
    view = NSView(
      frame: NSRect(
        origin: .zero,
        size: NSSize(width: 280, height: 160)
      )
    )

    titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    titleLabel.textColor = .labelColor

    addButton.target = self
    addButton.action = #selector(addNote)

    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = rowsView

    view.addSubview(titleLabel)
    view.addSubview(addButton)
    view.addSubview(scrollView)
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let bounds = view.bounds
    let headerHeight: CGFloat = 38

    titleLabel.frame = NSRect(
      x: 12,
      y: bounds.maxY - 29,
      width: max(0, bounds.width - 56),
      height: 18
    )
    addButton.frame = NSRect(
      x: bounds.maxX - 34,
      y: bounds.maxY - 33,
      width: 24,
      height: 24
    )
    scrollView.frame = NSRect(
      x: 8,
      y: 8,
      width: max(0, bounds.width - 16),
      height: max(0, bounds.height - headerHeight - 8)
    )
    layoutRows()
  }

  func display(notes: [MemoNote], selectedIndex: Int) {
    _ = view
    pendingDeleteIndex = nil
    displayedNoteCount = notes.count
    rowViews.forEach { $0.removeFromSuperview() }
    rowViews = notes.enumerated().map { index, note in
      let row = NoteListRowView(
        index: index,
        title: note.title ?? "",
        fallbackTitle: Self.fallbackTitle(for: note),
        isSelected: index == selectedIndex,
        canDelete: notes.count > 1 || !note.isEmpty,
        clearsOnlyNote: notes.count == 1
      )
      row.onSelect = { [weak self] index in
        self?.onSelectNote?(index)
      }
      row.onRename = { [weak self] index, title in
        self?.onRenameNote?(index, title)
      }
      row.onDelete = { [weak self] index in
        self?.requestDelete(at: index)
      }
      row.onCancelDelete = { [weak self] in
        self?.dismissDeleteConfirmation()
      }
      row.onConfirmDelete = { [weak self] index in
        self?.confirmDelete(at: index)
      }
      rowsView.addSubview(row)
      return row
    }

    updatePreferredContentSize()
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
  }

  func dismissDeleteConfirmation() {
    pendingDeleteIndex = nil
    rowViews.forEach {
      $0.setDeleteConfirmationVisible(false)
    }
  }

  private func requestDelete(at index: Int) {
    guard index >= 0, index < displayedNoteCount else { return }
    pendingDeleteIndex = index
    for (rowIndex, row) in rowViews.enumerated() {
      row.setDeleteConfirmationVisible(rowIndex == index)
    }
  }

  private func confirmDelete(at index: Int) {
    guard pendingDeleteIndex == index else { return }
    dismissDeleteConfirmation()
    onDeleteNote?(index)
  }

  @objc private func addNote() {
    onAddNote?()
  }

  private func updatePreferredContentSize() {
    let visibleRows = min(max(displayedNoteCount, 1), 8)
    preferredContentSize = NSSize(
      width: 280,
      height: 46
        + (CGFloat(visibleRows) * NoteListRowView.height)
    )
  }

  private func layoutRows() {
    let width = scrollView.contentSize.width
    let contentHeight = max(
      scrollView.contentSize.height,
      CGFloat(rowViews.count) * NoteListRowView.height
    )
    rowsView.frame = NSRect(
      x: 0,
      y: 0,
      width: width,
      height: contentHeight
    )

    for (index, row) in rowViews.enumerated() {
      row.frame = NSRect(
        x: 0,
        y: CGFloat(index) * NoteListRowView.height,
        width: width,
        height: NoteListRowView.height
      )
    }
  }

  private static func fallbackTitle(for note: MemoNote) -> String {
    let collapsedText = note.text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    if collapsedText.isEmpty {
      return note.strokes.isEmpty ? "Blank note" : "Drawing"
    }

    let maximumLength = 36
    let preview = String(collapsedText.prefix(maximumLength))
    return collapsedText.count > maximumLength ? "\(preview)…" : preview
  }

  private static func makeIconButton(
    symbolName: String,
    accessibilityLabel: String
  ) -> NSButton {
    let button = NSButton(frame: .zero)
    button.image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: accessibilityLabel
    )
    button.imagePosition = .imageOnly
    button.isBordered = false
    button.bezelStyle = .inline
    button.focusRingType = .none
    button.toolTip = accessibilityLabel
    button.setAccessibilityLabel(accessibilityLabel)
    return button
  }
}

private final class FlippedRowsView: NSView {
  override var isFlipped: Bool { true }
}

private final class NoteListRowView:
  NSView,
  NSTextFieldDelegate
{
  static let height: CGFloat = 36

  var onSelect: ((Int) -> Void)?
  var onRename: ((Int, String) -> Void)?
  var onDelete: ((Int) -> Void)?
  var onCancelDelete: (() -> Void)?
  var onConfirmDelete: ((Int) -> Void)?

  private let index: Int
  private let isSelected: Bool
  private let canDelete: Bool
  private let titleField = NSTextField(frame: .zero)
  private let deleteButton = NSButton(frame: .zero)
  private let cancelDeleteButton = NSButton(frame: .zero)
  private let confirmDeleteButton = NSButton(frame: .zero)
  private var isShowingDeleteConfirmation = false
  private var isEditingTitle = false

  init(
    index: Int,
    title: String,
    fallbackTitle: String,
    isSelected: Bool,
    canDelete: Bool,
    clearsOnlyNote: Bool
  ) {
    self.index = index
    self.isSelected = isSelected
    self.canDelete = canDelete
    super.init(frame: .zero)

    wantsLayer = true
    layer?.cornerRadius = 7
    updateBackgroundColor()

    titleField.stringValue = title
    titleField.placeholderString = fallbackTitle
    titleField.font = .systemFont(ofSize: 12)
    titleField.lineBreakMode = .byTruncatingTail
    titleField.usesSingleLineMode = true
    titleField.isEditable = false
    titleField.isSelectable = false
    titleField.isBordered = false
    titleField.drawsBackground = false
    titleField.focusRingType = .none
    titleField.toolTip = "Click to open; right-click or double-click to rename"
    toolTip = titleField.toolTip
    titleField.delegate = self
    titleField.setAccessibilityLabel("Note \(index + 1) title")

    deleteButton.image = NSImage(
      systemSymbolName: "trash",
      accessibilityDescription: "Delete note \(index + 1)"
    )
    deleteButton.imagePosition = .imageOnly
    deleteButton.isBordered = false
    deleteButton.bezelStyle = .inline
    deleteButton.focusRingType = .none
    deleteButton.contentTintColor = .secondaryLabelColor
    deleteButton.toolTip = "Delete note \(index + 1)"
    deleteButton.setAccessibilityLabel("Delete note \(index + 1)")
    deleteButton.target = self
    deleteButton.action = #selector(deleteNote)
    deleteButton.isHidden = !canDelete

    configureConfirmationButton(
      cancelDeleteButton,
      title: "Cancel",
      color: .secondaryLabelColor,
      accessibilityLabel: "Cancel note deletion",
      action: #selector(cancelDelete)
    )
    configureConfirmationButton(
      confirmDeleteButton,
      title: clearsOnlyNote ? "Clear" : "Delete",
      color: .systemRed,
      accessibilityLabel: clearsOnlyNote
        ? "Clear note \(index + 1)"
        : "Delete note \(index + 1)",
      action: #selector(confirmDelete)
    )

    addSubview(titleField)
    addSubview(deleteButton)
    addSubview(cancelDeleteButton)
    addSubview(confirmDeleteButton)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    deleteButton.frame = NSRect(
      x: bounds.maxX - 28,
      y: 6,
      width: 24,
      height: 24
    )
    confirmDeleteButton.frame = NSRect(
      x: bounds.maxX - 52,
      y: 6,
      width: 48,
      height: 24
    )
    cancelDeleteButton.frame = NSRect(
      x: confirmDeleteButton.frame.minX - 52,
      y: 6,
      width: 48,
      height: 24
    )
    let titleTrailingEdge: CGFloat
    if isShowingDeleteConfirmation {
      titleTrailingEdge = cancelDeleteButton.frame.minX - 4
    } else if canDelete {
      titleTrailingEdge = deleteButton.frame.minX - 4
    } else {
      titleTrailingEdge = bounds.maxX - 4
    }
    titleField.frame = NSRect(
      x: 8,
      y: 5,
      width: max(0, titleTrailingEdge - 8),
      height: 25
    )
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let hitView = super.hitTest(point)
    if hitView === deleteButton
      || hitView === cancelDeleteButton
      || hitView === confirmDeleteButton
      || isEditingTitle
    {
      return hitView
    }
    return bounds.contains(point) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    guard !isShowingDeleteConfirmation else { return }
    let point = convert(event.locationInWindow, from: nil)
    if event.clickCount >= 2, titleField.frame.contains(point) {
      beginTitleEditing()
      return
    }
    onSelect?(index)
  }

  override func rightMouseDown(with event: NSEvent) {
    guard !isShowingDeleteConfirmation else { return }
    let point = convert(event.locationInWindow, from: nil)
    if titleField.frame.contains(point) {
      beginTitleEditing()
      return
    }
    super.rightMouseDown(with: event)
  }

  func setDeleteConfirmationVisible(_ isVisible: Bool) {
    if isVisible, isEditingTitle {
      window?.makeFirstResponder(nil)
      finishTitleEditing()
    }
    isShowingDeleteConfirmation = isVisible
    deleteButton.isHidden = isVisible || !canDelete
    cancelDeleteButton.isHidden = !isVisible
    confirmDeleteButton.isHidden = !isVisible
    updateBackgroundColor()
    needsLayout = true
  }

  func controlTextDidChange(_ notification: Notification) {
    onRename?(index, titleField.stringValue)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    finishTitleEditing()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    shouldChangeCharactersIn range: NSRange,
    replacementString string: String?
  ) -> Bool {
    let currentTitle = textView.string as NSString
    let updatedTitle = currentTitle.replacingCharacters(
      in: range,
      with: string ?? ""
    )
    return updatedTitle.count <= 80
  }

  @objc private func deleteNote() {
    onDelete?(index)
  }

  @objc private func cancelDelete() {
    onCancelDelete?()
  }

  @objc private func confirmDelete() {
    onConfirmDelete?(index)
  }

  private func beginTitleEditing() {
    guard !isEditingTitle else { return }
    isEditingTitle = true
    titleField.isEditable = true
    titleField.isSelectable = true
    titleField.isBordered = true
    titleField.drawsBackground = true
    titleField.focusRingType = .default
    window?.makeFirstResponder(titleField)
    titleField.selectText(nil)
  }

  private func finishTitleEditing() {
    guard isEditingTitle else { return }
    isEditingTitle = false
    titleField.isEditable = false
    titleField.isSelectable = false
    titleField.isBordered = false
    titleField.drawsBackground = false
    titleField.focusRingType = .none
  }

  private func configureConfirmationButton(
    _ button: NSButton,
    title: String,
    color: NSColor,
    accessibilityLabel: String,
    action: Selector
  ) {
    button.title = title
    button.font = .systemFont(ofSize: 10, weight: .semibold)
    button.isBordered = false
    button.bezelStyle = .inline
    button.focusRingType = .none
    button.contentTintColor = color
    button.toolTip = accessibilityLabel
    button.setAccessibilityLabel(accessibilityLabel)
    button.target = self
    button.action = action
    button.isHidden = true
  }

  private func updateBackgroundColor() {
    layer?.backgroundColor = if isShowingDeleteConfirmation {
      NSColor.systemRed.withAlphaComponent(0.1).cgColor
    } else if isSelected {
      NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
    } else {
      NSColor.clear.cgColor
    }
  }
}
