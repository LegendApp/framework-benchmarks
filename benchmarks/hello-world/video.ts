import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, rmSync, writeFileSync } from "node:fs";
import { relative } from "node:path";
import { changedRatio, cropVideo, extractFeatures, firstStableFrame, nearestFrame, probeVideo, videoWindow, type WindowInfo } from "../chat-history/video";
import { detectContentExecutable, verifyTextExecutable } from "./macos";

export async function analyzeHelloWorld(input: {
  recordingPath: string;
  timestampPath: string;
  artifactPath: string;
  resultsRoot: string;
  launchTimestampMs: number;
  window: WindowInfo;
}) {
  const probe = probeVideo(input.recordingPath, input.timestampPath);
  const rect = videoWindow(input.window, probe.width, probe.height);
  const frames = await extractFeatures(input.recordingPath, probe.width, probe.height, probe.timestampsMs, rect);
  const referenceTimestampMs = frames.at(-1)!.timestampMs - 250;
  const referenceFrame = nearestFrame(frames, referenceTimestampMs);
  const reference = frames[referenceFrame];
  const baseline = frames[nearestFrame(frames, input.launchTimestampMs - 100)];
  if (baseline.timestampMs >= input.launchTimestampMs) throw new Error("Recording has no pre-launch baseline");
  const change = changedRatio(reference.feature, baseline.feature);
  if (change < 0.01) throw new Error("Recording does not show a new window");
  const windowFrame = firstStableFrame(frames, input.launchTimestampMs, referenceTimestampMs,
    (frame) => changedRatio(frame.feature, baseline.feature) >= Math.max(0.01, change * 0.4));

  // The text is a tiny fraction of a blank window. Match a tight central region,
  // otherwise the product suite's whole-window tolerance can accept an empty frame.
  const textRect = {
    x: rect.x + rect.width * 0.35,
    y: rect.y + rect.height * 0.42,
    width: Math.floor(rect.width * 0.3),
    height: Math.floor(rect.height * 0.2),
  };
  if (windowFrame < 0) throw new Error("Missing stable window frames");
  const sourceStartMs = Number(execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=start_time", "-of", "default=nw=1:nk=1", input.recordingPath], { encoding: "utf8" }).trim()) * 1000;
  if (!Number.isFinite(sourceStartMs)) throw new Error("Missing recording presentation timestamp origin");
  const ocrFrames = JSON.parse(execFileSync(detectContentExecutable, [
    input.recordingPath, String(sourceStartMs + frames[windowFrame].timestampMs - probe.timestampsMs[0]),
    String(textRect.x / probe.width), String(textRect.y / probe.height),
    String(textRect.width / probe.width), String(textRect.height / probe.height),
  ], { encoding: "utf8" })) as Array<{ frameIndex: number; videoMs: number; text: string; confidence: number; matched: boolean }>;
  const firstContentTimestampMs = probe.timestampsMs[0] + ocrFrames.at(-3)!.videoMs - sourceStartMs;
  const contentFrame = nearestFrame(frames, firstContentTimestampMs);
  if (contentFrame < windowFrame || !probe.timestampsMs[contentFrame]) throw new Error("Invalid OCR content boundary");

  cropVideo(input.recordingPath, input.artifactPath, rect);
  const screenshot = input.artifactPath.replace(/\.mp4$/, ".png");
  // OCR only the central content region, excluding a title bar that also says Hello World.
  writeReferenceScreenshot(input.recordingPath, screenshot, referenceFrame, textRect);
  const recognizedText = execFileSync(verifyTextExecutable, [screenshot], { encoding: "utf8" }).trim();
  const captureTimestamps = input.artifactPath.replace(/\.mp4$/, ".capture.json");
  copyFileSync(input.timestampPath, captureTimestamps);
  const evidence = {
    analysisVersion: 2,
    launchTimestampMs: input.launchTimestampMs,
    recordingStartedTimestampMs: probe.timestampsMs[0],
    videoLaunchOffsetMs: input.launchTimestampMs - probe.timestampsMs[0],
    captureTimestamps: relative(input.resultsRoot, captureTimestamps),
    windowOpenTimestampMs: frames[windowFrame].timestampMs,
    firstContentTimestampMs,
    windowOpenFrame: windowFrame,
    firstContentFrame: contentFrame,
    referenceTimestampMs,
    referenceFrame,
    referenceExtraction: "recorded frame index",
    frameCount: frames.length,
    window: input.window,
    textRect,
    match: { stableFrames: 3, contentMethod: "native-resolution Vision OCR", minimumConfidence: 0.8 },
    ocrFrames,
    recognizedText,
    video: relative(input.resultsRoot, input.artifactPath),
    screenshot: relative(input.resultsRoot, screenshot),
  };
  writeFileSync(input.artifactPath.replace(/\.mp4$/, ".frames.json"), JSON.stringify(evidence, null, 2) + "\n");
  return evidence;
}

export function writeReferenceScreenshot(
  recordingPath: string,
  outputPath: string,
  frameIndex: number,
  rect: { x: number; y: number; width: number; height: number },
) {
  // A positive presentation-time origin can make EOF seeking overshoot the last
  // packet. Decode the recorded frame index instead; startup OCR is unchanged.
  rmSync(outputPath, { force: true });
  execFileSync("ffmpeg", ["-v", "error", "-i", recordingPath,
    "-vf", `select='eq(n,${frameIndex})',crop=${rect.width}:${rect.height}:${Math.round(rect.x)}:${Math.round(rect.y)}`,
    "-frames:v", "1", "-update", "1", "-y", outputPath]);
  if (!existsSync(outputPath)) throw new Error(`No screenshot for recorded frame ${frameIndex}`);
}
