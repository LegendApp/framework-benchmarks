import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { prepareGrammarPack, sealGrammarPack } from "../../benchmarks/chat-history/grammar-packs";
const root = resolve(import.meta.dir, "../..");
const suite = process.argv[2];
if (suite !== "chat-history" && suite !== "hello-world") throw new Error("Expected chat-history or hello-world");
const chat = suite === "chat-history";
if (chat) prepareGrammarPack(root, "compose-syntax");
execFileSync("python3", ["scripts/compose-guard.py", "scripts/with-local-compose.sh", ...(chat ? [":chat:createReleaseDistributable", ":syntax:exportPack"] : [":hello:createReleaseDistributable"])], { cwd: root, stdio: "inherit" });
if (chat) {
  const pack = resolve(root, ".build/chat-history-benchmarks/grammar-packs/v1/compose-syntax");
  cpSync(resolve(root, "benchmarks/chat-history/syntax-highlighting-policy.json"), resolve(pack, "policy.json"));
  sealGrammarPack(pack, "compose-syntax");
}
const name = chat ? "ChatHistoryCompose" : "HelloWorldCompose";
const source = resolve(root, `apps/${suite}-compose/build/compose/binaries/main-release/app/${name}.app`);
if (!existsSync(source)) throw new Error(`Missing release bundle: ${source}`);
const output = resolve(root, `.build/${suite}-benchmarks/${chat ? "Chat History" : "Hello World"} — Compose Multiplatform.app`);
mkdirSync(resolve(output, ".."), { recursive: true });
rmSync(output, { recursive: true, force: true });
execFileSync("ditto", [source, output]);
for (const key of ["CFBundleDisplayName", "CFBundleName"]) execFileSync("plutil", ["-replace", key, "-string", `${chat ? "Chat History" : "Hello World"} — Compose Multiplatform`, resolve(output, "Contents/Info.plist")]);
execFileSync("codesign", ["--force", "--deep", "--sign", "-", output]);
console.log(output);
