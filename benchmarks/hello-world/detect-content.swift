import AVFoundation
import Foundation
import Vision

// Inspect native-resolution text, rather than requiring encoded pixels to match
// a much later frame. The latter confuses compression changes with startup.
guard CommandLine.arguments.count == 7,
  let startMs = Double(CommandLine.arguments[2]),
  let x = Double(CommandLine.arguments[3]), let y = Double(CommandLine.arguments[4]),
  let width = Double(CommandLine.arguments[5]), let height = Double(CommandLine.arguments[6])
else { exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let track = asset.tracks(withMediaType: .video).first else { exit(3) }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
  kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
reader.add(output)
guard reader.startReading() else { throw reader.error! }
var frames: [[String: Any]] = []
var index = 0
var matchedRun = 0
while let sample = output.copyNextSampleBuffer() {
  let videoMs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 1000
  defer { index += 1 }
  if videoMs < startMs { continue }
  if let buffer = CMSampleBufferGetImageBuffer(sample) {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.regionOfInterest = CGRect(x: x, y: 1 - y - height, width: width, height: height)
    try VNImageRequestHandler(cvPixelBuffer: buffer).perform([request])
    let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
    let text = candidates.map { $0.string }.joined(separator: " ")
    let confidence = candidates.map { $0.confidence }.min() ?? 0
    let matched = text.lowercased().filter { $0.isLetter } == "helloworld" && confidence >= 0.8
    frames.append(["frameIndex": index, "videoMs": videoMs, "text": text,
                   "confidence": confidence, "matched": matched])
    matchedRun = matched ? matchedRun + 1 : 0
    if matchedRun == 3 { break }
  } else {
    matchedRun = 0
  }
}
reader.cancelReading()
guard matchedRun == 3 else {
  FileHandle.standardError.write(Data("No three consecutive readable Hello World frames\n".utf8))
  exit(3)
}
print(String(data: try JSONSerialization.data(withJSONObject: frames), encoding: .utf8)!)
