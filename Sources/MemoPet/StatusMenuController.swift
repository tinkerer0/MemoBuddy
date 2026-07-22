import AppKit

struct StatusMenuState {
  var characterVisible: Bool
  var hasCustomCharacter: Bool
  var scratchpadVisible: Bool
  var characterSize: CGFloat
}

final class StatusMenuController: NSObject {
  var onToggleScratchpad: (() -> Void)?
  var onChooseCharacter: (() -> Void)?
  var onResetCharacter: (() -> Void)?
  var onCenterCharacter: (() -> Void)?
  var onToggleCharacter: (() -> Void)?
  var onSetCharacterSize: ((CGFloat) -> Void)?
  var onOpenDataFolder: (() -> Void)?
  var onQuit: (() -> Void)?

  private let statusItem: NSStatusItem
  private(set) var menu = NSMenu()

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    super.init()

    if let button = statusItem.button {
      if let image = NSImage(
        systemSymbolName: "note.text",
        accessibilityDescription: "MemoPet"
      ) {
        image.isTemplate = true
        button.image = image
      } else {
        button.title = "Pet"
      }
      button.toolTip = "MemoPet"
    }
  }

  func rebuild(state: StatusMenuState) {
    let menu = NSMenu()

    menu.addItem(
      actionItem(
        title: state.scratchpadVisible ? "Close Memo" : "Open Memo",
        action: #selector(toggleScratchpad)
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      actionItem(title: "Change Character…", action: #selector(chooseCharacter))
    )
    let sizeRootItem = NSMenuItem(title: "Character Size", action: nil, keyEquivalent: "")
    sizeRootItem.submenu = makeSizeMenu(selectedSize: state.characterSize)
    menu.addItem(sizeRootItem)
    menu.addItem(.separator())

    let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
    moreItem.submenu = makeMoreMenu(state: state)
    menu.addItem(moreItem)
    menu.addItem(.separator())
    menu.addItem(actionItem(title: "Quit MemoPet", action: #selector(quit), key: "q"))

    self.menu = menu
    statusItem.menu = menu
  }

  func makeCharacterMenu(state: StatusMenuState) -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      actionItem(
        title: state.scratchpadVisible ? "Close Memo" : "Open Memo",
        action: #selector(toggleScratchpad)
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      actionItem(title: "Change Character…", action: #selector(chooseCharacter))
    )

    let sizeItem = NSMenuItem(title: "Character Size", action: nil, keyEquivalent: "")
    sizeItem.submenu = makeSizeMenu(selectedSize: state.characterSize)
    menu.addItem(sizeItem)
    return menu
  }

  private func actionItem(
    title: String,
    action: Selector,
    key: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  private func makeSizeMenu(selectedSize: CGFloat) -> NSMenu {
    let menu = NSMenu()
    let sizeOptions: [(title: String, value: CGFloat)] = [
      ("Small", 56),
      ("Medium", 80),
      ("Large", 112),
    ]
    for option in sizeOptions {
      let item = actionItem(title: option.title, action: #selector(setCharacterSize(_:)))
      item.representedObject = Double(option.value)
      item.state = abs(selectedSize - option.value) < 0.5 ? .on : .off
      menu.addItem(item)
    }
    return menu
  }

  private func makeMoreMenu(state: StatusMenuState) -> NSMenu {
    let menu = NSMenu()
    let resetItem = actionItem(
      title: "Reset Character",
      action: #selector(resetCharacter)
    )
    resetItem.isEnabled = state.hasCustomCharacter
    menu.addItem(resetItem)
    menu.addItem(
      actionItem(title: "Center Character", action: #selector(centerCharacter))
    )
    menu.addItem(
      actionItem(
        title: state.characterVisible ? "Hide Character" : "Show Character",
        action: #selector(toggleCharacter)
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      actionItem(title: "Open Data Folder", action: #selector(openDataFolder))
    )
    return menu
  }

  @objc private func toggleScratchpad() { onToggleScratchpad?() }
  @objc private func chooseCharacter() { onChooseCharacter?() }
  @objc private func resetCharacter() { onResetCharacter?() }
  @objc private func centerCharacter() { onCenterCharacter?() }
  @objc private func toggleCharacter() { onToggleCharacter?() }
  @objc private func setCharacterSize(_ sender: NSMenuItem) {
    guard let value = sender.representedObject as? Double else { return }
    onSetCharacterSize?(CGFloat(value))
  }
  @objc private func openDataFolder() { onOpenDataFolder?() }
  @objc private func quit() { onQuit?() }
}
