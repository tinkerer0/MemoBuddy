enum CharacterChoice: String, CaseIterable {
  case classic
  case memoWriter
  case orbitingPlanet
  case custom

  static let builtInChoices: [CharacterChoice] = [
    .classic,
    .memoWriter,
    .orbitingPlanet,
  ]

  var menuTitle: String {
    switch self {
    case .classic:
      return "Classic"
    case .memoWriter:
      return "Memo Writer"
    case .orbitingPlanet:
      return "Orbiting Planet"
    case .custom:
      return "Custom Character…"
    }
  }

  var bundledResourceName: String? {
    switch self {
    case .memoWriter:
      return "default-character"
    case .orbitingPlanet:
      return "orbiting-planet"
    case .classic, .custom:
      return nil
    }
  }
}
