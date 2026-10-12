import { main } from "../cli";
try { await main("run", ["--suite", "chat-history", ...process.argv.slice(2)]); } catch (error) { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; }
