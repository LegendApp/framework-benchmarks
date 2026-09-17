import { expect, test } from "bun:test";
import { verifyRenderingInputs, type RenderingInputs } from "./fairness";

const record = (): RenderingInputs => ({
  contractSha256: "policy-v1", highlightingPolicySha256: "languages-v1",
  legendList: { version: "same-version", artifacts: { "react.js": "a", "react.mjs": "b", "react.d.ts": "c" } },
});

test("rejects different bundled implementations even under the same version", () => {
  const changed = record();
  changed.legendList!.artifacts["react.mjs"] = "locally-patched";
  expect(() => verifyRenderingInputs({ "react-native": record(), electron: changed })).toThrow("snapshot differs");
});
test("rejects missing and inconsistent policy provenance", () => {
  expect(() => verifyRenderingInputs({ appkit: undefined })).toThrow("Missing");
  expect(() => verifyRenderingInputs({ appkit: record(), swiftui: { ...record(), highlightingPolicySha256: "other" } })).toThrow("policy differs");
});
test("accepts native engines with matching policy and matching shared list artifacts", () => {
  expect(() => verifyRenderingInputs({ "react-native": record(), electron: record(), appkit: { ...record(), legendList: undefined } })).not.toThrow();
});
