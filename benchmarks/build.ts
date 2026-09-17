import { main } from "./cli";
try { await main("build"); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
