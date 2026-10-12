import { app, BrowserWindow } from "electron";
import { join } from "node:path";

app.whenReady().then(async () => {
  const window = new BrowserWindow({
    width: 1280,
    height: 720,
    useContentSize: true,
    title: "Hello World — Electron",
    backgroundColor: "#ffffff",
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false },
  });
  await window.loadFile(join(import.meta.dirname, "index.html"));
});
app.on("window-all-closed", () => app.quit());
