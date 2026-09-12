# Tasks

Phase checklists are filled in by `@planner Phase N` immediately before each phase is
built. Placeholders below track the roadmap in `docs/roadmap.md`.

## Phase 1 — Louder timer audio

Spec: `.claude/specs/phase1_spec.md`

### Logic & Backend Tasks (TDD where applicable — this is WebAudio tuning, verified on-device, not unit-testable)

- [x] `index.html:345` — add `let compressorNode = null;` next to `audioCtx`.
- [x] `primeAudio()` (index.html:656) — create a `DynamicsCompressorNode` once
      alongside `audioCtx`, set `threshold=-6, knee=0, ratio=20, attack=0.003,
      release=0.1`, connect it to `audioCtx.destination`, store in `compressorNode`.
- [x] `beep()` (index.html:665-681) — change `osc.type` from `"triangle"` to
      `"square"`.
- [x] `beep()` — change default gain from `0.32` to `0.4`.
- [x] `beep()` — change connection chain from
      `osc.connect(gainNode).connect(audioCtx.destination)` to
      `osc.connect(gainNode).connect(compressorNode)`.
- [x] index.html:1269 — raise timer-expiry beep gain from `0.5` to `0.65`.

### Manual On-Device Verification (no automated test — audio perception)

- [ ] Play music at normal volume on a real phone, trigger timer-expiry beep, confirm
      it now cuts through clearly (louder than pre-change).
- [ ] Same conditions, trigger the 3-tone confirm chord, confirm no audible
      clipping/distortion from the gain increase.
- [ ] Trigger both beeps back-to-back rapidly, confirm the compressor prevents harsh
      clipping from overlapping oscillator sums.
- [ ] Confirm the `ponytail:` no-mute-toggle behavior (iOS ringer silences, Android
      doesn't) is unchanged.

## Phase 2 — Background/locked-phone timer alerts

Spec: `.claude/specs/phase2_spec.md` — implements ADR 001 (`docs/ARCHITECTURE.md:81-180`).

### Logic & Backend Tasks (TDD where applicable — this is service-worker/OS behavior, verified on-device, not unit-testable)

- [x] New file `sw.js` at repo root — header comment naming the ADR 001 scope
      constraint (no `fetch`, no `push`/`pushManager`, no Background Sync), then
      `install` → `skipWaiting()`, `activate` → `clients.claim()`. Nothing else.
- [x] `sw.js` — `notificationclick` handler: `notification.close()`, then
      `event.waitUntil()` a `clients.matchAll({type:'window', includeUncontrolled:true})`;
      focus the first window if present, else `clients.openWindow('./')` (relative).
- [x] `index.html:~346` — add `let swReg = null;` and `let bgAlertTimeout = null;`
      next to the existing bootstrap `let`s.
- [x] `index.html` bootstrap — `registerServiceWorker()`: guard on
      `'serviceWorker' in navigator`, register the **relative** path `'sw.js'` (never
      `'/sw.js'` — GitHub Pages subpath), assign `swReg`, swallow failures silently.
- [x] `index.html:~1269` — `nextRestEndMs()`: soonest future `entry.restEndMs` across
      the active workout's entries, else `null`.
- [x] `index.html:~1269` — `disarmBackgroundAlert()`: `clearTimeout(bgAlertTimeout)`,
      null it.
- [x] `index.html:~1269` — `armBackgroundAlert()`: no-op unless `swReg` and
      `Notification.permission === 'granted'`; disarm first, then `setTimeout` for
      `nextRestEndMs() - Date.now()`. Add a `ponytail:` comment noting the single-timer
      ceiling (soonest timer only).
- [x] `armBackgroundAlert()` fire callback — late-fire guard FIRST: drop silently if
      `document.visibilityState === 'visible'` or `Date.now() - endMs > 5000`.
      Otherwise `swReg.showNotification('Rest over', { body, tag: 'rest-timer',
      renotify: true, vibrate: [100,80,100,80,100], icon: 'icon-192.png' })`, then null
      `bgAlertTimeout`.
- [x] `index.html:1719` — extend the **existing** `visibilitychange` listener (do not
      add a second): `hidden` → `armBackgroundAlert()`; `visible` →
      `disarmBackgroundAlert()` before the existing `tickRestTimers()` call.
- [x] `index.html:309-312` — add hidden toolbar button `#bgAlertBtn`
      ("Enable background alerts"); show only when notifications + SW are supported
      and `Notification.permission === 'default'`.
- [x] `enableBackgroundAlerts()` click handler — call `Notification.requestPermission()`
      synchronously inside the gesture (no `await` before it); hide the button on any
      result; if granted and the page is hidden, `armBackgroundAlert()`.

### Manual On-Device Verification (no automated test — OS/browser behavior)

Requires a secure context: GitHub Pages HTTPS or `localhost`. A LAN-IP
`python3 -m http.server` is plain HTTP and will silently fail to register the SW.

- [ ] Android installed PWA: tap "Enable background alerts", accept → button disappears.
- [ ] Rest timer + app backgrounded → notification fires at zero with vibration.
- [ ] Rest timer + **phone locked** → notification + vibration on the lock screen.
- [ ] Tap the notification → existing app window focused, no duplicate tab.
- [ ] Return **before** zero → no notification; foreground beep fires normally.
- [ ] Return **long after** zero → no late notification (5s guard).
- [ ] Two rests back-to-back while backgrounded → notifications replace, never stack.
- [ ] Deny permission → no button on reload, app fully functional, no console errors.
- [ ] iOS installed PWA: foreground beep + wake lock unchanged, nothing breaks.
- [ ] DevTools → Application → Service Workers: `sw.js` active, serving **no** network
      requests (confirms no `fetch` handler).

## Phase 3 — Persistent PR medals

(tasks filled in by `@planner Phase 3` immediately before build)

## Phase 4 — Routine preview view

(tasks filled in by `@planner Phase 4` immediately before build)

## Phase 5 — Readable 3-month exercise trend graph

(tasks filled in by `@planner Phase 5` immediately before build)
