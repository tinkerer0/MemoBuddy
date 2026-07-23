import Foundation

public enum UpdateCheckSchedule {
  public static func shouldCheck(
    lastCheck: Date?,
    now: Date = Date(),
    interval: TimeInterval = 24 * 60 * 60
  ) -> Bool {
    guard let lastCheck else { return true }
    let elapsed = now.timeIntervalSince(lastCheck)
    return elapsed < 0 || elapsed >= interval
  }
}

public struct AppVersion: Comparable, Equatable, Sendable {
  private let components: [Int]

  public init?(_ rawValue: String) {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.first == "v" || value.first == "V" {
      value.removeFirst()
    }

    let core = value.prefix { character in
      character != "-" && character != "+"
    }
    let pieces = core.split(separator: ".", omittingEmptySubsequences: false)
    let parsedComponents = pieces.compactMap { Int($0) }
    guard !pieces.isEmpty,
      pieces.allSatisfy({ !$0.isEmpty }),
      parsedComponents.count == pieces.count,
      parsedComponents.allSatisfy({ $0 >= 0 })
    else {
      return nil
    }

    var components = parsedComponents
    while components.count > 1, components.last == 0 {
      components.removeLast()
    }
    self.components = components
  }

  public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0
      if left != right {
        return left < right
      }
    }
    return false
  }
}

public struct AvailableUpdate: Equatable, Sendable {
  public let version: String
  public let releaseURL: URL

  public init(version: String, releaseURL: URL) {
    self.version = version
    self.releaseURL = releaseURL
  }
}

public enum UpdateCheckResult: Equatable, Sendable {
  case upToDate
  case updateAvailable(AvailableUpdate)
}

public enum GitHubReleaseCheckerError: LocalizedError {
  case invalidCurrentVersion
  case invalidResponse
  case httpStatus(Int)
  case invalidRelease

  public var errorDescription: String? {
    switch self {
    case .invalidCurrentVersion:
      return "The current app version is unavailable."
    case .invalidResponse:
      return "GitHub returned an unreadable response."
    case let .httpStatus(status):
      return "GitHub returned HTTP status \(status)."
    case .invalidRelease:
      return "The latest release information is invalid."
    }
  }
}

public final class GitHubReleaseChecker {
  public static let defaultEndpoint = URL(
    string: "https://api.github.com/repos/tinkerer0/MemoPet/releases/latest"
  )!

  private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case htmlURL = "html_url"
    }
  }

  private let session: URLSession
  private let endpoint: URL

  public init(
    session: URLSession = .shared,
    endpoint: URL = GitHubReleaseChecker.defaultEndpoint
  ) {
    self.session = session
    self.endpoint = endpoint
  }

  public func check(
    currentVersion: String,
    completion: @escaping (Result<UpdateCheckResult, Error>) -> Void
  ) {
    guard let installedVersion = AppVersion(currentVersion) else {
      completion(.failure(GitHubReleaseCheckerError.invalidCurrentVersion))
      return
    }

    var request = URLRequest(url: endpoint)
    request.timeoutInterval = 8
    request.setValue(
      "application/vnd.github+json",
      forHTTPHeaderField: "Accept"
    )
    request.setValue(
      "2026-03-10",
      forHTTPHeaderField: "X-GitHub-Api-Version"
    )
    request.setValue(
      "MemoPet/\(currentVersion)",
      forHTTPHeaderField: "User-Agent"
    )

    session.dataTask(with: request) { data, response, error in
      if let error {
        completion(.failure(error))
        return
      }

      guard let response = response as? HTTPURLResponse else {
        completion(.failure(GitHubReleaseCheckerError.invalidResponse))
        return
      }
      guard response.statusCode == 200 else {
        completion(.failure(GitHubReleaseCheckerError.httpStatus(response.statusCode)))
        return
      }
      guard let data,
        let payload = try? JSONDecoder().decode(ReleasePayload.self, from: data),
        let latestVersion = AppVersion(payload.tagName)
      else {
        completion(.failure(GitHubReleaseCheckerError.invalidRelease))
        return
      }

      guard latestVersion > installedVersion else {
        completion(.success(.upToDate))
        return
      }
      guard payload.htmlURL.scheme?.lowercased() == "https",
        payload.htmlURL.host?.lowercased() == "github.com"
      else {
        completion(.failure(GitHubReleaseCheckerError.invalidRelease))
        return
      }

      completion(
        .success(
          .updateAvailable(
            AvailableUpdate(
              version: Self.displayVersion(from: payload.tagName),
              releaseURL: payload.htmlURL
            )
          )
        )
      )
    }.resume()
  }

  private static func displayVersion(from tag: String) -> String {
    var version = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    if version.first == "v" || version.first == "V" {
      version.removeFirst()
    }
    return String(version.prefix { $0 != "-" && $0 != "+" })
  }
}
