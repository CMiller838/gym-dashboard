# Phase 2 — Background/locked-phone timer alerts

Implements ADR 001 (`docs/ARCHITECTURE.md:81-180`, Accepted). Fire a vibration + OS
notification when the rest timer ends while the app is backgrounded or the phone is
locked. Android-only by design; iOS keeps the foreground-only path it already has.

## 0. What investigation found (from dispatch, no re-scan needed)

- Rest deadline lives on each entry as `entry.restEndMs` (ms timestamp or `null`),
  set at `index.html:1523` as `Date.now() + restSeconds*1000`; entries live in
  `w.entries[idx]` (shape documented `index.html:896`), initialized at 1057/1405.
- `tickRestTimers()` (`index.html:1269`) runs on `setInterval(..., 1000)` stored in
  `restTickInterval` (`index.html:1255`). On expiry it calls
  `beep([1200,800,1200,800], 0.65)` (1279), `vibrate([100,80,100,80,100])` (1280),
  then nulls `entry.restEndMs` (1281).
- Helpers: `beep(freqs, gain = 0.4)` (675), `vibrate(pattern)` (1423), `esc()` (546).
- A `visibilitychange` listener **already exists** at `index.html:1719` and calls
  `tickRestTimers()`. No `serviceWorker` and no `Notification` code exists anywhere.
- Module bootstrap (constants, `let`s, `primeAudio()`, `acquireWakeLock()`) is
  `index.html:315-346`, inside the `<script>` opened at 314.
- App is served from repo root scope (`manifest.json` at line 7, bare icon paths).
- Toolbar markup is `#mainToolbar`, `index.html:309-312`.
- localStorage keys in use: `TOKEN_KEY`, `ACTIVE_KEY`, `EXINDEX_KEY`,
  `ROUTINE_ORDER_KEY` (322-327).

## 1. Decisions (Tier 3 — decided here, not gated)

- **File name / location: `sw.js` at repo root.** ADR 001 prescribes "one small
  static file served from the repo root" but never names it. `sw.js` is the
  conventional name and keeps root scope without a `Service-Worker-Allowed` header
  (GitHub Pages can't set headers).
- **Register with a *relative* path (`'sw.js'`, or `'./sw.js'`), never `'/sw.js'`.**
  GitHub Pages may serve this repo under a project subpath; an absolute path would
  request the wrong URL and 404. Relative resolves against the page URL.
- **Extend the existing `visibilitychange` listener at `index.html:1719`** rather than
  adding a second one. One listener, one place to reason about arm/disarm ordering.
- **Arm/disarm logic lives in two small module-scope functions next to the timer code,
  not inside `tickRestTimers()`.** `tickRestTimers()` is the 1s foreground loop and
  must stay free of per-tick notification work; the background path is edge-triggered
  by visibility, not polled.
- **No new localStorage key.** `Notification.permission` is already persisted by the
  browser and is the single source of truth — a mirrored flag would be a second truth
  that can disagree with it.
- **Permission button is a toolbar button in `#mainToolbar`, hidden unless it's
  actionable** (i.e. shown only when notifications are supported and
  `Notification.permission === 'default'`). Satisfies ADR 001's "real user gesture,
  never on page load", and self-removes after the one tap so it costs no permanent
  toolbar space.
- **Only the soonest live rest timer is armed** (single `setTimeout`, single
  notification `tag`). Concurrent rest timers across entries are not a real usage
  pattern here. Mark with a `ponytail:` comment naming the ceiling.

## 2. Changes

### New file: `sw.js` (repo root)

Three handlers, nothing else. Per ADR 001 this file must contain **no `fetch`
handler, no `push` handler, no `pushManager` use, and no Background Sync** — its only
purpose is to exist so `registration.showNotification()` is callable.

```
self.addEventListener('install', (event) => { /* skipWaiting */ });
self.addEventListener('activate', (event) => { /* clients.claim() */ });
self.addEventListener('notificationclick', (event) => { /* see below */ });
```

`notificationclick` behavior: close the notification, then
`event.waitUntil(...)` a `clients.matchAll({ type: 'window', includeUncontrolled: true })`
— focus the first existing window if there is one, otherwise `clients.openWindow('./')`
(relative, same subpath reason as registration).

Add a one-line header comment in `sw.js` stating the scope constraint and pointing at
ADR 001, so the next person doesn't casually add a `fetch` handler.

### `index.html` bootstrap (~after line 346)

```
let swReg = null;             // ServiceWorkerRegistration | null
let bgAlertTimeout = null;    // number | null (setTimeout id)
```

Registration, guarded by `'serviceWorker' in navigator` (and silently no-op on
failure — this is an enhancement, never a blocker for the app booting):

```
registerServiceWorker(): void   // fire-and-forget; assigns swReg
```

Failure path: `catch` and leave `swReg = null`. Registration fails on plain HTTP
(non-localhost), which is expected when testing over a LAN IP — see §4.

### New: arm/disarm, near the rest-timer code (`index.html` ~1269-1290)

```
nextRestEndMs(): number | null
```
Returns the soonest `entry.restEndMs` across the active workout's entries that is
still in the future, else `null`.

```
armBackgroundAlert(): void
```
No-op unless `swReg` is set and `Notification.permission === 'granted'`. Reads
`nextRestEndMs()`; if null, no-op. Otherwise `bgAlertTimeout = setTimeout(fire, endMs - Date.now())`.
Always `disarmBackgroundAlert()` first so it can't stack.

```
disarmBackgroundAlert(): void
```
`clearTimeout(bgAlertTimeout)`; `bgAlertTimeout = null`.

Fire callback (inline in `armBackgroundAlert`, captures `endMs`) — **late-fire guard
first**, per ADR 001:

- Drop silently if `document.visibilityState === 'visible'` (page resumed; the
  foreground `beep()`/`vibrate()` path owns the alert).
- Drop silently if `Date.now() - endMs > 5000` (timer expired well in the past —
  throttled/suspended wake, alert would be noise).
- Otherwise:

```
swReg.showNotification('Rest over', {
  body: <exercise name, esc() not needed — notification body is text, not innerHTML>,
  tag: 'rest-timer',        // stable: a repeat replaces, never stacks
  renotify: true,
  vibrate: [100, 80, 100, 80, 100],   // same pattern as the foreground vibrate()
  icon: 'icon-192.png',     // relative, subpath-safe
});
```

Set `bgAlertTimeout = null` after firing.

### `visibilitychange` handler (`index.html:1719`)

Extend the existing listener — do not add a second one:

- `hidden` → `armBackgroundAlert()`
- `visible` → `disarmBackgroundAlert()`, then the existing `tickRestTimers()` call
  (order matters: disarm before the foreground tick takes over).

### Toolbar (`index.html:309-312` markup + its render/init path)

Add a button (id e.g. `#bgAlertBtn`), hidden by default. Shown only when
`'Notification' in window && 'serviceWorker' in navigator && Notification.permission === 'default'`.

```
enableBackgroundAlerts(): Promise<void>   // click handler
```
Calls `Notification.requestPermission()` directly in the click handler (must stay in
the gesture's call stack — do not `await` anything before it). On any result, hide the
button. On `'granted'`, if the page is currently hidden, `armBackgroundAlert()`.

## 3. Edge cases

- **Permission denied / dismissed** — button hides, `armBackgroundAlert()` stays a
  no-op forever via the `permission === 'granted'` check. No nagging, no retry.
- **iOS** — `showNotification` while backgrounded does not deliver; the guard path
  simply produces nothing. Foreground beep + Screen Wake Lock remain unchanged. Do not
  add an iOS-specific branch.
- **Rest ends while hidden, then the user returns much later** — the fire callback's
  `> 5000ms` guard drops it; the notification is not shown late.
- **Backgrounded `setInterval` throttling** — `tickRestTimers()` may still fire late
  while hidden and beep/vibrate. Accepted: it's the same alert moment, and on `visible`
  the existing handler re-ticks. No code change.
- **Timer started *while* the page is hidden** — not possible; starting a rest requires
  a tap on a visible page. No arming outside `visibilitychange`.
- **SW registration fails (HTTP, private mode, unsupported)** — `swReg` stays null,
  every background path no-ops, app is otherwise unaffected.
- **Repeat/overlapping alerts** — stable `tag: 'rest-timer'` replaces rather than
  stacks; `armBackgroundAlert()` disarms before re-arming.
- **User finishes the set early and the page goes hidden again** — re-arm recomputes
  from `nextRestEndMs()`, so a cancelled/reset rest can't fire a stale notification.

## 4. Manual on-device verification (no automated test — this is OS/browser behavior)

Service workers and Notifications require a **secure context**: `https://` or
`localhost` only. `python3 -m http.server 8000` reached over a LAN IP is plain HTTP and
will silently fail to register — verify on the deployed GitHub Pages URL, or via
`localhost` with port forwarding.

- Android, installed PWA: tap "Enable background alerts", accept → button disappears.
- Start a rest timer, background the app → notification fires at zero with vibration.
- Same, with the **phone locked** → notification + vibration on the lock screen.
- Tap the notification → the existing app window is focused (not a duplicate tab).
- Start a rest, background, return **before** zero → no notification; foreground beep
  fires normally at zero.
- Start a rest, background, return **long after** zero → no late notification.
- Two rests in a row while backgrounded → notifications replace, never stack.
- Deny permission → no button on reload, app fully functional, no errors in console.
- iOS installed PWA: foreground beep + wake lock still work; nothing breaks when
  backgrounded.
- DevTools → Application → Service Workers: confirm `sw.js` is active and that **no**
  network requests are being served from it (no `fetch` handler).

## 5. Explicitly out of scope

- Any `fetch` handler, offline caching, or app-shell precaching (ADR 001 hard
  constraint — needs separate sign-off).
- `push` handler, `pushManager.subscribe()`, VAPID, Background Sync / Periodic Sync.
- Any backend or proxy (`CLAUDE.md` architecture invariant).
- Making background alerts work on iOS — accepted ceiling, documented in ADR 001.
- Notification actions/buttons ("Skip rest", "+30s"), notification settings UI, or
  per-exercise alert preferences.
- Arming more than one concurrent rest timer.
