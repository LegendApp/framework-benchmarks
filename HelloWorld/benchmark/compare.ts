import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { labels, option, type AppName } from "./config";

type Result = { app: AppName; buildSizeBytes: number; grammarPackBytes?: number; combinedInstalledBytes?: number; median: { firstContentMs: number; physicalFootprintBytes?: number; initialMemory?: { physicalFootprintBytes: number } } };
type Report = { workload?: string; measuredAt: string; iterations?: number; warmups?: number; results?: Result[]; apps?: Result[]; protocol?: { visualAuthority?: string }; methodology?: { video?: string }; video?: boolean };
const productPath = option("--product");
const helloPath = option("--hello-world");
if (!productPath || !helloPath) throw new Error("Usage: bun run benchmark:compare --product <product-results.json> --hello-world <hello-world-results.json> [--output comparison.md]");
const product: Report = JSON.parse(readFileSync(resolve(productPath), "utf8"));
const hello: Report = JSON.parse(readFileSync(resolve(helloPath), "utf8"));
if (hello.workload !== "hello-world") throw new Error("--hello-world must be a Hello World benchmark report");
if (product.workload === "hello-world") throw new Error("--product must be a chat product benchmark report");
if (!Array.isArray(product.apps) || !Array.isArray(hello.results)) throw new Error("Expected benchmark results arrays");
if (!product.protocol?.visualAuthority?.startsWith("Timestamped")) throw new Error("Product report must use video-derived visual timing, not --no-video diagnostics");
const mb = (value: number | undefined) => value === undefined || !Number.isFinite(value) ? "n/a" : (value / 1048576).toFixed(1);
const ms = (value: number | undefined) => value === undefined || !Number.isFinite(value) ? "n/a" : value.toFixed(1);
const lines = [
  "# Hello World and full product comparison", "",
  `Hello World measured: ${hello.measuredAt} (${hello.iterations ?? "unknown"} iterations, ${hello.warmups ?? "unknown"} warmups). Full product measured: ${product.measuredAt} (${product.iterations ?? "unknown"} iterations, ${product.warmups ?? "unknown"} warmups).`, "",
  "Each pair is **Hello World / full product**. Startup and footprint are medians. The product startup includes catalog discovery and the initial large transcript; the baseline renders one label. Differences describe these workloads, not an isolated estimate of framework overhead.", "",
  "| Runtime | First content ms | Physical footprint MiB | App MiB | Product grammar MiB | Product combined MiB |",
  "| --- | ---: | ---: | ---: | ---: | ---: |",
];
for (const blank of hello.results!) {
  const full = product.apps!.find((row) => row.app === blank.app);
  lines.push(`| ${labels[blank.app] ?? blank.app} | ${ms(blank.median.firstContentMs)} / ${ms(full?.median.firstContentMs)} | ${mb(blank.median.physicalFootprintBytes)} / ${mb(full?.median.initialMemory?.physicalFootprintBytes)} | ${mb(blank.buildSizeBytes)} / ${mb(full?.buildSizeBytes)} | ${mb(full?.grammarPackBytes)} | ${mb(full?.combinedInstalledBytes)} |`);
}
lines.push("", "Use source reports from the same machine and comparable release builds, display conditions, and video timing mode. Missing product rows are shown as n/a. Parsing, jump, and switch results remain in the product report.", "");
const markdown = lines.join("\n");
const output = option("--output");
if (output) writeFileSync(resolve(output), markdown);
console.log(markdown);
