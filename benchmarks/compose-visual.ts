/** Synthetic visual/lifecycle regression. Build and run the standard harness once
 * first so its signed capture/launch helpers exist. This is not a timing score. */
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import { installRuntimeGrammarPacks } from "./chat-history/grammar-packs";
const root = resolve(import.meta.dir, "..");
const appearance = process.argv[2] ?? "dark";
if (!["dark", "light"].includes(appearance)) throw new Error("Expected dark or light");
const output = resolve(root, `benchmarks/chat-history/results/compose-visual-${Date.now()}-${appearance}`);
const home = resolve(homedir(), "Library/Caches/so.legend.desktop-benchmarks/compose-visual-home");
const sessions = resolve(home, ".codex/sessions");
mkdirSync(sessions, { recursive: true }); mkdirSync(output, { recursive: true });
const ids = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"];
const long = readFileSync(resolve(root, "docs/report-assets/long-chat-fixture.md"), "utf8");
const rich = "# Rich Markdown\n\n**Bold**, *italic*, ~~strike~~ and [a link](https://example.com).\n\n- [x] task\n- another item\n  - nested item\n\n> A quote with **formatting**.\n\n| Name | Value |\n| --- | --- |\n| answer | `42` |\n\n```swift\nlet message = \"Hello\"\nfunc greet() -> String { return message }\n```\n\n```ruby\ndef greet(name)\n  puts \"Hello #{name}\"\nend\n```";
for (let i = 0; i < ids.length; i++) {
  const records = [{ type: "session_meta", payload: { id: ids[i], cwd: "/visual-proof" } },
    ...Array.from({ length: i ? 1 : 25 }, () => ({ type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: i ? rich : long }] } }))];
  writeFileSync(resolve(sessions, `rollout-${ids[i]}.jsonl`), records.map(r => JSON.stringify(r)).join("\n") + "\n");
}
const config = resolve(home, `config-${Date.now()}.json`), events = resolve(home, `events-${Date.now()}.jsonl`);
writeFileSync(config, JSON.stringify({ version: 2, appearance, loadImages: false, topDelayMs: 2000, switchDelayMs: 2000, targets: ids.map(id => ({ provider: "codex", id: `codex:${id}` })) }));
const base = resolve(root, ".build/chat-history-benchmarks");
const capture = spawn(resolve(base, "Chat History Benchmark Capture.app/Contents/MacOS/ChatHistoryCapture"), [resolve(output, "compose.mp4"), resolve(output, "capture.json")], { stdio: ["pipe", "pipe", "pipe"] });
const closed = new Promise<void>((done, reject) => { capture.once("error", reject); capture.once("close", code => code ? reject(new Error(`Capture failed: ${code}`)) : done()); });
let pid: number | undefined;
try {
  await new Promise<void>((done, reject) => { capture.stdout.once("data", () => done()); capture.once("error", reject); capture.once("exit", code => reject(new Error(`Capture exited early: ${code}`))); });
  const launch = JSON.parse(execFileSync(resolve(base, "chat-history-launch-app"), [resolve(base, "Chat History — Compose Multiplatform.app")], {
    encoding: "utf8", timeout: 30000, env: { ...process.env, CHAT_HISTORY_BENCHMARK_CONFIG: config, CHAT_HISTORY_BENCHMARK_HOME: home, CHAT_HISTORY_BENCHMARK_EVENTS: events, BENCHMARK_GRAMMAR_ROOT: installRuntimeGrammarPacks(root, ["compose"]) },
  }));
  pid = launch.pid; capture.stdin.write(`pid ${pid}\n`);
  const deadline = Date.now() + 30000;
  while (true) {
    const rows = existsSync(events) ? readFileSync(events, "utf8").trim().split("\n").filter(Boolean).map(s => JSON.parse(s)) : [];
    if (rows.some(r => r.name === "contentReady" && r.phase === "switch")) {
      if (!rows.some(r => r.name === "viewportReady" && r.phase === "top")) throw new Error("Missing top viewport");
      writeFileSync(resolve(output, "window.json"), execFileSync(resolve(base, "chat-history-window-info"), [String(pid)]));
      await Bun.sleep(1500); break;
    }
    if (Date.now() > deadline) throw new Error(`No switch content: ${JSON.stringify(rows)}`);
    await Bun.sleep(100);
  }
  writeFileSync(resolve(output, "events.jsonl"), readFileSync(events));
  writeFileSync(resolve(output, "config.json"), readFileSync(config));
  console.log(`PASS ${appearance}: ${output}`);
} finally {
  capture.stdin.write("q\n");
  await Promise.race([closed, Bun.sleep(10000).then(() => { capture.kill("SIGTERM"); })]);
  if (pid) { try { process.kill(pid, "SIGTERM"); } catch {} }
}
