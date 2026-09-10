#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as sleep } from "node:timers/promises";
import { chromium } from "playwright-core";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PORT = 4010;
const DEFAULT_CDP_PORT = 5010;
const EMAIL = "verify@example.com";
const PASSWORD = "verify-pass-12";

function findRepoRoot(start) {
  let dir = start;
  for (let i = 0; i < 8; i++) {
    if (existsSync(join(dir, "mix.exs"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("could not find mix.exs above the harness");
}

const REPO = findRepoRoot(SCRIPT_DIR);
const RUN_DIR = join(REPO, "tmp/verify-pinventory/run");
const ARTIFACTS_DIR = join(REPO, "tmp/verify-pinventory/artifacts");
const STATE_PATH = join(RUN_DIR, "state.json");

function usage() {
  return `verify-pinventory <command>

Launch / health / teardown:
  launch [--port N] [--cdp-port N]
  doctor
  cleanup

Browser (Chromium over CDP, persistent until cleanup):
  browser login
  browser goto <path>
  browser click <selector>
  browser click-at <selector> <x> <y>
  browser click-box <selector> <fx> <fy>
  browser box <selector>
  browser hover <selector>
  browser fill <selector> <value>
  browser press <key>
  browser wait <selector>
  browser wait-attached <selector>
  browser wait-enabled <selector>
  browser enabled <selector>
  browser text <selector>
  browser exists <selector>
  browser attr <selector> <name>
  browser count <selector>
  browser screenshot <relpath>
  browser html <relpath>

Database:
  sqlite <sql>
`;
}

function loadState() {
  if (!existsSync(STATE_PATH)) {
    throw new Error(`no verification run at ${STATE_PATH}; run launch`);
  }
  return JSON.parse(readFileSync(STATE_PATH, "utf8"));
}

function saveState(state) {
  mkdirSync(RUN_DIR, { recursive: true });
  writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + "\n");
}

function pidAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function listeningPid(port) {
  const result = spawnSync("ss", ["-ltnp", `sport = :${port}`], {
    encoding: "utf8",
  });
  const match = (result.stdout || "").match(/pid=(\d+)/);
  return match ? Number(match[1]) : null;
}

function runMix(args, env) {
  const result = spawnSync("mix", args, {
    cwd: REPO,
    env: { ...process.env, MIX_ENV: "dev", ...env },
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(
      `mix ${args.join(" ")} failed:\n${result.stdout}\n${result.stderr}`,
    );
  }
  return result.stdout;
}

function findChrome() {
  if (process.env.PINVENTORY_CHROME && existsSync(process.env.PINVENTORY_CHROME)) {
    return process.env.PINVENTORY_CHROME;
  }
  const cache = join(homedir(), ".cache/ms-playwright");
  if (existsSync(cache)) {
    for (const name of readdirSync(cache)) {
      if (!name.startsWith("chromium-")) continue;
      const candidate = join(cache, name, "chrome-linux64", "chrome");
      if (existsSync(candidate)) return candidate;
    }
  }
  if (existsSync("/usr/bin/chromium")) return "/usr/bin/chromium";
  throw new Error("no Chromium binary; set PINVENTORY_CHROME or install Chromium");
}

async function httpCode(url) {
  try {
    const res = await fetch(url, { redirect: "manual" });
    return res.status;
  } catch {
    return 0;
  }
}

async function waitFor(fn, { timeoutMs, intervalMs, label }) {
  const start = Date.now();
  let lastErr;
  while (Date.now() - start < timeoutMs) {
    try {
      const value = await fn();
      if (value) return value;
    } catch (err) {
      lastErr = err;
      if (String(err.message).includes("exited")) throw err;
    }
    await sleep(intervalMs);
  }
  const extra = lastErr ? `\n${lastErr.message}` : "";
  throw new Error(`timed out waiting for ${label}${extra}`);
}

function spawnDetached(command, args, { logPath, env, cwd }) {
  mkdirSync(dirname(logPath), { recursive: true });
  const logFd = openSync(logPath, "a");
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, ...env },
    detached: true,
    stdio: ["ignore", logFd, logFd],
  });
  child.unref();
  return child.pid;
}

function killGroup(pid) {
  if (!pid || !pidAlive(pid)) return;
  try {
    process.kill(-pid, "SIGTERM");
  } catch {
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      /* already gone */
    }
  }
}

function forceKillGroup(pid) {
  if (!pid || !pidAlive(pid)) return;
  try {
    process.kill(-pid, "SIGKILL");
  } catch {
    try {
      process.kill(pid, "SIGKILL");
    } catch {
      /* already gone */
    }
  }
}

async function cmdLaunch(flags) {
  const port = Number(flags.port || DEFAULT_PORT);
  const cdpPort = Number(flags["cdp-port"] || DEFAULT_CDP_PORT);

  if (existsSync(STATE_PATH)) {
    try {
      const existing = loadState();
      if (
        pidAlive(existing.serverPid) &&
        (await httpCode(`${existing.url}/user/log-in`)) === 200
      ) {
        throw new Error(
          `a verification instance is already running at ${existing.url} (pid ${existing.serverPid}). Run cleanup first.`,
        );
      }
    } catch (err) {
      if (String(err.message).includes("already running")) throw err;
    }
    rmSync(RUN_DIR, { recursive: true, force: true });
  }

  const owner = listeningPid(port);
  if (owner) {
    throw new Error(
      `port ${port} is already in use by pid ${owner}. Pick another --port or stop that process. Never drive :4000.`,
    );
  }
  const cdpOwner = listeningPid(cdpPort);
  if (cdpOwner) {
    throw new Error(`CDP port ${cdpPort} is already in use by pid ${cdpOwner}`);
  }

  mkdirSync(RUN_DIR, { recursive: true });
  mkdirSync(ARTIFACTS_DIR, { recursive: true });
  const databasePath = join(RUN_DIR, "pinventory.db");
  const env = {
    PORT: String(port),
    DATABASE_PATH: databasePath,
    MIX_ENV: "dev",
  };

  runMix(["ecto.create"], env);
  runMix(["ecto.migrate"], env);
  runMix(["pinventory.user", EMAIL, PASSWORD], env);

  const serverLog = join(RUN_DIR, "server.log");
  const serverPid = spawnDetached("mix", ["phx.server"], {
    logPath: serverLog,
    env,
    cwd: REPO,
  });

  const url = `http://127.0.0.1:${port}`;
  try {
    await waitFor(
      async () => {
        if (!pidAlive(serverPid)) {
          const tail = existsSync(serverLog)
            ? readFileSync(serverLog, "utf8").slice(-2000)
            : "";
          throw new Error(`mix phx.server pid ${serverPid} exited:\n${tail}`);
        }
        return (await httpCode(`${url}/user/log-in`)) === 200;
      },
      { timeoutMs: 120000, intervalMs: 500, label: `${url}/user/log-in` },
    );
  } catch (err) {
    killGroup(serverPid);
    throw err;
  }

  const chrome = findChrome();
  const browserLog = join(RUN_DIR, "browser.log");
  const userDataDir = join(RUN_DIR, "chrome-profile");
  mkdirSync(userDataDir, { recursive: true });
  const browserPid = spawnDetached(
    chrome,
    [
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-dev-shm-usage",
      "--no-sandbox",
      `--remote-debugging-port=${cdpPort}`,
      "--remote-debugging-address=127.0.0.1",
      `--user-data-dir=${userDataDir}`,
      "--window-size=1280,800",
      "about:blank",
    ],
    { logPath: browserLog, env: {}, cwd: REPO },
  );

  try {
    await waitFor(
      async () => {
        if (!pidAlive(browserPid)) {
          const tail = existsSync(browserLog)
            ? readFileSync(browserLog, "utf8").slice(-2000)
            : "";
          throw new Error(`Chromium pid ${browserPid} exited:\n${tail}`);
        }
        return (await httpCode(`http://127.0.0.1:${cdpPort}/json/version`)) === 200;
      },
      {
        timeoutMs: 30000,
        intervalMs: 200,
        label: `CDP http://127.0.0.1:${cdpPort}/json/version`,
      },
    );
  } catch (err) {
    killGroup(browserPid);
    killGroup(serverPid);
    throw err;
  }

  saveState({
    port,
    cdpPort,
    url,
    databasePath,
    serverPid,
    browserPid,
    chrome,
    email: EMAIL,
    password: PASSWORD,
    repoRoot: REPO,
    artifactsDir: ARTIFACTS_DIR,
  });
  console.log(`ok url=${url}`);
  console.log(`ok db=${databasePath}`);
  console.log(`ok serverPid=${serverPid}`);
  console.log(`ok browserPid=${browserPid}`);
  console.log(`ok cdp=http://127.0.0.1:${cdpPort}`);
  console.log(`ok artifacts=${ARTIFACTS_DIR}`);
}

async function cmdDoctor() {
  const state = loadState();
  const failures = [];
  const check = (ok, line) => {
    if (ok) console.log(`ok ${line}`);
    else {
      console.log(`fail ${line}`);
      failures.push(line);
    }
  };

  check(pidAlive(state.serverPid), `serverPid=${state.serverPid} alive`);
  check(pidAlive(state.browserPid), `browserPid=${state.browserPid} alive`);
  const loginCode = await httpCode(`${state.url}/user/log-in`);
  check(loginCode === 200, `GET ${state.url}/user/log-in -> ${loginCode}`);
  const cdpCode = await httpCode(`http://127.0.0.1:${state.cdpPort}/json/version`);
  check(cdpCode === 200, `GET CDP /json/version -> ${cdpCode}`);
  check(existsSync(state.databasePath), `db exists ${state.databasePath}`);
  if (existsSync(state.databasePath)) {
    const emails = spawnSync(
      "sqlite3",
      [state.databasePath, "select email from users order by email;"],
      { encoding: "utf8" },
    );
    const list = (emails.stdout || "").trim();
    check(
      emails.status === 0 && list.includes(EMAIL),
      `user ${EMAIL} in sqlite (${list || "empty"})`,
    );
  }
  const listen = listeningPid(state.port);
  check(
    listen != null,
    `port ${state.port} listening` + (listen ? ` pid=${listen}` : ""),
  );
  check(state.port !== 4000, "not driving default :4000");
  if (failures.length) process.exitCode = 1;
}

async function cmdCleanup() {
  let state = null;
  if (existsSync(STATE_PATH)) {
    try {
      state = loadState();
    } catch {
      state = null;
    }
  }
  if (state) {
    killGroup(state.browserPid);
    killGroup(state.serverPid);
    await sleep(500);
    forceKillGroup(state.browserPid);
    forceKillGroup(state.serverPid);
  }
  if (existsSync(RUN_DIR)) rmSync(RUN_DIR, { recursive: true, force: true });
  console.log(`ok cleaned ${RUN_DIR}`);
  console.log(`ok artifacts kept at ${ARTIFACTS_DIR}`);
}

async function withPage(fn) {
  const state = loadState();
  const browser = await chromium.connectOverCDP(
    `http://127.0.0.1:${state.cdpPort}`,
  );
  try {
    const context = browser.contexts()[0];
    if (!context) throw new Error("Chromium has no context; relaunch");
    let page = context.pages()[0];
    if (!page) page = await context.newPage();
    page.setDefaultTimeout(15000);
    return await fn(page, state);
  } finally {
    await browser.close();
  }
}

function artifactPath(rel) {
  const dest = isAbsolute(rel) ? rel : join(ARTIFACTS_DIR, rel);
  mkdirSync(dirname(dest), { recursive: true });
  return dest;
}

async function cmdBrowser(args) {
  const [action, ...rest] = args;
  if (!action) throw new Error(usage());

  if (action === "login") {
    await withPage(async (page, state) => {
      await page.goto(`${state.url}/user/log-in`, {
        waitUntil: "domcontentloaded",
      });
      if (await page.locator("#items-page").count()) {
        console.log("ok already logged in");
        return;
      }
      await page.waitForSelector("#login_form_password");
      await page.fill("#user_email", state.email);
      await page.fill("#user_password", state.password);
      await page.click("#login_form_password button");
      await page.waitForSelector("#items-page");
      console.log("ok logged in");
    });
    return;
  }

  if (action === "goto") {
    const path = rest[0];
    if (!path) throw new Error("browser goto <path>");
    await withPage(async (page, state) => {
      const url = path.startsWith("http") ? path : `${state.url}${path}`;
      await page.goto(url, { waitUntil: "domcontentloaded" });
      console.log(`ok ${page.url()}`);
    });
    return;
  }

  if (action === "click") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser click <selector>");
    await withPage(async (page) => {
      await page.click(selector);
      console.log(`ok clicked ${selector}`);
    });
    return;
  }

  if (action === "click-at") {
    const xRaw = rest.length >= 2 ? rest[rest.length - 2] : undefined;
    const yRaw = rest.length >= 2 ? rest[rest.length - 1] : undefined;
    const selector = rest.slice(0, -2).join(" ").trim();
    const x = Number(xRaw);
    const y = Number(yRaw);
    if (!selector || !Number.isFinite(x) || !Number.isFinite(y)) {
      throw new Error("browser click-at <selector> <x> <y>");
    }
    await withPage(async (page) => {
      await page.locator(selector).first().click({ position: { x, y } });
      console.log(`ok clicked ${selector} at ${x},${y}`);
    });
    return;
  }

  if (action === "box") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser box <selector>");
    await withPage(async (page) => {
      const box = await page.locator(selector).first().boundingBox();
      if (!box) throw new Error(`no bounding box for ${selector}`);
      console.log(
        `ok ${selector} x=${box.x} y=${box.y} w=${box.width} h=${box.height}`,
      );
    });
    return;
  }

  if (action === "click-box") {
    const fxRaw = rest.length >= 2 ? rest[rest.length - 2] : undefined;
    const fyRaw = rest.length >= 2 ? rest[rest.length - 1] : undefined;
    const selector = rest.slice(0, -2).join(" ").trim();
    const fx = Number(fxRaw);
    const fy = Number(fyRaw);
    if (!selector || !Number.isFinite(fx) || !Number.isFinite(fy)) {
      throw new Error("browser click-box <selector> <fx> <fy>");
    }
    await withPage(async (page) => {
      const box = await page.locator(selector).first().boundingBox();
      if (!box) throw new Error(`no bounding box for ${selector}`);
      const x = box.x + fx * box.width;
      const y = box.y + fy * box.height;
      await page.mouse.click(x, y);
      console.log(`ok clicked ${selector} box ${fx},${fy} at ${x},${y}`);
    });
    return;
  }

  if (action === "hover") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser hover <selector>");
    await withPage(async (page) => {
      await page.hover(selector);
      console.log(`ok hovered ${selector}`);
    });
    return;
  }

  if (action === "fill") {
    const selector = rest[0];
    const value = rest.slice(1).join(" ");
    if (!selector) throw new Error("browser fill <selector> <value>");
    await withPage(async (page) => {
      await page.fill(selector, value);
      console.log(`ok filled ${selector}`);
    });
    return;
  }

  if (action === "press") {
    const key = rest[0];
    if (!key) throw new Error("browser press <key>");
    await withPage(async (page) => {
      await page.keyboard.press(key);
      console.log(`ok pressed ${key}`);
    });
    return;
  }

  if (action === "wait") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser wait <selector>");
    await withPage(async (page) => {
      await page.waitForSelector(selector, { state: "visible" });
      console.log(`ok visible ${selector}`);
    });
    return;
  }

  if (action === "wait-attached") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser wait-attached <selector>");
    await withPage(async (page) => {
      await page.waitForSelector(selector, { state: "attached" });
      console.log(`ok attached ${selector}`);
    });
    return;
  }

  if (action === "wait-enabled") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser wait-enabled <selector>");
    await withPage(async (page) => {
      await page.waitForFunction((sel) => {
        const el = document.querySelector(sel);
        return Boolean(el) && !el.disabled;
      }, selector);
      console.log(`ok enabled ${selector}`);
    });
    return;
  }

  if (action === "enabled") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser enabled <selector>");
    await withPage(async (page) => {
      const loc = page.locator(selector).first();
      const disabled = await loc.isDisabled();
      console.log(disabled ? "disabled" : "enabled");
    });
    return;
  }

  if (action === "text") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser text <selector>");
    await withPage(async (page) => {
      console.log((await page.locator(selector).innerText()).trim());
    });
    return;
  }

  if (action === "exists") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser exists <selector>");
    await withPage(async (page) => {
      const n = await page.locator(selector).count();
      if (n === 0) {
        console.log(`fail missing ${selector}`);
        process.exitCode = 1;
      } else {
        console.log(`ok ${n} ${selector}`);
      }
    });
    return;
  }

  if (action === "attr") {
    const selector = rest[0];
    const name = rest[1];
    if (!selector || !name) throw new Error("browser attr <selector> <name>");
    await withPage(async (page) => {
      const value = await page.locator(selector).first().getAttribute(name);
      console.log(value ?? "");
    });
    return;
  }

  if (action === "count") {
    const selector = rest.join(" ").trim();
    if (!selector) throw new Error("browser count <selector>");
    await withPage(async (page) => {
      console.log(String(await page.locator(selector).count()));
    });
    return;
  }

  if (action === "screenshot") {
    const rel = rest[0];
    if (!rel) throw new Error("browser screenshot <relpath>");
    await withPage(async (page) => {
      const dest = artifactPath(rel);
      await page.screenshot({ path: dest, fullPage: true });
      console.log(`ok ${dest}`);
    });
    return;
  }

  if (action === "html") {
    const rel = rest[0];
    if (!rel) throw new Error("browser html <relpath>");
    await withPage(async (page) => {
      const dest = artifactPath(rel);
      writeFileSync(dest, await page.content());
      console.log(`ok ${dest}`);
    });
    return;
  }

  throw new Error(`unknown browser action ${action}\n${usage()}`);
}

function cmdSqlite(sql) {
  const state = loadState();
  const result = spawnSync(
    "sqlite3",
    ["-header", "-column", state.databasePath, sql],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(result.stderr || `sqlite3 exit ${result.status}`);
  }
  const out = (result.stdout || "").trimEnd();
  if (out) console.log(out);
}

function parseFlags(argv) {
  const flags = {};
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) flags[key] = true;
      else {
        flags[key] = next;
        i++;
      }
    } else rest.push(arg);
  }
  return { flags, rest };
}

async function main() {
  const argv = process.argv.slice(2);
  const command = argv[0];
  if (!command || command === "-h" || command === "--help") {
    process.stdout.write(usage());
    return;
  }
  const { flags, rest } = parseFlags(argv.slice(1));
  if (command === "launch") await cmdLaunch(flags);
  else if (command === "doctor") await cmdDoctor();
  else if (command === "cleanup") await cmdCleanup();
  else if (command === "browser") await cmdBrowser(rest);
  else if (command === "sqlite") cmdSqlite(rest.join(" "));
  else throw new Error(`unknown command ${command}\n${usage()}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
