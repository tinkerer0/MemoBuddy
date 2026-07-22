import AppKit

final class AppSettings {
  private enum Key {
    static let characterOriginX = "characterOriginX"
    static let characterOriginY = "characterOriginY"
    static let hasCharacterOrigin = "hasCharacterOrigin"
    static let characterVisible = "characterVisible"
    static let characterSize = "characterSize"
    static let characterChoice = "characterChoice"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var characterOrigin: NSPoint? {
    get {
      guard defaults.bool(forKey: Key.hasCharacterOrigin) else { return nil }
      return NSPoint(
        x: defaults.double(forKey: Key.characterOriginX),
        y: defaults.double(forKey: Key.characterOriginY)
      )
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: Key.characterOriginX)
        defaults.removeObject(forKey: Key.characterOriginY)
        defaults.set(false, forKey: Key.hasCharacterOrigin)
        return
      }
      defaults.set(Double(newValue.x), forKey: Key.characterOriginX)
      defaults.set(Double(newValue.y), forKey: Key.characterOriginY)
      defaults.set(true, forKey: Key.hasCharacterOrigin)
    }
  }

  var isCharacterVisible: Bool {
    get {
      guard defaults.object(forKey: Key.characterVisible) != nil else { return true }
      return defaults.bool(forKey: Key.characterVisible)
    }
    set {
      defaults.set(newValue, forKey: Key.characterVisible)
    }
  }

  var characterSize: CGFloat {
    get {
      let value = defaults.double(forKey: Key.characterSize)
      return value == 0 ? 80 : CGFloat(value)
    }
    set {
      defaults.set(Double(newValue), forKey: Key.characterSize)
    }
  }

  var characterChoice: CharacterChoice? {
    get {
      guard let rawValue = defaults.string(forKey: Key.characterChoice) else {
        return nil
      }
      return CharacterChoice(rawValue: rawValue)
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: Key.characterChoice)
        return
      }
      defaults.set(newValue.rawValue, forKey: Key.characterChoice)
    }
  }
}
