import AppKit
import Foundation

private struct LaunchResult: Codable {
  let launchStartedTimestampMs: Double
  let pid: Int32
  let desktopSession: DesktopSession
}

// A shareable display can still belong to a locked session. Some WebKit pages
// suspend there; expose the state so diagnostic runs can record this condition.
private struct DesktopSession: Codable {
  let locked: Bool
  let onConsole: Bool
  let lastLockedTimestampMs: Double?
}
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
private let desktopSession = DesktopSession(
  locked: session["CGSSessionScreenIsLocked"] as? Bool ?? false,
  onConsole: session["kCGSSessionOnConsoleKey"] as? Bool ?? false,
  lastLockedTimestampMs: (session["CGSSessionScreenLockedTime"] as? Double).map { $0 * 1_000 })
if CommandLine.arguments.dropFirst().first == "--check-session" {
  FileHandle.standardOutput.write(try JSONEncoder().encode(desktopSession))
  exit(0)
}
let allowLockedSession = ProcessInfo.processInfo.environment["CHAT_HISTORY_BENCHMARK_ALLOW_LOCKED"] == "1"
guard desktopSession.onConsole && (!desktopSession.locked || allowLockedSession) else {
  FileHandle.standardError.write(Data("Benchmark requires an unlocked console session. Unlock the Mac before rerunning.\n".utf8))
  exit(6)
}

guard CommandLine.arguments.count >= 2 else {
  FileHandle.standardError.write(Data("Usage: launch-app <bundle.app> [arguments...]\n".utf8))
  exit(2)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
configuration.addsToRecentItems = false
configuration.createsNewApplicationInstance = true
// NSArgumentDomain is process-local: this does not write user/global defaults.
// Both suites share this launcher, including capture-disabled memory launches.
// The opt-out exists only for controlled presentation-policy verification.
let useSystemAnimations = ProcessInfo.processInfo.environment["CHAT_HISTORY_BENCHMARK_SYSTEM_ANIMATIONS"] == "1"
configuration.arguments = Array(CommandLine.arguments.dropFirst(2)) + (useSystemAnimations ? [] : [
  "-NSAutomaticWindowAnimationsEnabled", "NO"
])
configuration.environment = ProcessInfo.processInfo.environment
let launchStartedTimestampMs = Date().timeIntervalSince1970 * 1_000
NSWorkspace.shared.openApplication(
  at: URL(fileURLWithPath: CommandLine.arguments[1]),
  configuration: configuration
) { application, error in
  if let error {
    FileHandle.standardError.write(Data("Could not launch app: \(error.localizedDescription)\n".utf8))
    exit(3)
  }
  guard let application else {
    FileHandle.standardError.write(Data("LaunchServices returned no application\n".utf8))
    exit(4)
  }
  do {
    let result = LaunchResult(
      launchStartedTimestampMs: launchStartedTimestampMs,
      pid: application.processIdentifier,
      desktopSession: desktopSession)
    FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("Could not encode launch result: \(error)\n".utf8))
    exit(5)
  }
}
RunLoop.main.run()
