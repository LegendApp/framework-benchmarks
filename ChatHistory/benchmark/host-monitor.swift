import Foundation
import Darwin

// Low-frequency host-wide diagnostics; never sample or suspend measured tasks.
func cpuTicks() -> [UInt32]? {
  var info = host_cpu_load_info()
  var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
  let status = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
    }
  }
  guard status == KERN_SUCCESS else { return nil }
  return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
}
var previous = cpuTicks()
while true {
  Thread.sleep(forTimeInterval: 5)
  let current = cpuTicks()
  var row: [String: Any] = ["timestampMs": Date().timeIntervalSince1970 * 1000,
    "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
    "activeProcessorCount": ProcessInfo.processInfo.activeProcessorCount]
  if let a = previous, let b = current {
    let delta = zip(a, b).map { Double($1 &- $0) }
    let total = delta.reduce(0, +)
    if total > 0 { row["cpuBusyPercent"] = 100 * (total - delta[2]) / total }
  }
  previous = current
  if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
  }
}
