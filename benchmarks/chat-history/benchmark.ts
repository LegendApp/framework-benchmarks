import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const build = resolve(import.meta.dir, "build.ts");
const run = resolve(import.meta.dir, "run.ts");
const args = process.argv.slice(2);

for (const script of [build, run]) {
  const result = spawnSync("bun", [script, ...args], {
    env: process.env,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}
