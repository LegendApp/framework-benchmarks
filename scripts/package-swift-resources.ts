import { cpSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

export function copySwiftResources(appRoot: string, outputApp: string) {
  const release = resolve(appRoot, ".build/release");
  for (const entry of readdirSync(release)) {
    if (entry.endsWith(".bundle")) cpSync(resolve(release, entry), resolve(outputApp, "Contents/Resources", entry), { recursive: true });
  }
}
