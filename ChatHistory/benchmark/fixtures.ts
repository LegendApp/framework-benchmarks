import { createHash } from "node:crypto";
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { basename, resolve } from "node:path";
import { pipeline } from "node:stream/promises";
import { createGunzip } from "node:zlib";
import type { BenchmarkFixtureManifest } from "../apps/chat-history-electron/src/model";

const fixtureRoot = resolve(import.meta.dir, "../fixtures");

async function fixtureHash(path: string) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

/** Expand published samples outside measurement; no user history is copied. */
export async function prepareFixtures() {
  const destination = resolve(import.meta.dir, "../../.build/chat-history-fixtures");
  const manifest = JSON.parse(readFileSync(resolve(fixtureRoot, "manifest.json"), "utf8")) as BenchmarkFixtureManifest;
  if (manifest.version !== 2 || manifest.fixtures.length < 2) throw new Error("Unsupported sample fixture manifest");
  const fixtures = [];
  for (const fixture of manifest.fixtures) {
    const source = resolve(fixtureRoot, fixture.path);
    const compressed = source.endsWith(".gz");
    const path = compressed ? resolve(destination, basename(source, ".gz")) : source;
    let valid = existsSync(path) && statSync(path).size === fixture.sourceBytes
      && await fixtureHash(path) === fixture.sha256;
    if (compressed && !valid) {
      mkdirSync(destination, { recursive: true });
      await pipeline(createReadStream(source), createGunzip(), createWriteStream(path));
      valid = statSync(path).size === fixture.sourceBytes && await fixtureHash(path) === fixture.sha256;
    }
    if (!valid) {
      throw new Error(`Sample fixture size or hash changed: ${fixture.path}`);
    }
    fixtures.push({ ...fixture, path });
  }
  return { ...manifest, fixtures };
}
