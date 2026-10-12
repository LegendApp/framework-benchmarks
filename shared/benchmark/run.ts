import { main } from "./cli";
try { await main("run"); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
