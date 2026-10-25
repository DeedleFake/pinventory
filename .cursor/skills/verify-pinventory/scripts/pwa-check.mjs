#!/usr/bin/env node
// One-off PWA proof over CDP: installability, service worker control, cache contents,
// and the offline fallback. The harness `browser` commands cannot do this (no JS eval,
// no offline toggle, and each command reconnects, which drops offline mode).
// Run: node ./.cursor/skills/verify-pinventory/scripts/pwa-check.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const here = dirname(fileURLToPath(import.meta.url));
const state = JSON.parse(
  readFileSync(join(here, "../../../../tmp/verify-pinventory/run/state.json"), "utf8"),
);
const failures = [];
const check = (label, ok, detail = "") => {
  console.log(`${ok ? "ok" : "fail"} ${label}${detail ? ` ${detail}` : ""}`);
  if (!ok) failures.push(label);
};

const browser = await chromium.connectOverCDP(`http://127.0.0.1:${state.cdpPort}`);
const ctx = browser.contexts()[0];
const page = await ctx.newPage();
try {
  await page.goto(`${state.url}/user/log-in`);
  await page.waitForSelector("#login_form_password");
  check("manifest link", (await page.getAttribute("link[rel=manifest]", "href")) === "/manifest.webmanifest");

  const cdp = await ctx.newCDPSession(page);
  const manifest = await cdp.send("Page.getAppManifest");
  check("manifest parses", manifest.errors.length === 0, JSON.stringify(manifest.errors));
  const inst = await cdp.send("Page.getInstallabilityErrors");
  check("installable", inst.installabilityErrors.length === 0, JSON.stringify(inst.installabilityErrors));

  const reg = await page.evaluate(async () => {
    const r = await navigator.serviceWorker.ready;
    return { scope: r.scope, script: r.active?.scriptURL };
  });
  check("service worker active", reg.script === `${state.url}/sw.js` && reg.scope === `${state.url}/`, JSON.stringify(reg));
  await page.reload();
  await page.waitForSelector("#login_form_password");
  check("page controlled after reload", await page.evaluate(() => !!navigator.serviceWorker.controller));

  const cached = await page.evaluate(async () => {
    const out = {};
    for (const k of await caches.keys())
      out[k] = (await (await caches.open(k)).keys()).map((r) => new URL(r.url).pathname).sort();
    return out;
  });
  const keys = Object.keys(cached);
  check("one pinventory cache", keys.length === 1 && keys[0].startsWith("pinventory-static-"), JSON.stringify(cached));
  const entries = cached[keys[0]] || [];
  check(
    "cache holds offline page and icons",
    ["/offline.html", "/images/icon-192.png", "/images/icon-512.png"].every((p) => entries.includes(p)),
  );

  await ctx.setOffline(true);
  try {
    await page.goto(`${state.url}/`);
    await page.waitForSelector("#offline-page", { timeout: 10000 });
    check("offline page heading", (await page.textContent("#offline-page h1")).includes("You're offline"));
    check("offline page retry button", (await page.textContent("#offline-page button")).includes("Try again"));
  } finally {
    await ctx.setOffline(false);
  }
  await page.goto(`${state.url}/user/log-in`);
  check("back online", (await page.locator("#login_form_password").count()) === 1);
} finally {
  await page.close().catch(() => {});
}
process.exit(failures.length ? 1 : 0);
