import Foundation
import XCTest

@testable import MemoPetCore

final class UpdateCheckerTests: XCTestCase {
  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testSemanticVersionComparison() throws {
    XCTAssertLessThan(try XCTUnwrap(AppVersion("0.2.9")), try XCTUnwrap(AppVersion("0.3.0")))
    XCTAssertLessThan(try XCTUnwrap(AppVersion("v1.9")), try XCTUnwrap(AppVersion("1.10")))
    XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
    XCTAssertEqual(AppVersion("V2.0.0-beta"), AppVersion("2"))
    XCTAssertNil(AppVersion("version two"))
    XCTAssertNil(AppVersion("1.-2.3"))
    XCTAssertNil(AppVersion("1..3"))
  }

  func testDailyScheduleHandlesRecentOldAndFutureDates() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    XCTAssertTrue(
      UpdateCheckSchedule.shouldCheck(lastCheck: nil, now: now)
    )
    XCTAssertFalse(
      UpdateCheckSchedule.shouldCheck(
        lastCheck: now.addingTimeInterval(-60),
        now: now
      )
    )
    XCTAssertTrue(
      UpdateCheckSchedule.shouldCheck(
        lastCheck: now.addingTimeInterval(-(24 * 60 * 60)),
        now: now
      )
    )
    XCTAssertTrue(
      UpdateCheckSchedule.shouldCheck(
        lastCheck: now.addingTimeInterval(60),
        now: now
      )
    )
  }

  func testNewerGitHubReleaseReturnsValidatedUpdate() throws {
    let endpoint = try XCTUnwrap(URL(string: "https://api.github.test/latest"))
    let releaseURL = try XCTUnwrap(
      URL(string: "https://github.com/tinkerer0/MemoPet/releases/tag/v0.3.0")
    )
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
      XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MemoPet/0.2.0")
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: endpoint,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = try JSONSerialization.data(
        withJSONObject: [
          "tag_name": "v0.3.0",
          "html_url": releaseURL.absoluteString,
        ]
      )
      return (response, data)
    }

    let result = try waitForResult(
      checker: makeChecker(endpoint: endpoint),
      currentVersion: "0.2.0"
    )

    XCTAssertEqual(
      result,
      .updateAvailable(
        AvailableUpdate(version: "0.3.0", releaseURL: releaseURL)
      )
    )
  }

  func testSameReleaseIsUpToDate() throws {
    let endpoint = try XCTUnwrap(URL(string: "https://api.github.test/latest"))
    URLProtocolStub.requestHandler = { _ in
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: endpoint,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = try JSONSerialization.data(
        withJSONObject: [
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/tinkerer0/MemoPet/releases/tag/v0.3.0",
        ]
      )
      return (response, data)
    }

    let result = try waitForResult(
      checker: makeChecker(endpoint: endpoint),
      currentVersion: "0.3"
    )

    XCTAssertEqual(result, .upToDate)
  }

  func testRejectsNonGitHubReleaseLink() throws {
    let endpoint = try XCTUnwrap(URL(string: "https://api.github.test/latest"))
    URLProtocolStub.requestHandler = { _ in
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: endpoint,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = try JSONSerialization.data(
        withJSONObject: [
          "tag_name": "v9.0.0",
          "html_url": "https://example.com/not-a-release",
        ]
      )
      return (response, data)
    }

    XCTAssertThrowsError(
      try waitForResult(
        checker: makeChecker(endpoint: endpoint),
        currentVersion: "0.3.0"
      )
    )
  }

  func testReportsHTTPFailure() throws {
    let endpoint = try XCTUnwrap(URL(string: "https://api.github.test/latest"))
    URLProtocolStub.requestHandler = { _ in
      let response = try XCTUnwrap(
        HTTPURLResponse(
          url: endpoint,
          statusCode: 503,
          httpVersion: nil,
          headerFields: nil
        )
      )
      return (response, Data())
    }

    XCTAssertThrowsError(
      try waitForResult(
        checker: makeChecker(endpoint: endpoint),
        currentVersion: "0.3.0"
      )
    )
  }

  func testReportsOfflineNetworkFailureWithoutCrashing() throws {
    let endpoint = try XCTUnwrap(URL(string: "https://api.github.test/latest"))
    URLProtocolStub.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    XCTAssertThrowsError(
      try waitForResult(
        checker: makeChecker(endpoint: endpoint),
        currentVersion: "0.3.0"
      )
    ) { error in
      XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    }
  }

  private func makeChecker(endpoint: URL) -> GitHubReleaseChecker {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return GitHubReleaseChecker(
      session: URLSession(configuration: configuration),
      endpoint: endpoint
    )
  }

  private func waitForResult(
    checker: GitHubReleaseChecker,
    currentVersion: String
  ) throws -> UpdateCheckResult {
    let expectation = expectation(description: "Update check completes")
    var receivedResult: Result<UpdateCheckResult, Error>?
    checker.check(currentVersion: currentVersion) { result in
      receivedResult = result
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
    return try XCTUnwrap(receivedResult).get()
  }
}

private final class URLProtocolStub: URLProtocol {
  static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = Self.requestHandler else {
      XCTFail("Missing URLProtocolStub request handler")
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
