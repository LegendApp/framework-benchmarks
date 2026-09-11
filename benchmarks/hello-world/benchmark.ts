import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

for (const script of ["build.ts", "run.ts"]) {
  const result = spawnSync("bun", [resolve(import.meta.dir, script), ...process.argv.slice(2)], { env: process.env, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
