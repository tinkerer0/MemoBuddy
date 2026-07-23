import AppKit

final class AppSettings {
  private enum Key {
    static let characterOriginX = "characterOriginX"
    static let characterOriginY = "characterOriginY"
    static let hasCharacterOrigin = "hasCharacterOrigin"
    static let characterVisible = "characterVisible"
    static let characterSize = "characterSize"
    static let characterChoice = "characterChoice"
    static let memoWidth = "memoWidth"
    static let memoHeight = "memoHeight"
    static let lastUpdateCheckDate = "lastUpdateCheckDate"
    static let lastNotifiedUpdateVersion = "lastNotifiedUpdateVersion"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var characterOrigin: NSPoint? {
    get {
      guard defaults.bool(forKey: Key.hasCharacterOrigin) else { return nil }
      let x = defaults.double(forKey: Key.characterOriginX)
      let y = defaults.double(forKey: Key.characterOriginY)
      guard x.isFinite, y.isFinite else { return nil }
      return NSPoint(x: x, y: y)
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
      guard value.isFinite, value > 0 else { return 80 }
      return min(max(CGFloat(value), 40), 160)
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

  var memoSize: NSSize {
    get {
      let width = defaults.double(forKey: Key.memoWidth)
      let height = defaults.double(forKey: Key.memoHeight)
      guard width.isFinite, height.isFinite, width > 0, height > 0 else {
        return NSSize(width: 360, height: 220)
      }
      return NSSize(width: width, height: height)
    }
    set {
      defaults.set(Double(newValue.width), forKey: Key.memoWidth)
      defaults.set(Double(newValue.height), forKey: Key.memoHeight)
    }
  }

  var lastUpdateCheckDate: Date? {
    get {
      defaults.object(forKey: Key.lastUpdateCheckDate) as? Date
    }
    set {
      defaults.set(newValue, forKey: Key.lastUpdateCheckDate)
    }
  }

  var lastNotifiedUpdateVersion: String? {
    get {
      defaults.string(forKey: Key.lastNotifiedUpdateVersion)
    }
    set {
      defaults.set(newValue, forKey: Key.lastNotifiedUpdateVersion)
    }
  }
}
