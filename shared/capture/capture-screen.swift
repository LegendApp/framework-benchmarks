import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

private struct CaptureSidecar: Codable {
  let captureFps: Int
  let frameTimestampsMs: [Double]
}

private final class CaptureController: NSObject, SCRecordingOutputDelegate, SCStreamDelegate,
  SCStreamOutput
{
  private let captureFps = 60
  private let outputURL: URL
  private let sidecarURL: URL
  private let lock = NSLock()
  private let hostClockOffsetMs: Double
  private var frameTimestampsMs: [Double] = []
  private var didEmitReady = false
  private var didFinish = false
  private var recordingStarted = false
  private var display: SCDisplay?
  private var stream: SCStream?

  init(outputURL: URL, sidecarURL: URL) {
    self.outputURL = outputURL
    self.sidecarURL = sidecarURL
    let hostTimeMs = CMClockGetTime(CMClockGetHostTimeClock()).seconds * 1_000
    hostClockOffsetMs = Date().timeIntervalSince1970 * 1_000 - hostTimeMs
  }

  func start() async throws {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      throw NSError(
        domain: "ChatHistoryCapture",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Screen Recording permission is required for Chat History Benchmark Capture"
        ])
    }
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
      throw NSError(
        domain: "ChatHistoryCapture", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Main display is unavailable"])
    }
    let helper = content.applications.filter {
      $0.bundleIdentifier == "so.legend.chat-history-benchmark-capture"
    }
    let filter = SCContentFilter(
      display: display, excludingApplications: helper, exceptingWindows: [])
    let configuration = SCStreamConfiguration()
    configuration.width = display.width
    configuration.height = display.height
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(captureFps))
    configuration.queueDepth = 8
    configuration.showsCursor = false
    configuration.capturesAudio = false

    let recordingConfiguration = SCRecordingOutputConfiguration()
    recordingConfiguration.outputURL = outputURL
    recordingConfiguration.outputFileType = .mp4
    recordingConfiguration.videoCodecType = .h264
    let recordingOutput = SCRecordingOutput(
      configuration: recordingConfiguration, delegate: self)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    try stream.addStreamOutput(
      self, type: .screen,
      sampleHandlerQueue: DispatchQueue(label: "so.legend.chat-history.capture.frames"))
    try stream.addRecordingOutput(recordingOutput)
    self.display = display
    self.stream = stream
    try await stream.startCapture()
  }

  func target(processID: pid_t) async {
    guard let stream, let display else { return }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        if let application = content.applications.first(where: { $0.processID == processID }) {
          let filter = SCContentFilter(
            display: display, including: [application], exceptingWindows: [])
          try await stream.updateContentFilter(filter)
          let payload = "{\"targetReady\":true,\"pid\":\(processID)}\n"
          FileHandle.standardOutput.write(Data(payload.utf8))
          return
        }
      } catch {
        FileHandle.standardError.write(
          Data("Could not find capture target yet: \(error.localizedDescription)\n".utf8))
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    FileHandle.standardError.write(Data("Could not capture process \(processID)\n".utf8))
    exit(5)
  }

  func stop() {
    guard let stream else { finish(error: nil); return }
    stream.stopCapture { [weak self] error in
      if let error {
        self?.finish(error: error)
      }
    }
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen, sampleBuffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let attachment = attachments.first,
      let statusNumber = attachment[.status] as? NSNumber,
      SCFrameStatus(rawValue: statusNumber.intValue) == .complete,
      let displayTime = attachment[.displayTime] as? NSNumber
    else {
      return
    }
    let timestampMs = hostClockOffsetMs
      + CMClockMakeHostTimeFromSystemUnits(displayTime.uint64Value).seconds * 1_000
    lock.lock()
    if frameTimestampsMs.last != timestampMs {
      frameTimestampsMs.append(timestampMs)
    }
    emitReadyIfPossibleLocked()
    lock.unlock()
  }

  func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
    lock.lock()
    recordingStarted = true
    emitReadyIfPossibleLocked()
    lock.unlock()
  }

  func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
    finish(error: nil)
  }

  func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
    finish(error: error)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    finish(error: error)
  }

  private func emitReadyIfPossibleLocked() {
    guard recordingStarted, !frameTimestampsMs.isEmpty, !didEmitReady else { return }
    didEmitReady = true
    let payload = "{\"ready\":true,\"firstFrameTimestampMs\":\(frameTimestampsMs[0])}\n"
    FileHandle.standardOutput.write(Data(payload.utf8))
  }

  private func finish(error: Error?) {
    lock.lock()
    guard !didFinish else { lock.unlock(); return }
    didFinish = true
    let timestamps = frameTimestampsMs
    lock.unlock()
    do {
      let sidecar = CaptureSidecar(captureFps: captureFps, frameTimestampsMs: timestamps)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(sidecar).write(to: sidecarURL)
    } catch {
      FileHandle.standardError.write(Data("Could not write capture timestamps: \(error)\n".utf8))
      exit(4)
    }
    if let error {
      FileHandle.standardError.write(Data("Capture failed: \(error.localizedDescription)\n".utf8))
      exit(3)
    }
    exit(0)
  }
}

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("Usage: ChatHistoryCapture <video.mp4> <timestamps.json>\n".utf8))
  exit(2)
}

private let controller = CaptureController(
  outputURL: URL(fileURLWithPath: CommandLine.arguments[1]),
  sidecarURL: URL(fileURLWithPath: CommandLine.arguments[2]))
Task {
  do {
    try await controller.start()
    DispatchQueue.global().async {
      while let command = readLine() {
        if command == "q" {
          controller.stop()
          return
        }
        if command.hasPrefix("pid "), let processID = Int32(command.dropFirst(4)) {
          Task { await controller.target(processID: pid_t(processID)) }
        }
      }
      controller.stop()
    }
  } catch {
    FileHandle.standardError.write(Data("Capture failed: \(error.localizedDescription)\n".utf8))
    exit(3)
  }
}
RunLoop.main.run()
