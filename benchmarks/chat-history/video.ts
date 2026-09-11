import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, relative } from "node:path";

type Rect = { height: number; width: number; x: number; y: number };

export type WindowInfo = {
  display: Rect;
  window: Rect;
  windowID: number;
};

type Frame = {
  feature: Uint8Array;
  width: number;
  height: number;
  timestampMs: number;
};

type Recording = {
  child: ChildProcess;
  errorOutput: string;
  output: string;
  timestampPath: string;
};

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

const captureFps = 60;
const analysisWidth = 320;
const changedPixelThreshold = 12;
const contentMaximumChangedRatio = 0.004;
const stableFrames = 3;
const windowMinimumChangedRatio = 0.01;

function waitForExit(child: ChildProcess, timeoutMs: number) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve();
  }
  return new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      child.off("exit", handleExit);
      reject(new Error("Timed out waiting for screen recorder"));
    }, timeoutMs);
    const handleExit = (code: number | null, signal: NodeJS.Signals | null) => {
      clearTimeout(timeout);
      if (code === 0 || signal === "SIGTERM") {
        resolve();
      } else {
        reject(new Error(`Screen recorder exited with ${code ?? signal}`));
      }
    };
    child.once("exit", handleExit);
  });
}

function waitForOutput(recording: Recording, pattern: RegExp, timeoutMs = 10_000) {
  if (pattern.test(recording.output)) {
    return Promise.resolve();
  }
  return new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      recording.child.stdout?.off("data", handleData);
      recording.child.off("exit", handleExit);
      reject(new Error(
        `Screen recorder did not emit ${pattern}\n${recording.errorOutput}`,
      ));
    }, timeoutMs);
    const handleData = () => {
      if (pattern.test(recording.output)) {
        clearTimeout(timeout);
        recording.child.stdout?.off("data", handleData);
        recording.child.off("exit", handleExit);
        resolve();
      }
    };
    const handleExit = (code: number | null) => {
      clearTimeout(timeout);
      recording.child.stdout?.off("data", handleData);
      reject(new Error(
        `Screen recorder exited before ${pattern} (${code})\n${recording.errorOutput}`,
      ));
    };
    recording.child.stdout?.on("data", handleData);
    recording.child.once("exit", handleExit);
  });
}

export async function startRecording(path: string, executable: string): Promise<Recording> {
  mkdirSync(dirname(path), { recursive: true });
  const timestampPath = path.replace(/\.mp4$/, ".capture.json");
  const child = spawn(executable, [path, timestampPath], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  const recording: Recording = { child, errorOutput: "", output: "", timestampPath };
  child.stdout?.on("data", (chunk: Buffer) => { recording.output += chunk.toString(); });
  child.stderr?.on("data", (chunk: Buffer) => { recording.errorOutput += chunk.toString(); });
  child.once("exit", (code) => {
    if (code && !recording.errorOutput) {
      recording.errorOutput = `Screen recorder exited with ${code}`;
    }
  });
  try {
    await waitForOutput(recording, /"ready":true/);
  } catch (error) {
    recording.child.kill("SIGTERM");
    await waitForExit(recording.child, 5_000).catch(() => undefined);
    throw error;
  }
  return recording;
}

export async function targetRecording(recording: Recording, pid: number) {
  recording.child.stdin?.write(`pid ${pid}\n`);
  await waitForOutput(recording, new RegExp(`"targetReady":true,"pid":${pid}`));
}

export async function stopRecording(recording: Recording) {
  recording.child.stdin?.write("q\n");
  recording.child.stdin?.end();
  await waitForExit(recording.child, 15_000);
}

export function probeVideo(path: string, timestampPath: string) {
  const output = execFileSync("ffprobe", [
    "-v", "error",
    "-select_streams", "v:0",
    "-show_entries", "stream=width,height,nb_frames",
    "-of", "json",
    path,
  ], { encoding: "utf8", maxBuffer: 64 * 1_024 * 1_024 });
  const result = JSON.parse(output) as {
    streams: { height: number; nb_frames: string; width: number }[];
  };
  const timestamps = JSON.parse(readFileSync(timestampPath, "utf8")) as {
    captureFps: number;
    frameTimestampsMs: number[];
  };
  const stream = result.streams[0];
  if (!stream || timestamps.frameTimestampsMs.length === 0) {
    throw new Error(`Screen recording has no video frames: ${path}`);
  }
  if (Math.abs(Number(stream.nb_frames) - timestamps.frameTimestampsMs.length) > 2) {
    throw new Error(
      `Screen recording has ${stream.nb_frames} frames but ${timestamps.frameTimestampsMs.length} timestamps`,
    );
  }
  return {
    height: stream.height,
    timestampsMs: timestamps.frameTimestampsMs,
    width: stream.width,
  };
}

function even(value: number) {
  const rounded = Math.max(2, Math.round(value));
  return rounded % 2 === 0 ? rounded : rounded - 1;
}

export function videoWindow(windowInfo: WindowInfo, videoWidth: number, videoHeight: number) {
  const horizontalScale = videoWidth / windowInfo.display.width;
  const verticalScale = videoHeight / windowInfo.display.height;
  const x = Math.max(0, Math.round((windowInfo.window.x - windowInfo.display.x) * horizontalScale));
  const y = Math.max(0, Math.round((windowInfo.window.y - windowInfo.display.y) * verticalScale));
  return {
    height: Math.min(videoHeight - y, even(windowInfo.window.height * verticalScale)),
    width: Math.min(videoWidth - x, even(windowInfo.window.width * horizontalScale)),
    x,
    y,
  };
}

export function extractFeatures(
  path: string,
  sourceWidth: number,
  sourceHeight: number,
  timestampsMs: number[],
  windowRect: Rect,
) {
  const height = even(sourceHeight * analysisWidth / sourceWidth);
  const scaleX = analysisWidth / sourceWidth;
  const scaleY = height / sourceHeight;
  const crop = {
    height: Math.max(1, Math.floor(windowRect.height * scaleY)),
    width: Math.max(1, Math.floor(windowRect.width * scaleX)),
    x: Math.floor(windowRect.x * scaleX),
    y: Math.floor(windowRect.y * scaleY),
  };
  const rowBytes = analysisWidth * 3;
  const frameBytes = rowBytes * height;
  const child = spawn("ffmpeg", [
    "-v", "error",
    "-i", path,
    "-vf", `scale=${analysisWidth}:${height}:flags=fast_bilinear`,
    "-fps_mode", "passthrough",
    "-pix_fmt", "rgb24",
    "-f", "rawvideo",
    "pipe:1",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  return new Promise<Frame[]>((resolve, reject) => {
    const frames: Frame[] = [];
    let pending: Buffer<ArrayBufferLike> = Buffer.alloc(0);
    let errorOutput = "";
    child.stderr.on("data", (chunk: Buffer) => { errorOutput += chunk.toString(); });
    child.stdout.on("data", (chunk: Buffer) => {
      pending = pending.length === 0 ? chunk : Buffer.concat([pending, chunk]);
      while (pending.length >= frameBytes) {
        const pixels = pending.subarray(0, frameBytes);
        pending = pending.subarray(frameBytes);
        const feature = new Uint8Array(crop.width * crop.height * 3);
        let output = 0;
        for (let row = 0; row < crop.height; row += 1) {
          const start = (crop.y + row) * rowBytes + crop.x * 3;
          feature.set(pixels.subarray(start, start + crop.width * 3), output);
          output += crop.width * 3;
        }
        const timestampMs = timestampsMs[frames.length];
        if (timestampMs !== undefined) {
          frames.push({ feature, width: crop.width, height: crop.height, timestampMs });
        }
      }
    });
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code !== 0) {
        reject(new Error(`Could not decode screen recording (${code})\n${errorOutput}`));
      } else if (Math.abs(frames.length - timestampsMs.length) > 2) {
        reject(new Error(`Decoded ${frames.length} frames but probed ${timestampsMs.length}`));
      } else {
        resolve(frames);
      }
    });
  });
}

export function nearestFrame(frames: Frame[], timestampMs: number) {
  let best = 0;
  for (let index = 1; index < frames.length; index += 1) {
    if (Math.abs(frames[index].timestampMs - timestampMs)
      < Math.abs(frames[best].timestampMs - timestampMs)) {
      best = index;
    }
  }
  return best;
}

function percentile(values: number[], quantile: number) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * quantile) - 1)];
}

export function changedRatio(left: Uint8Array, right: Uint8Array, topFraction = 0) {
  if (left.length !== right.length) {
    throw new Error("Video frame features have different dimensions");
  }
  const start = Math.floor(left.length * topFraction / 3) * 3;
  let changed = 0;
  let pixels = 0;
  for (let index = start; index < left.length; index += 3) {
    const delta = (
      Math.abs(left[index] - right[index])
      + Math.abs(left[index + 1] - right[index + 1])
      + Math.abs(left[index + 2] - right[index + 2])
    ) / 3;
    if (delta >= changedPixelThreshold) {
      changed += 1;
    }
    pixels += 1;
  }
  return changed / pixels;
}

export function firstStableFrame(
  frames: Frame[],
  startTimestampMs: number,
  endTimestampMs: number,
  matches: (frame: Frame) => boolean,
) {
  let run = 0;
  for (let index = 0; index < frames.length; index += 1) {
    const frame = frames[index];
    if (frame.timestampMs < startTimestampMs || frame.timestampMs > endTimestampMs) {
      run = 0;
      continue;
    }
    run = matches(frame) ? run + 1 : 0;
    if (run >= stableFrames) {
      return index - stableFrames + 1;
    }
  }
  return -1;
}

export function cropVideo(source: string, destination: string, rect: Rect) {
  mkdirSync(dirname(destination), { recursive: true });
  execFileSync("ffmpeg", [
    "-v", "error",
    "-i", source,
    "-vf", `crop=${rect.width}:${rect.height}:${rect.x}:${rect.y},setpts=PTS-STARTPTS`,
    "-an",
    "-fps_mode", "passthrough",
    "-c:v", "h264_videotoolbox",
    "-q:v", "65",
    "-movflags", "+faststart",
    "-y",
    destination,
  ]);
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
