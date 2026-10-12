import { describe, expect, test } from "bun:test";
import { changedRatio, firstStableFrame } from "../../shared/video";
import { regionFeature } from "./video";

const width = 100;
const height = 100;
function pixels() { return new Uint8Array(width * height * 3); }
function paint(data: Uint8Array, left: number, top: number, right: number, bottom: number) {
  for (let y = top; y < bottom; y += 1) {
    for (let x = left; x < right; x += 1) data.fill(255, (y * width + x) * 3, (y * width + x + 1) * 3);
  }
}

describe("transcript visual readiness", () => {
  test("sidebar scrollbar fade cannot delay unchanged transcript content", () => {
    const settled = pixels();
    const scrollbar = pixels();
    paint(scrollbar, 17, 20, 19, 80);
    expect(changedRatio(scrollbar, settled, 0.07)).toBeGreaterThan(0.004);
    expect(changedRatio(regionFeature(scrollbar, width, height), regionFeature(settled, width, height))).toBe(0);
  });
  test("missing or moving transcript text still prevents readiness", () => {
    const loaded = pixels();
    paint(loaded, 30, 25, 80, 27);
    expect(changedRatio(regionFeature(pixels(), width, height), regionFeature(loaded, width, height))).toBeGreaterThan(0.004);
  });
  test("content must match for three consecutive captured frames", () => {
    const settled = pixels();
    const moving = pixels();
    paint(moving, 30, 25, 80, 27);
    const frames = [settled, settled, moving, settled, settled, settled].map((feature, index) => ({
      feature: regionFeature(feature, width, height), width, height, timestampMs: index * 10,
    }));
    const reference = regionFeature(settled, width, height);
    expect(firstStableFrame(frames, 0, 50, (frame) => changedRatio(frame.feature, reference) <= 0.004)).toBe(3);
    expect(firstStableFrame(frames, 0, 40, (frame) => changedRatio(frame.feature, reference) <= 0.004)).toBe(-1);
  });
});
