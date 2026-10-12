import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import {
  defaultChatHistorySettings,
  normalizeChatHistorySettings,
  type ChatHistorySettings,
} from "./model";

const settingsFileName = "settings.json";

export async function readSettings(userDataPath: string) {
  try {
    return normalizeChatHistorySettings(JSON.parse(await readFile(join(userDataPath, settingsFileName), "utf8")));
  } catch {
    return { ...defaultChatHistorySettings };
  }
}

export async function writeSettings(userDataPath: string, settings: ChatHistorySettings) {
  const path = join(userDataPath, settingsFileName);
  const temporaryPath = `${path}.tmp`;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(temporaryPath, `${JSON.stringify(normalizeChatHistorySettings(settings), null, 2)}\n`, "utf8");
  await rename(temporaryPath, path);
}
