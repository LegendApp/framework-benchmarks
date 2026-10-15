import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { prepareFixtures } from "./fixtures";

const manifest = await prepareFixtures();
const outputPath = resolve(import.meta.dir, "fixtures.local.json");
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
for (const fixture of manifest.fixtures) {
  console.log(`${fixture.title}: ${(fixture.sourceBytes / 1_048_576).toFixed(2)} MiB`);
}
console.log(outputPath);
