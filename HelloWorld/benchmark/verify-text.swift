import AppKit
import Vision

// Validate the settled image outside the app and outside the measured launch path.
guard CommandLine.arguments.count == 2 else { exit(2) }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
let normalized = strings.joined(separator: " ").lowercased().filter { $0.isLetter }
guard normalized.contains("helloworld") else {
    FileHandle.standardError.write(Data("Settled image does not contain Hello, world!: \(strings)\n".utf8))
    exit(3)
}
print(strings.joined(separator: "\n"))
