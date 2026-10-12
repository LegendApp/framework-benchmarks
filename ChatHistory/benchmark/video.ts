// Chat-history video evidence: which frames prove first content, top, and switch.
import { writeFileSync } from "node:fs";
import { relative } from "node:path";
import {
  captureFps,
  changedPixelThreshold,
  changedRatio,
  contentMaximumChangedRatio,
  cropVideo,
  extractFeatures,
  firstStableFrame,
  nearestFrame,
  percentile,
  probeVideo,
  stableFrames,
  videoWindow,
  windowMinimumChangedRatio,
  type Frame,
  type Recording,
  type WindowInfo,
} from "../../shared/video";

export type VideoEvidence = {
  analysisVersion: 4;
  sourceFrameTimestampsMs: number[];
  legacyWindowContent: { firstContentTimestampMs: number | null; topContentTimestampMs: number | null; switchContentTimestampMs: number | null };
  captureFps: number;
  firstContentFrame: number;
  firstContentTimestampMs: number;
  frameCount: number;
  internal: {
    firstContentTimestampMs: number;
    switchContentTimestampMs: number;
    switchStartedTimestampMs: number;
    topContentTimestampMs: number;
    topStartedTimestampMs: number;
    windowShownTimestampMs: number;
  };
  launchTimestampMs: number;
  match: {
    changedPixelThreshold: number;
    contentMaximumChangedRatio: number;
    contentRegion: typeof transcriptRegion;
    stableFrames: number;
    windowMinimumChangedRatio: number;
  };
  observedFrameIntervalMs: {
    median: number;
    p90: number;
  };
  switchContentFrame: number;
  switchContentTimestampMs: number;
  topContentFrame: number;
  topContentTimestampMs: number;
  video: string;
  window: WindowInfo;
  windowOpenFrame: number;
  windowOpenTimestampMs: number;
};

// The same transcript interior is measured in every app. Window chrome,
// catalog/sidebar animation, metrics, and overlay scrollers are not content.
export const transcriptRegion = { left: 0.24, top: 0.14, right: 0.98, bottom: 0.98 } as const;

export function regionFeature(feature: Uint8Array, width: number, height: number) {
  if (width * height * 3 !== feature.length) throw new Error("Invalid feature dimensions");
  const left = Math.floor(width * transcriptRegion.left);
  const right = Math.floor(width * transcriptRegion.right);
  const top = Math.floor(height * transcriptRegion.top);
  const bottom = Math.floor(height * transcriptRegion.bottom);
  const result = new Uint8Array((right - left) * (bottom - top) * 3);
  for (let row = top; row < bottom; row += 1) {
    result.set(feature.subarray((row * width + left) * 3, (row * width + right) * 3),
      (row - top) * (right - left) * 3);
  }
  return result;
}

export async function analyzeRecording({
  artifactPath,
  firstContentTimestampMs,
  launchTimestampMs,
  recordingPath,
  recordingTimestampPath,
  resultsRoot,
  switchContentTimestampMs,
  switchStartedTimestampMs,
  topContentTimestampMs,
  topStartedTimestampMs,
  windowInfo,
  windowShownTimestampMs,
}: {
  artifactPath: string;
  firstContentTimestampMs: number;
  launchTimestampMs: number;
  recordingPath: string;
  recordingTimestampPath: string;
  resultsRoot: string;
  switchContentTimestampMs: number;
  switchStartedTimestampMs: number;
  topContentTimestampMs: number;
  topStartedTimestampMs: number;
  windowInfo: WindowInfo;
  windowShownTimestampMs: number;
}): Promise<VideoEvidence> {
  if (![firstContentTimestampMs, launchTimestampMs, switchContentTimestampMs,
    switchStartedTimestampMs, topContentTimestampMs, topStartedTimestampMs,
    windowShownTimestampMs].every(Number.isFinite)) {
    throw new Error("Video analysis received a non-finite benchmark timestamp");
  }
  const probe = probeVideo(recordingPath, recordingTimestampPath);
  const rect = videoWindow(windowInfo, probe.width, probe.height);
  const frames = await extractFeatures(
    recordingPath, probe.width, probe.height, probe.timestampsMs, rect);
  const initialReferenceTimestamp = Math.min(
    topStartedTimestampMs - 500,
    firstContentTimestampMs + 1_000,
  );
  const topReferenceTimestamp = Math.min(
    switchStartedTimestampMs - 500,
    topContentTimestampMs + 1_000,
  );
  const switchReferenceTimestamp = frames.at(-1)?.timestampMs ?? switchContentTimestampMs;
  const initialReference = frames[nearestFrame(frames, initialReferenceTimestamp)];
  const topReference = frames[nearestFrame(frames, topReferenceTimestamp)];
  const switchReference = frames[nearestFrame(frames, switchReferenceTimestamp)];
  const baseline = frames[nearestFrame(frames, launchTimestampMs - 100)];
  if (!initialReference || !topReference || !switchReference || !baseline) {
    throw new Error("Screen recording does not span the benchmark reference frames");
  }
  const maximumWindowChange = Math.max(...frames
    .filter((frame) => frame.timestampMs >= launchTimestampMs
      && frame.timestampMs <= initialReferenceTimestamp)
    .map((frame) => changedRatio(frame.feature, baseline.feature)));
  const loadedWindowChange = changedRatio(initialReference.feature, baseline.feature);
  const windowChangeThreshold = Math.max(
    windowMinimumChangedRatio,
    Math.min(maximumWindowChange, loadedWindowChange) * 0.4,
  );
  const windowOpenFrame = firstStableFrame(
    frames,
    launchTimestampMs,
    initialReferenceTimestamp,
    (frame) => changedRatio(frame.feature, baseline.feature) >= windowChangeThreshold,
  );
  const legacyFirstContentFrame = firstStableFrame(
    frames,
    launchTimestampMs,
    topStartedTimestampMs - 250,
    (frame) => changedRatio(frame.feature, initialReference.feature, 0.07)
      <= contentMaximumChangedRatio,
  );
  const legacyTopContentFrame = firstStableFrame(
    frames,
    topStartedTimestampMs,
    switchStartedTimestampMs - 250,
    (frame) => changedRatio(frame.feature, topReference.feature, 0.07)
      <= contentMaximumChangedRatio,
  );
  const legacySwitchContentFrame = firstStableFrame(
    frames,
    switchStartedTimestampMs,
    switchReferenceTimestamp,
    (frame) => changedRatio(frame.feature, switchReference.feature, 0.07)
      <= contentMaximumChangedRatio,
  );
  const contentFrames = frames.map((frame) => ({
    ...frame, feature: regionFeature(frame.feature, frame.width, frame.height),
  }));
  const contentInitialReference = contentFrames[nearestFrame(frames, initialReferenceTimestamp)];
  const contentTopReference = contentFrames[nearestFrame(frames, topReferenceTimestamp)];
  const contentSwitchReference = contentFrames[nearestFrame(frames, switchReferenceTimestamp)];
  const firstContentFrame = firstStableFrame(
    contentFrames,
    launchTimestampMs,
    topStartedTimestampMs - 250,
    (frame) => changedRatio(frame.feature, contentInitialReference.feature)
      <= contentMaximumChangedRatio,
  );
  const topContentFrame = firstStableFrame(
    contentFrames,
    topStartedTimestampMs,
    switchStartedTimestampMs - 250,
    (frame) => changedRatio(frame.feature, contentTopReference.feature)
      <= contentMaximumChangedRatio,
  );
  const switchContentFrame = firstStableFrame(
    contentFrames,
    switchStartedTimestampMs,
    switchReferenceTimestamp,
    (frame) => changedRatio(frame.feature, contentSwitchReference.feature)
      <= contentMaximumChangedRatio,
  );
  if (windowOpenFrame < 0 || firstContentFrame < 0 || topContentFrame < 0 || switchContentFrame < 0) {
    throw new Error(
      `Could not find stable visual frames: window=${windowOpenFrame}, initial=${firstContentFrame}, top=${topContentFrame}, switch=${switchContentFrame}, maximumWindowChange=${maximumWindowChange.toFixed(4)}`,
    );
  }
  cropVideo(recordingPath, artifactPath, rect);
  const frameIntervals = frames.slice(1).map(
    (frame, index) => frame.timestampMs - frames[index].timestampMs,
  );
  const evidence: VideoEvidence = {
    analysisVersion: 4,
    sourceFrameTimestampsMs: frames.map((frame) => frame.timestampMs),
    legacyWindowContent: {
      firstContentTimestampMs: frames[legacyFirstContentFrame]?.timestampMs ?? null,
      topContentTimestampMs: frames[legacyTopContentFrame]?.timestampMs ?? null,
      switchContentTimestampMs: frames[legacySwitchContentFrame]?.timestampMs ?? null,
    },
    captureFps,
    firstContentFrame,
    firstContentTimestampMs: frames[firstContentFrame].timestampMs,
    frameCount: frames.length,
    internal: {
      firstContentTimestampMs,
      switchContentTimestampMs,
      switchStartedTimestampMs,
      topContentTimestampMs,
      topStartedTimestampMs,
      windowShownTimestampMs,
    },
    launchTimestampMs,
    match: {
      changedPixelThreshold,
      contentMaximumChangedRatio,
      contentRegion: transcriptRegion,
      stableFrames,
      windowMinimumChangedRatio: windowChangeThreshold,
    },
    observedFrameIntervalMs: {
      median: percentile(frameIntervals, 0.5),
      p90: percentile(frameIntervals, 0.9),
    },
    switchContentFrame,
    switchContentTimestampMs: frames[switchContentFrame].timestampMs,
    topContentFrame,
    topContentTimestampMs: frames[topContentFrame].timestampMs,
    video: relative(resultsRoot, artifactPath),
    window: windowInfo,
    windowOpenFrame,
    windowOpenTimestampMs: frames[windowOpenFrame].timestampMs,
  };
  writeFileSync(
    artifactPath.replace(/\.mp4$/, ".frames.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
  return evidence;
}
