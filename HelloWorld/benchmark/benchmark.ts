import { main } from "../../shared/benchmark/cli";
try { await main("run", ["--suite", "hello-world", ...process.argv.slice(2)]); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
