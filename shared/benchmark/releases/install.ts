import { existsSync, mkdirSync, renameSync, rmSync } from "node:fs";
import { dirname, resolve } from "node:path";

// All replacements are already verified and staged on the same filesystem.
// Roll back both bundles and manifests if any rename fails.
export function installTransaction(items: { staged: string; destination: string }[], backupRoot: string) {
  const journal: { destination: string; backup: string; backedUp: boolean; installed: boolean }[] = [];
  mkdirSync(backupRoot, { recursive: true });
  try {
    for (const [index, item] of items.entries()) {
      mkdirSync(dirname(item.destination), { recursive: true });
      const entry = { destination: item.destination, backup: resolve(backupRoot, String(index)), backedUp: false, installed: false };
      journal.push(entry);
      if (existsSync(item.destination)) { renameSync(item.destination, entry.backup); entry.backedUp = true; }
      renameSync(item.staged, item.destination); entry.installed = true;
    }
  } catch (error) {
    for (const entry of journal.reverse()) {
      if (entry.installed) rmSync(entry.destination, { recursive: true, force: true });
      if (entry.backedUp) renameSync(entry.backup, entry.destination);
    }
    throw error;
  }
}
