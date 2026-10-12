import CoreGraphics
import Foundation

struct RectPayload: Codable {
  let height: Double
  let width: Double
  let x: Double
  let y: Double
}

struct WindowPayload: Codable {
  let display: RectPayload
  let window: RectPayload
  let windowID: UInt32
}

let requestedPIDs = Set(CommandLine.arguments.dropFirst().compactMap(Int.init))
guard !requestedPIDs.isEmpty else {
  FileHandle.standardError.write(Data("Expected at least one process ID\n".utf8))
  exit(2)
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
let candidates = windows.compactMap { info -> (CGRect, UInt32)? in
  guard
    let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
    requestedPIDs.contains(ownerPID),
    let layer = info[kCGWindowLayer as String] as? Int,
    layer == 0,
    let number = info[kCGWindowNumber as String] as? NSNumber,
    let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
    bounds.width >= 400,
    bounds.height >= 300
  else {
    return nil
  }
  return (bounds, number.uint32Value)
}

guard let (windowBounds, windowID) = candidates.max(by: {
  $0.0.width * $0.0.height < $1.0.width * $1.0.height
}) else {
  let message = "No benchmark window found for \(requestedPIDs.sorted())\n"
  FileHandle.standardError.write(Data(message.utf8))
  exit(3)
}

let displayID = CGMainDisplayID()
let displayBounds = CGDisplayBounds(displayID)
guard displayBounds.intersects(windowBounds) else {
  FileHandle.standardError.write(Data("Benchmark window is not on the main display\n".utf8))
  exit(4)
}

func payload(_ rect: CGRect) -> RectPayload {
  RectPayload(
    height: rect.height,
    width: rect.width,
    x: rect.origin.x,
    y: rect.origin.y)
}

let result = WindowPayload(
  display: payload(displayBounds),
  window: payload(windowBounds),
  windowID: windowID)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(result))
FileHandle.standardOutput.write(Data("\n".utf8))
