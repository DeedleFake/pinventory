# PWA

Pinventory is installable. A web app manifest and icons make browsers offer install. A small service worker shows an offline page when the network is down. The header theme toggle also sets the browser title-bar color.

## Sub-features

- `pwa-manifest` links `/manifest.webmanifest` from every page (`link[rel=manifest]`), with 192, 512 and maskable 512 icons. `link[rel=apple-touch-icon]` points at `/images/apple-touch-icon.png`.
- `pwa-installable` means Chromium reports no installability errors.
- `pwa-service-worker` registers `/sw.js` with scope `/`. It controls the page after a reload.
- `pwa-cache` holds only `/offline.html` and the two non-maskable icons in `pinventory-static-v1` on the dev server.
- `pwa-offline` shows `#offline-page` (heading `You're offline`, button `Try again`) for any page navigation while the network is unreachable. Pages are never served from cache.
- `pwa-theme` switches the theme with the header toggle (`System theme`, `Light theme`, `Dark theme`) and keeps `meta[name=theme-color]` in step. The choice survives a page load.
- `pwa-public-files` serves the manifest, `/sw.js`, `/offline.html` and the icons without a session.

## How to get to it (user POV)

- Use the browser's Install action on a Pinventory page. A headless run cannot click it; `pwa-check.mjs` reads the same installability verdict from Chromium.
- Lose the network, then open or reload a page.
- Choose the sun, moon, or computer icon at the top right of any page.

## Driving it with verify-pinventory

Preconditions:

- Doctor is green. `pwa-check.mjs` starts from `/user/log-in`, so it needs no login. The theme recipes work on any page.
- The harness `browser` commands cannot prove installability, worker control, cache contents, or the offline page. They have no JS eval, and each command reconnects over CDP, which drops offline mode. Run the one-off script instead.

- **Install, worker, cache, offline.** Run `node ./.cursor/skills/verify-pinventory/scripts/pwa-check.mjs`. Every line prints `ok`: manifest link, manifest parses, installable, service worker active, page controlled after reload, one `pinventory-static-v1` cache, cache holds the offline page and icons, offline page heading, retry button, back online. Exit code is 0. It turns network off in the shared browser and always turns it back on.
- **Public files.** Run `curl -s -o /dev/null -w '%{http_code} %{content_type}\n' http://127.0.0.1:4010/manifest.webmanifest`. Expect `200 application/manifest+json`. `/sw.js`, `/offline.html` and `/images/icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `apple-touch-icon.png` are also `200`.
- **Manifest link.** Run `verify-pinventory browser attr 'link[rel=manifest]' href`. It prints `/manifest.webmanifest`.
- **Theme forced.** Run `verify-pinventory browser goto /`, then `verify-pinventory browser click 'button[aria-label="Dark theme"]'`. `browser attr html data-theme` prints `dark`. `browser attr 'meta[data-theme-color=light]' content` and the same for `dark` both print `#292f37`.
- **Light.** Click `button[aria-label="Light theme"]`. `data-theme` is `light`. Both metas print `#f8f8f8`.
- **System.** Click `button[aria-label="System theme"]`. `data-theme` prints blank (the attribute is removed). The `light` meta is `#f8f8f8` and the `dark` meta is `#292f37`.
- **Persists.** Click `Dark theme`, then `verify-pinventory browser goto /locations`. `data-theme` is still `dark`. Finish with `System theme` so later recipes start from the default.
- **Proof.** Run `verify-pinventory browser screenshot pwa/dark.png` with Dark selected. Keep the `pwa-check.mjs` output.

## Gotchas

- Launch runs the dev server, so `pwa-check.mjs` sees only the three precached files in the cache. `sw.js` also caches digested `/assets/...?vsn=` files in a prod build. That is not verified here.
- The theme buttons have no ids. Use the `aria-label` selectors. The harness cannot read `localStorage`. Read `data-theme` and the metas instead.
- While Dark or Light is forced, both `meta[name=theme-color]` tags carry that theme's color, so the media conditions no longer matter. Only System uses the device setting.
- The manifest `theme_color` and `background_color` are both the light `#f8f8f8`. A dark-theme user can see a light splash screen before the page loads. The meta tags take over once the page loads.
- Not covered: installing on a real device, real HTTPS, and a prod build.
- `pwa-check.mjs` opens its own tab in the shared browser and closes it. It does not need a login.
