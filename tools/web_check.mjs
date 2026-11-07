// Boots the web build in headless Chrome and verifies the game starts.
// Usage: node tools/web_check.mjs [url] [out.png] [timeout_sec]
// Exit 0 when the console shows "Main scene ready" (printed by scenes/main), 1 otherwise.
// Requires Node >= 22 (built-in WebSocket) and google-chrome. No npm packages.
import { spawn } from "node:child_process";
import { writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const url = process.argv[2] || "http://localhost:8000/index.html";
const out = process.argv[3] || "shots/web.png";
const timeoutSec = Number(process.argv[4] || 90);
const MARKER = "Main scene ready";
const port = 9300 + Math.floor(Math.random() * 500);

const chrome = spawn("google-chrome", [
  "--headless=new", "--no-sandbox", "--no-first-run", "--disable-gpu-sandbox",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
  "--window-size=1280,720", `--remote-debugging-port=${port}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), "ik-chrome-"))}`, "about:blank",
], { stdio: ["ignore", "ignore", "ignore"] });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = false;
const errors = [];

async function main() {
  let targets;
  for (let i = 0; i < 50; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); break; }
    catch { await sleep(200); }
  }
  const page = targets.find((t) => t.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  let id = 0;
  const pending = new Map();
  const send = (method, params = {}) => new Promise((resolve) => {
    const msgId = ++id; pending.set(msgId, resolve);
    ws.send(JSON.stringify({ id: msgId, method, params }));
  });
  ws.addEventListener("message", (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result || msg.error); pending.delete(msg.id); }
    if (msg.method === "Runtime.consoleAPICalled") {
      const text = msg.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
      console.log(`[console.${msg.params.type}] ${text}`);
      if (msg.params.type === "error") errors.push(text);
      if (text.includes(MARKER)) ok = true;
    }
    if (msg.method === "Runtime.exceptionThrown") {
      const d = msg.params.exceptionDetails;
      const text = d.exception?.description || d.text;
      console.log(`[exception] ${text}`); errors.push(text);
    }
  });
  await send("Runtime.enable");
  await send("Page.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
  await send("Page.navigate", { url });
  const t0 = Date.now();
  while (!ok && Date.now() - t0 < timeoutSec * 1000) await sleep(500);
  if (ok) await sleep(2000); // let a few frames render
  const shot = await send("Page.captureScreenshot", { format: "png" });
  if (shot && shot.data) { writeFileSync(out, Buffer.from(shot.data, "base64")); console.log(`screenshot: ${out}`); }
  console.log(ok ? `WEB OK: game booted in ${((Date.now() - t0) / 1000).toFixed(1)}s` : `WEB FAIL: "${MARKER}" not seen in ${timeoutSec}s`);
  ws.close();
}

main().catch((e) => { console.error(e); }).finally(() => { chrome.kill("SIGKILL"); process.exit(ok ? 0 : 1); });
