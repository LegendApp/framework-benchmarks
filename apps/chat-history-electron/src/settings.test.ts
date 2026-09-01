import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defaultChatHistorySettings, normalizeChatHistorySettings } from "./model";
import { readSettings, writeSettings } from "./settings";

test("normalizes and persists Electron settings", async () => {
  const userDataPath = await mkdtemp(join(tmpdir(), "legend-electron-settings-"));
  try {
    expect(await readSettings(userDataPath)).toEqual(defaultChatHistorySettings);
    const settings = normalizeChatHistorySettings({
      appearance: "dark",
      loadImages: false,
      recentChatLimit: 100,
      restoreSelection: false,
      selectedId: "codex:example",
      showPerformanceMetrics: false,
    });
    await writeSettings(userDataPath, settings);
    expect(await readSettings(userDataPath)).toEqual(settings);
    expect(JSON.parse(await readFile(join(userDataPath, "settings.json"), "utf8"))).toEqual(settings);
  } finally {
    await rm(userDataPath, { force: true, recursive: true });
  }
});

test("replaces invalid settings with stable defaults", () => {
  expect(normalizeChatHistorySettings({ appearance: "sepia", recentChatLimit: 500 })).toEqual(defaultChatHistorySettings);
});
