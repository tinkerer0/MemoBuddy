import AppKit

final class AnimationLifecycle {
  var onSuspensionChanged: ((Bool) -> Void)?

  private var screenSleeping = false
  private var sessionInactive = false

  init() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self,
      selector: #selector(screenDidSleep),
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(screenDidWake),
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(sessionDidResignActive),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    center.addObserver(
      self,
      selector: #selector(sessionDidBecomeActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  @objc private func screenDidSleep() {
    screenSleeping = true
    publish()
  }

  @objc private func screenDidWake() {
    screenSleeping = false
    publish()
  }

  @objc private func sessionDidResignActive() {
    sessionInactive = true
    publish()
  }

  @objc private func sessionDidBecomeActive() {
    sessionInactive = false
    publish()
  }

  private func publish() {
    onSuspensionChanged?(screenSleeping || sessionInactive)
  }
}
