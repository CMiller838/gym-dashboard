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

### Logic & Backend (TDD)

- [x] Add `exercisePRHolders(records)` next to `classifySetPR` (index.html ~947): scans one
      exercise's `{logId, weight, reps}` records for the max-weight and max-volume record,
      tie-broken by lowest `logId`; returns `{weightLogId, volumeLogId}` (`null`s when empty).
- [x] Add self-test block for `exercisePRHolders` (same `assert()` pattern as `classifySetPR`,
      index.html ~1864-1873): empty input, single record, distinct weight/volume holders, exact
      tie tie-break, constant-weight/varying-reps volume pick.
- [x] `renderActiveWorkout()`: per exercise entry, build the merged pool (`allLogsCache` filtered
      by `exerciseId` + this session's own already-logged `entry.sets`), call
      `exercisePRHolders`, and use the result to decide per-set badge flags.
- [x] `render()` (index.html ~752): pass the already-fetched flat `logs` array as `renderHistory`'s
      4th argument.
- [x] `renderHistory(sessions, logsBySession, routineById, logs)`: accept the new `logs` param,
      compute `exercisePRHolders` per exercise group from full fetched history (not just the
      current session's subset), before building each exercise's set list.

### UI & Layout (rapid prototyping)

- [x] Active workout: show a `🏆` badge on the logged set row matching `holders.weightLogId`,
      and/or a `🔥` badge on the row matching `holders.volumeLogId` (same row can show both),
      inside the existing `setnum` cell — unlogged rows never show a badge.
- [x] History: split the per-exercise `setStr` join (~index.html:816) into one `<span>` per set
      so a specific set can carry its own `🏆`/`🔥` badge, preserving the existing joined-text
      look as closely as possible.
- [ ] Manual check: log a new heaviest-ever set for an exercise mid-workout → medal appears on
      that row immediately (no reload) and moves off the previous holder.
- [ ] Manual check: delete a medal-holding logged set mid-workout → medal moves to the next-best
      remaining set, or disappears if none remain.
- [ ] Manual check: History tab shows the same medal-holder set as the active workout view for
      an exercise logged in both.

## Phase 4 — Routine preview view

(tasks filled in by `@planner Phase 4` immediately before build)

## Phase 5 — Readable 3-month exercise trend graph — done

### Logic & Backend (TDD)

- [x] Add `trendWindowBounds(now = new Date())` (index.html ~1002, before `buildTrendPoints`):
      returns `{startISO, endISO}` — `endISO` is `now` as `YYYY-MM-DD`, `startISO` is `now` minus
      3 calendar months (via `Date.setMonth`), both via `localDateISO`.
- [x] Rework `buildTrendPoints(exerciseId, logs, now = new Date())` (index.html:1004-1014):
      replace the `.slice(-20)` cap with a filter keeping only days
      `>= trendWindowBounds(now).startISO`; per-day max-weight grouping stays unchanged.
- [x] Add `trendLabelIndices(points)` (near `renderTrendSvg`): returns the deduped, sorted indices
      to label — first, last, first-occurrence-of-min-weight, first-occurrence-of-max-weight.
- [x] Rework `renderTrendSvg(points, now = new Date())` (index.html:1017-1030): delete the old
      `points.length === 1` special case; compute x per point as time-proportional within
      `trendWindowBounds(now)` (`(pointDate - startMs)/span * 300`) instead of even index
      spacing; keep existing y min/max normalization.
- [x] Replace the old self-test block for `buildTrendPoints` (index.html ~1961-1970) with:
      `trendWindowBounds` fixed-date assertion; in-window vs before-window filtering with a fixed
      `now`; a >20-in-window fixture asserting no truncation (removes the old 20-day-cap
      assertion); per-day max-weight collapse retained from the existing fixtures.
- [x] Add self-test block for `trendLabelIndices`: empty -> `[]`; single point -> `[0]`;
      ascending-then-descending weight fixture -> four distinct correct indices; a fixture where
      min/max coincides with first/last -> deduped, no repeated index.

### UI & Layout (rapid prototyping)

- [x] `renderTrendSvg`: for each index from `trendLabelIndices`, render a value line
      (`formatKg(weight)`) and a compact date line (`month short + day`, e.g. `"Sep 3"` — not
      `fmtDate`, too wide) as two `<text>` elements near the point; non-labeled points stay plain
      circles.
- [x] Label placement: vertical above the point (`y-18`/`y-8`) unless `y <= 25`, then below
      (`y+14`/`y+24`); horizontal `text-anchor` `start`/`end` near the left/right viewBox edges
      (`x<=20`/`x>=280`), `middle` otherwise.
- [x] Add `.trend-svg text{...}` CSS rule(s) (~index.html:200-203, alongside existing
      `.trend-svg circle`/`polyline` rules) for label color/size, following existing CSS variable
      conventions.
- [x] Manual check: open an exercise's detail view with logs spread across the full 3-month
      window (including a multi-week gap) — confirm the gap shows as visual spacing, not evenly
      compressed, and only the first/last/min/max points carry a date+weight label. Verified via
      isolated logic test (node, 11 assertions) reproducing `trendWindowBounds`/`buildTrendPoints`/
      `trendLabelIndices`/`renderTrendSvg`'s x-scaling — full in-browser #selftest not run this
      session (no jsdom/browser automation available in sandbox); syntax-checked via `node --check`.
- [x] Manual check: exercise with only one log in the window — single dot at its real position
      in the window (not centered), one label. Verified in the same isolated test (single-point
      x falls strictly between 0 and 300, not centered at 150).
- [x] Manual check: exercise with no logs in the last 3 months (but older history exists) —
      "No history yet" empty state, not a widened window. Unchanged code path
      (`renderTrendSvg` still returns `.trend-empty` on `!points.length`), confirmed by the
      before-window-exclusion assertion feeding an empty `points` array.
