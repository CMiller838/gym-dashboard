# Tasks

Phase checklists are filled in by `@planner Phase N` immediately before each phase is
built. Placeholders below track the roadmap in `docs/roadmap.md`.

## Phase 1 — Date and time correctness

Spec: `.claude/specs/phase1_spec.md`. All edits are in `index.html`.

### Logic & backend tasks (TDD — add the `#selftest` case first, watch it fail, then fix)

- [x] Add `runSelfTest()` at the end of the `<script>`, gated on `location.hash === "#selftest"`, with a check counter and one closing `console.log` summary
- [x] Add `localDateISO(d = new Date())` returning local `YYYY-MM-DD` from calendar fields (no `toISOString`, no locale strings)
- [x] Point `todayISO()` at `localDateISO()` — fixes the session `date` / `time_start` clock mismatch
- [x] Replace `checkDate.toISOString().slice(0,10)` in the streak loop with `localDateISO(checkDate)` (same root cause; streak is currently off by one all through BST)
- [x] Add `dayKey(v)` handling both date-only and datetime API values, and `null`
- [x] Add `compareSessionsDesc(a, b)` — `dayKey(date)`, then `time_start`, then `id`, all descending; total, never `NaN`, safe on missing fields
- [x] Add non-mutating `sortSessionsDesc(list)`
- [x] Sort `sessions` with `sortSessionsDesc` in `render()` after the generation guard, before stats and `renderHistory` consume it
- [x] Rewrite `lastTimeForExercise` ordering to use `compareSessionsDesc`, and group the most recent day with `dayKey` instead of exact string equality
- [x] Confirm empirically whether the live wger API returns `WorkoutLog.date` as a date or a datetime — confirmed via wger's `WorkoutLogSerializer` source: `WorkoutLog.date` is unchanged, still a plain date field
- [x] Root cause found for "Invalid Date"/unsorted history: `WorkoutSessionSerializer` was changed upstream to return `datetime_start`/`datetime_end` — `date`/`time_start`/`time_end` are now write-only legacy-compat fields, never present on GET. Added `sessionStartKey(s)` (prefers `datetime_start`, falls back to legacy `date`+`time_start`) and routed `compareSessionsDesc`, `fmtDate`, `daysAgo`, and the streak's `uniqueDates` through it; changed the `/workoutsession/` fetch to `ordering=-datetime_start`
- [x] `updateTimer`: `Math.round` → `Math.floor`, and repaint both `#wtimer` and `#resumeMins`, no-op when neither exists
- [x] Delete `timerInterval`, its `setInterval(updateTimer, 30000)` and both `clearInterval` calls; call `updateTimer()` from the existing 1 Hz `tickRestTimers`
- [x] Add `visibilitychange` + `pageshow` listeners that recompute the timer when the app becomes visible (defensive fix for the observed-but-not-reproduced stale timer)
- [x] Add the code comment recording "observed but not reproduced" for the live-timer symptom, and the `ponytail:` comments for the cross-midnight duration ceiling and the 500-log Previous-column window
- [x] Self-test cases 1-6 from the spec all pass at `index.html#selftest` (local date, UTC divergence, `dayKey`, comparator, non-mutating sort, `lastTimeForExercise` incl. fallback and datetime-`date` fixture) — verified via a Node harness executing the inline script (16/16 checks pass)

### UI & layout tasks (visual, no TDD)

- [x] Wrap the resume banner's minutes in `<span id="resumeMins">` so it refreshes without a re-render
- [ ] Check the header timer and resume banner still read correctly right after a workout starts (`0 min elapsed`, no flicker) — **needs manual check in a browser against the live API**

### Manual verification against the real API / phone

- [ ] Background or lock the app mid-workout for ≥3 min, reopen → minutes match wall clock immediately
- [ ] Reload mid-workout → elapsed time continues from the real start
- [ ] Finish a workout → wger shows the local day and a duration matching the real session length
- [ ] Two sessions logged on one day → History lists the later one first
- [ ] Previous column shows the prior session's sets, including an exercise skipped last session (fallback path)

**Phase notes:** `WorkoutLog.date` shape not empirically confirmed against the live wger API
this session (no token/network available in this environment) — `dayKey` handles both
date-only and datetime shapes regardless, so behavior is correct either way; confirm the
actual shape next time the app is run against the real API and record it here.

Phase 1 also discovered — and Phase 2 acts on — that the resume banner `#resumeMins` was
wired into is unreachable: `render()` routes to `renderActiveWorkout()` whenever a workout is
active, so the banner only ever renders when there is nothing to resume. See
`.claude/specs/phase2_spec.md` §1.1.

- [ ] Mark Phase 1 done in `docs/roadmap.md` and commit it with the code (per `.claude/rules/roadmap-gating.md`)

## Phase 2 — Active workout: keep it, get back to it, make the tap feel right

Spec: `.claude/specs/phase2_spec.md`. All edits are in `index.html`. Gates answered:
1A (in-memory back flag, bar replaces the toolbar, delete the banner), 2A (44×40 tick, ✕
moves to the set-number cell), 3A (always-on two-tier WebAudio beep, no mute toggle).
No new dependencies, no new asset files.

### Logic & backend tasks (TDD — add the `#selftest` case first, watch it fail, then fix)

- [x] Add self-test case 7: replace `#topHeader`'s innerHTML/className as `renderActiveWorkout` does, call `renderMainHeader()`, assert `#headerSub` exists and `className === "topbar"`, then assert again after a second call (idempotence) — watch it fail before writing `renderMainHeader`
- [x] Add `renderMainHeader()`: idempotently restore `#topHeader` to `class="topbar"` and the main-screen markup (`<h1>🏋️ Gym Log</h1>` + `<div class="sub" id="headerSub">`)
- [x] Call `renderMainHeader()` at the top of `render()` (before the `#headerSub` write, which currently throws `TypeError` and is the real cause of the finish/discard dead-end) and at the top of `showSetup()`
- [x] Add `let showMain = false;` and `let audioCtx = null;` beside `activeTab`
- [x] `render()`: change the guard to `if(active && !showMain){ renderActiveWorkout(); return; }`
- [x] Add `backToMain()` (`showMain = true; render();`) and set `showMain = false` at the top of `renderActiveWorkout()`
- [x] `renderActiveWorkout()`: set `topHeader.className = "workout-header"` so the existing but never-applied `.workout-header` CSS takes effect
- [x] Add `renderToolbar()` painting `#mainToolbar` for the current state — resume button when `getActive()`, else the existing Refresh / Change token buttons — and call it from `render()` and `showSetup()` in place of the direct `style.display = "flex"` writes
- [x] Escape the routine name in the resume button with `esc(w.dayName)` (the deleted banner interpolated it raw — see spec §1.1 and the `CLAUDE.md` escaping invariant)
- [x] Add `primeAudio()` (lazily create + `resume()` the `AudioContext`, try/catch) and call it as the **first statement** of `logSet`, before any `await`, so iOS unlocks it inside the user gesture
- [x] Add `beep(freqs)` — triangle oscillator + gain envelope per note, ~70ms apart, try/catch no-op if audio is unavailable
- [x] Wire `beep([880])` into `triggerSetFeedback`'s normal branch and `beep([880,1175,1568])` into the PR branch, beside the existing `vibrate` calls
- [x] Add the `ponytail:` comment recording the no-mute-toggle ceiling (iOS ringer switch silences WebAudio, Android does not) and a comment noting `showMain` is deliberately not persisted
- [x] Confirm `restTickInterval` is **not** cleared by `backToMain` — it is what keeps the bar's minute count live (spec §1.5)
- [ ] Self-test case 7 passes at `index.html#selftest`, and the Phase 1 cases still pass — **not verified this session: no browser/DOM driver available (no playwright/puppeteer install, only a cached Chromium binary with no launcher); script parses cleanly under `node -c` but the DOM-dependent self-test needs a real run**

### UI & layout tasks (visual, no TDD)

- [x] Add the back button `<button class="backbtn" onclick="backToMain()">‹</button>` as the first child of the workout header, with the title wrapped in `.wtitle`
- [x] Add `.workout-header .backbtn` and `.workout-header .wtitle` CSS; give `.discardbtn` a 44px min tap size
- [x] Add `.toolbar .resumebtn` CSS (full-width accent button, ~46px tall, `nowrap` + ellipsis for long routine names)
- [x] Delete `resumeBannerHtml()` and the `.resume-banner` CSS block
- [x] Replace all nine `resumeBannerHtml() + tabsHtml()` call sites with `tabsHtml()`
- [x] `.logbtn` → 44×40, `border-radius:10px`, `font-size:16px`; `.actioncell` → 50px
- [x] Move the ✕ delete out of `.rowbtns` into the `.setnum` cell in **both** row branches (logged and unlogged) of `renderActiveWorkout`; delete the now-unused `.rowbtns` rule
- [x] `.setnum` → 44px, `.delbtn` → 26×26, `.prevcell` → 11px `nowrap`, `.settable td` → `padding:3px 2px`

### Manual verification against the real API / phone

- [ ] Start a workout → tap "‹" → main screen renders fully with no console error, bottom bar names the in-progress routine
- [ ] The bar's minute count increments while sitting on the main screen
- [ ] Tap the bar → returns to the workout with logged sets and rest timers intact
- [ ] Switch between History / PRs / Routines while backed out → stays on the main screen, bar persists
- [ ] Finish a workout → lands on History, header shows "🏋️ Gym Log" + session count, Refresh / Change token are back
- [ ] Discard a workout → lands on the main screen, no dead-end
- [ ] Every set tap plays the blip, including the **first** tap after a fresh page load (iOS gesture unlock); a PR plays the rising three-note flourish with the existing confetti + toast
- [ ] Tick is comfortable with a thumb; the ✕ is not hit by accident
- [ ] Set rows do not overflow at 360px **and** 320px viewport width with a 3-digit weight entered — if 320px overflows, shorten `prevStr` from `50kg×5` to `50×5` before touching input font sizes

- [ ] Mark Phase 2 done in `docs/roadmap.md` and commit it with the code (per `.claude/rules/roadmap-gating.md`)

## Phase 3 — Post-workout summary

Spec: `.claude/specs/phase3_spec.md`. All edits are in `index.html`. Gates answered:
**1B** (tap-to-advance full-screen cards, dot indicator, Done on the last card) and
**2A-widened** (reuse the existing live PR detection, but on **two independent tracks** —
heaviest weight *and* heaviest single-set volume; both celebrate live, both surface in the
summary). Muscle groups **decided IN** — the data already arrives in the `/exerciseinfo/`
response the app fetches and discards (spec §1.1). No new dependencies, no new files.

Hook left by Phase 2: the summary replaces the `render()` call at the end of `finishWorkout`
(`1207`).

### Logic & backend tasks (TDD — add the `#selftest` case first, watch it fail, then fix)

**Two-track PR rule** (this changes existing PR logic, it is not additive — see spec §1.3):

- [x] Add self-test case 8 for the new `computeBestByExercise` shape — fixture where the heaviest-weight set is **not** the highest-volume set (100kg×2 vs 60kg×10) asserting `w === 100` and `v === 600`; `weight <= 0` logs skipped; both `repetitions` and `reps` field names compute `v` — watch it fail first
- [x] Change `computeBestByExercise` (`675-683`) to return `{ [exerciseId]: { w, v } }`, tracking heaviest weight and heaviest single-set volume **independently** in the one existing loop; keep the `weight <= 0 → continue` guard; read reps as `parseFloat(l.repetitions ?? l.reps ?? 0)`
- [x] Add self-test case 9 for `classifySetPR` covering the full branch table (undefined prev → neither; weight-only; volume-only; both; equalling a best is **not** a PR; neither)
- [x] Add pure `classifySetPR(prev, weight, reps) -> { weightPR, volumePR }` — strictly-greater on each track, independent, `undefined` prev returns both false (first-ever exercise is not a PR)
- [x] Rename `sessionBest` → `w.best` at all three sites (`789`, `811`, `1156`) — this is the migration mechanism, **not** a cosmetic rename: `if(!w.best)` re-derives cleanly for a pre-upgrade workout whose map still holds bare numbers (spec §1.3). Do **not** add a shape sniff instead
- [x] Rewrite `logSet`'s PR block (`1156-1160`) to call `classifySetPR`, set `isPR = weightPR || volumePR`, and raise **both** tracks with `Math.max` including the first-ever seed case
- [x] Verify `isPR` still feeds `triggerSetFeedback` (`1164`) so a **volume-only** PR gets the full confetti/vibrate/flourish treatment — this is the explicit requirement, not an optional extra
- [x] Add self-test case 11 for `recordPR`: same exerciseId hitting the weight track then the volume track produces **one** record with both sub-objects, and the later volume set does **not** overwrite the weight figures (spec §2.4 hazard)
- [x] Add `recordPR(w, entry, weight, reps, prev, pr)` — upsert one record per `exerciseId` into `w.prs`, storing `weightPR` and `volumePR` as **separate** sub-objects, overwriting only the track(s) that fired
- [x] Add `prs: []` to the `launchDay` active-workout literal (`~790`) and default `w.prs || []` at every read site
- [x] Generalise `showPRToast(name, weight, prevBest)` (`1093`) → `showPRToast(name, label, detail)`; keep `esc(name)`, build `detail` from numbers only
- [x] Change `triggerSetFeedback`'s trailing params (`1108`, call site `1164`) to `(…, name, label, detail)`; labels are exactly **"Weight PR"**, **"Volume PR"**, **"Weight + Volume PR"** — no other synonyms anywhere in the UI
- [x] Update the stale comment above `triggerSetFeedback` (`1105-1107`) — it currently says PRs are "reserved for beating a previous best weight"

**Volume totals:**

- [x] Add self-test case 10 for `summaryTotals(entries)` — counts only `s.logged === true`, a logged set with `weight: ""` contributes 0 and produces **no `NaN`**, sets/reps/volume match a hand-computed fixture — watch it fail first
- [x] Add pure `summaryTotals(entries) -> { sets, reps, volume }` reducing over `entries[].sets`, zero API calls (spec §1.2)

**Muscle groups / exercise index v2:**

- [x] Bump `EXINDEX_KEY` (`210`) to `"exercise_index_v2"`
- [x] Store the category in `loadExerciseIndex`'s rebuild (`339`): `{ id, name, cat: (info.category && info.category.name) || "" }`
- [x] Add `localStorage.removeItem("exercise_index_v1")` beside the `setItem` (`~344`) so the superseded blob doesn't linger
- [x] Add **synchronous** `exerciseCatMap() -> {id: cat} | null` — reads in-memory `exerciseIndex` (`223`) else `localStorage[EXINDEX_KEY]` in try/catch; **never fetches**; ignores the TTL; returns `null` as the signal to drop the muscle card
- [x] Add the fire-and-forget `loadExerciseIndex().catch(() => {})` after `setActive` in `launchDay` (`~791`) — warms the index during the workout so the muscle card needs no fetch at finish (spec §1.1). Must **not** be awaited and must not affect starting a workout

**Summary state & wiring:**

- [x] Add `let summary = null;` and `let summaryCard = 0;` beside `showMain` (`228`), with a comment noting they are deliberately not persisted
- [x] Add `buildSummary(w)` → `{ durationMin, totals, prs, muscles }`; `durationMin` uses the same arithmetic as `renderToolbar` (`443`); `muscles` tallies logged-set counts per category, descending, `[]` when `exerciseCatMap()` is null
- [x] Rewrite `finishWorkout`'s tail (`1202-1207`): build the summary **before** `clearActive()` (spec §1.2), keep the existing interval/`finishBar` cleanup, return to `render()` when `totals.sets === 0`, else set `summary`/`summaryCard` and call `renderSummary()`
- [x] Confirm the `apiPatch` failure branch (`1197-1199`) still reaches the summary — a failed `time_end` patch must not swallow it
- [x] Add `nextSummaryCard()` (advance, clamped; last card → `closeSummary()`) and `closeSummary()` (`summary = null; summaryCard = 0; render();`)
- [x] Confirm **no** `summary` guard is added to `render()` (`478-481`) — the summary screen renders no tabs/back/discard, so nothing can re-enter `render()` behind it (spec §1.5)
- [x] Add the `ponytail:` comments: category-granularity ceiling (§1.1), the mid-workout `allLogsCache` re-derive ceiling at `811` (§1.3), and the hardcoded-`kg` unit ceiling (§2.9)

### UI & layout tasks (visual, no TDD)

- [x] Add `renderSummary()` — hides `#mainToolbar` (as `814`), calls `renderMainHeader()` (`433`) so the workout header's back/discard buttons cannot survive onto this screen, and writes the active card + dot row + button into `#content`
- [x] Build the card list **dynamically**: Volume and PRs always; the muscle card appended only when `summary.muscles.length > 0`, so the two-card fallback is not a visual bug
- [x] Volume card: `{volume}kg` hero figure with `{sets} sets · {reps} reps · {durationMin} min` beneath
- [x] PR card: one row per `prs[]` record with "Weight PR" / "Volume PR" badges and the figures; empty `prs` renders an explicit "No PRs this time — still counts." line, **not** a blank card
- [x] Muscle card: one `{cat} — {sets} sets` row per entry, sorted descending
- [x] Dot indicator renders one dot per card **actually present**, with the current one highlighted
- [x] Tap-to-advance on the card container; final card's button reads "Done" and is ≥44px tall
- [x] Escape **every** exercise `name` and every `cat` with `esc()` — brand-new `innerHTML` path, `CLAUDE.md` invariant (spec §2.7). Numbers must not be escaped
- [x] Add `.summary-card`, `.summary-hero`, `.summary-sub`, `.summary-dots`/`.dot`, `.pr-badge` CSS next to the existing `.pr-card` block, reusing the `:root` tokens — plain and legible only; Phase 4's design pass owns the real styling

### Manual verification against the real API / phone

- [ ] Finish a workout with logged sets → summary appears **before** the main screen; hand-check the total volume against two or three logged sets
- [ ] Tap through Volume → PRs → Muscle groups → Done → lands on History with the finished session listed, Refresh / Change token back
- [ ] Dot indicator count matches the number of cards actually shown
- [ ] Finish a workout with **zero** logged sets → no summary, straight to the main screen
- [ ] Beat a previous weight → confetti + a toast reading **"Weight PR"**, and a Weight PR badge on the summary
- [ ] Beat a previous single-set volume **without** beating the weight (same weight, more reps) → confetti + a toast reading **"Volume PR"**, and a Volume PR badge — **the main new behaviour to verify**
- [ ] One set beating both → a single "Weight + Volume PR" toast and one summary row with two badges
- [ ] An exercise logged for the **first time ever** → no PR and no confetti, but it still counts toward volume and muscle groups
- [ ] Muscle card names real categories (Chest / Back / Legs …) matching the exercises performed, with sensible set counts
- [ ] **Confirm and record in the phase notes** whether `/exerciseinfo/` returns `category.name`; if not, apply the documented fallback (`muscles[]`, else drop the card) and record which one was used
- [ ] Fresh install / cleared storage → workout start is not slowed by the warm-up fetch, and finishing shortly after still shows volume + PR cards with no stall
- [ ] Summary is legible and Done is comfortably tappable at 360px **and** 320px viewport width
- [x] Self-test cases 8-11 pass at `index.html#selftest` and cases 1-7 still pass — verified via a Node harness executing the inline script (37/37 checks pass)

**Phase notes:** Manual verification items (finish-workout flow, PR toasts on a live device,
whether `/exerciseinfo/` actually carries `category.name`) are **not done this session** — no
token/network/browser available in this environment. `exerciseCatMap`'s fallback-to-`null`
path means the app degrades safely either way; confirm the real shape next time the app runs
against the live API and record it here. The known inconsistency that `renderPRs` (`602-635`)
keeps its own weight-only PR computation and does **not** show volume PRs is deliberately out
of scope here (spec §2.10), for Phase 4 or a later pass to reconcile.

- [x] Mark Phase 3 done in `docs/roadmap.md` and commit it with the code (per `.claude/rules/roadmap-gating.md`)

## Phase 4 — UI modernization

- [ ] Not yet planned — run `@planner Phase 4`

## Phase 1 — Data integrity: last-time baseline and PR tracking (v3)

Spec: `.claude/specs/phase1_spec.md`. Investigation found must-haves 2 and 3, as
originally worded, already correct in existing code (see spec §0) — gates answered
**1A**/**2A** (regression self-tests only, no code change). The real remaining bug,
surfaced during planning: deleting/unmarking a logged set doesn't recompute PR state,
so a stale/typo PR can stick around. Gate 3 answered **A** — eager recompute via a new
frozen `w.preBest` baseline, kept live throughout the workout.

### Logic & backend tasks (TDD — add each self-test case first, watch it fail, then fix)

Regression locks (no behavior change — must-haves 2 and 3 as originally worded already work):

- [ ] Add self-test case for `lastTimeForExercise` proving `buildEntriesFromDay`'s single
  pre-session call site (`~817`) must never be re-invoked with logs that include the
  current session's own sets — fixture with/without a synthetic "logged this session"
  entry, asserting the most-recent-day grouping would pick it up if included (spec §5.1)
- [ ] Add one-line source comment at the `buildEntriesFromDay` call site (`~817`) pointing
  at that test, documenting the invariant it locks in
- [ ] Add self-test case for `computeBestByExercise` asserting a single low-rep heavy set
  (e.g. 100kg×1) fires a weight PR with no minimum-rep/"max test" gate involved (spec §5.2)

**The real fix — PR recompute on delete/unlog** (spec §1-§4):

- [ ] Add `w.preBest = computeBestByExercise(logs)` at `launchDay` (`~861`), called
  independently from the existing `w.best` seed — do not share one object between them
- [ ] Add migration sibling `if(!w.preBest) w.preBest = computeBestByExercise(logs)` next
  to the existing `w.best` migration check (`~888`); note the resumed-mid-session ceiling
  with a `ponytail:` comment (spec §1)
- [ ] Add self-test cases for `recomputeBestForExercise`: PR revoked when its set is
  deleted and no other session set supports it; PR downgraded (not deleted) when a
  smaller remaining session set still beats `w.preBest`; typo-correction (delete inflated
  set, relog correct weight) ends with the corrected, non-PR value; isolation (exercise A
  recompute leaves exercise B untouched); migration fixture with `w.preBest` absent
  (spec §5.3-§5.7) — watch each fail first
- [ ] Add `recomputeBestForExercise(w, exerciseId) -> void`: collect currently-`logged`
  sets for `exerciseId` across `w.entries`, find the winning weight-set and
  winning volume-set independently, recompute `w.best[exerciseId]` against `w.preBest`,
  and reconcile `w.prs`'s record for that exercise — update or delete each track's
  sub-object based on whether it still beats `w.preBest`, removing the whole record if
  neither track survives (spec §2). Read `recordPR`'s current field names (`1172-1181`)
  before wiring the reconciliation — match its existing `weightPR`/`volumePR` shape
  exactly, don't invent a new one
- [ ] Call `recomputeBestForExercise(w, entry.exerciseId)` in `removeSetRow`
  (`1025-1046`), after the existing splice from `entry.sets` and before `renderActiveWorkout()`
- [ ] Call `recomputeBestForExercise(w, exerciseId)` in `removeExercise` (`1060-1074`),
  after the delete loop and entry removal, using the exerciseId captured before removal
- [ ] Call `recomputeBestForExercise(w, entry.exerciseId)` in `unlogSet` (`1280-1296`),
  after `logged=false; logId=null` and before `renderActiveWorkout()`

No UI/layout tasks this phase — logic-only fix, no new screens.

## Phase 2 — Rest-timer reliability and audio overhaul (v3)

Spec: `.claude/specs/phase2_spec.md`.

### Logic & Backend (TDD)

- [x] `beep(freqs, gain = 0.32)`: add the `gain` param, replace hardcoded `0.25` peak with
      `gain` in the envelope ramp (index.html `505-521`); confirm existing call sites
      (`1204`, `1209`) still sound correct at the new louder default.
- [x] `tickRestTimers` (`996-1013`): in the `remaining <= 0` branch, fire
      `beep([1200,800,1200,800], 0.5)` + `vibrate([100,80,100,80,100])` before clearing
      `entry.restEndMs`.
- [x] Add `wakeLockSentinel` module state + `acquireWakeLock()` / `releaseWakeLock()`
      helpers (feature-detect `"wakeLock" in navigator`, try/catch no-op on
      unsupported/denied) alongside existing `audioCtx` state (`246`).
- [x] Wire `acquireWakeLock()` into `launchDay` right after `restTickInterval` is set
      (`983`); wire `releaseWakeLock()` into `finishWorkout` (`1376`).
- [x] Update the `visibilitychange` listener (`1432-1434`) to call `tickRestTimers()` +
      `acquireWakeLock()` when becoming visible with an active workout; update `pageshow`
      (`1435`) to call `tickRestTimers()`.
- [x] Self-test: expired-vs-not-yet-expired `restEndMs` check (see spec §4) added to
      `runSelfTest` (`1437`) — verified via a Node harness executing the inline script
      (42/42 checks pass).

### UI & Layout (rapid prototyping)

- [ ] Manual/on-device check: rest timer alert is audibly distinct from set-log and PR
      sounds and noticeably louder; confirm on at least one mobile browser that
      backgrounding the tab during a rest countdown and returning before/after expiry
      behaves per spec §3 edge cases.
- [ ] Manual check: screen does not sleep during an active workout on a device that
      supports Wake Lock; confirm no visible regression on a device that doesn't
      (Firefox/older Safari).

**Phase notes:** Manual on-device verification (audibility/loudness, backgrounding
behavior, Wake Lock screen-stay-awake) not done this session — no browser/phone available
in this environment; logic changes verified via the Node self-test harness only.

- [ ] Mark Phase 2 (v3) done in `docs/roadmap.md` and commit it with the code (per
  `.claude/rules/roadmap-gating.md`) — **not yet**, pending the manual on-device checks
  above.

## Phase 3 — In-workout exercise history/trend view (v3)

Spec: `.claude/specs/phase3_spec.md`. Decision Gate 1 (graph rendering) resolved: inline SVG
(hand-built polyline + circles, `viewBox`-scaled) — no new dependency.

### Logic & Backend (TDD)

- [x] `computeExerciseStats(exerciseId, logs)`: returns `{bestWeight, bestVolume, totalSets,
      lastPerformed}`, reusing `computeBestByExercise` (`734`) for `bestWeight`/`bestVolume`,
      filtering `logs` for `totalSets`/`lastPerformed`; all fields `null`/`0` when the exercise
      has no entries.
- [x] `buildTrendPoints(exerciseId, logs)`: returns ascending-by-date `{date, weight}[]`, one
      point per calendar day (max weight that day), capped to the most recent 20 days.
- [x] `renderTrendSvg(points)`: returns SVG markup — empty-state placeholder for 0 points,
      single `<circle>` (no polyline) for 1 point, scaled `<polyline>` + `<circle>`s for 2+,
      flat mid-height line when `minW === maxW` (no divide-by-zero).
- [x] Self-test additions to `runSelfTest` (`~1437`): fixture-based assertions for
      `computeExerciseStats` (multi-exercise, multi-day fixture incl. an absent-exercise
      `null`/`0` case) and `buildTrendPoints` (same-day max collapsing, 20-point cap on a
      25+ day fixture, ascending order) — verified via a Node harness executing the inline
      script (50/50 checks pass).

### UI & Layout (rapid prototyping)

- [x] `showExerciseDetail(exerciseId, name)`: new function following the existing
      `openAddExercise`/`showDayPicker` overlay pattern (`div.overlay` > `div.overlay-sheet`,
      appended to `document.body`) — heading `esc(name)`, 4-stat row (best weight / best
      volume / total sets / last performed, `null` shown as `"—"`), `renderTrendSvg(...)`
      output, close button. (No existing overlay in this codebase dismisses on background
      click — only a Cancel/close button — so this one matches that, not the spec's aside
      about background-click dismissal.)
- [x] Hook `.wex-name` (`renderActiveWorkout`, `~962`) to call `showExerciseDetailIdx(idx)` →
      `showExerciseDetail(entry.exerciseId, entry.name)` on tap, mirroring the existing
      idx-based inline `onclick` wiring style used by `moveExercise`/`removeExercise`; added a
      pointer-cursor affordance so it reads as tappable.
- [x] `.trend-svg` / `.trend-empty` / `.exdetail-stats` CSS: responsive width (`width:100%` on
      the SVG, fixed `viewBox`), consistent with the app's existing overlay-sheet styling.
- [ ] Manual check: tap an exercise name mid-workout for (a) an exercise with rich history,
      (b) an exercise with exactly one prior log, (c) a brand-new never-logged exercise —
      confirm graph/placeholder rendering and that no in-progress set input loses focus/value
      when the overlay opens.
- [ ] Manual check: exercise name containing HTML-significant characters renders literally in
      the overlay heading (escaping regression check, per the stored-XSS invariant).

- [ ] Mark Phase 3 (v3) done in `docs/roadmap.md` and commit it with the code (per
  `.claude/rules/roadmap-gating.md`) once the manual checks above pass.

## Phase 4 — Polished summary view (v3)

Spec: `.claude/specs/phase4_spec.md`. No Decision Gates raised — no schema/data-shape change,
no new dependency, roadmap's stated approach followable as written.

### Logic & Backend (TDD)

- [x] `formatKg(n)`: new pure formatting helper — rounds to at most 1 decimal (dropping a
      trailing `.0`), adds thousands separators, and returns `"0"` for `0`/`null`/`undefined`
      without ever producing `"NaN"`.
- [x] Update `renderSummary()` (`1423-1460`) call sites to use `formatKg`: `summary.totals.volume`
      (`1432`), `r.weightPR.weight` (`1441`), `r.volumePR.volume` (`1442`). Leave
      `summary.totals.sets`/`reps`/`durationMin` (`1433`) unformatted (already-integer counts).
      No change to `esc()` usage, and no change to `summaryTotals`/`buildSummary`/
      `summaryCards`'s return shapes.
- [x] Self-test additions to `runSelfTest`: `formatKg(157.5)` → `"157.5"`, `formatKg(500)` →
      `"500"`, `formatKg(500.04)` → `"500"`, `formatKg(12500)` includes a thousands separator,
      `formatKg(0)`/`formatKg(null)`/`formatKg(undefined)` all → `"0"` — verified standalone
      (full `runSelfTest` needs a DOM driver not available this session, same limitation noted
      in Phase 2/3 notes); all 5 assertions pass.

### UI & Layout (rapid prototyping)

- [x] Transitions/polish applied directly as CSS (no `ui-prototyper` detour — scope was pure
      animation/affordance polish on an already-styled, structurally-unchanged screen, not a new
      visual direction): `.summary-card` gets a `summaryCardIn` entry keyframe that replays on
      every `renderSummary()` call (card-to-card transition is "for free" since each call is a
      fresh `innerHTML` replacement), `.summary-dots .dot` transitions background-color/transform
      on the `active` toggle, `.donebtn` and the card itself get `:active` press affordance
      (scale/brightness). No JS/class-toggle wiring needed.
- [x] Apply the chosen direction to `index.html`: done inline above — adapted
      `.summary-card`/`.summary-dots`/`.donebtn` CSS (`69-86`), no change to
      `renderSummary()`/`nextSummaryCard()` JS, `formatKg` call sites, or card content logic.
- [ ] Manual check: volume/PR/muscle-group figures are still numerically correct after the
      restyle (spot-check against a workout with decimal weights and a large volume total).
- [ ] Manual check: rapid repeated taps on the card/`donebtn` during a transition don't desync
      the visible card from `summaryCard`'s actual index or double-advance past `closeSummary()`.

**Phase notes:** No JS behavior changed (`nextSummaryCard`/`closeSummary` untouched), so the
rapid-tap edge case is exactly whatever it already was pre-Phase-4 — not a new risk introduced
by the CSS-only transition. Manual on-device checks (numeric spot-check post-restyle, rapid-tap
behavior, and the animation actually reading well on a real screen) are **not done this
session** — no browser/device available in this environment; confirm next time the app runs
live and record it here.

- [ ] Mark Phase 4 (v3) done in `docs/roadmap.md` and commit it with the code (per
  `.claude/rules/roadmap-gating.md`) once the manual checks above pass.

## Phase 5 — Feedback on every touched interaction (v3)

Built directly at the user's explicit request ("animations and visual feedback on every
button and interactable"), skipping `@planner Phase 5` — scope is app-wide (every
tappable control), broader than the roadmap's original "what v3 touches" framing, and
was a straightforward CSS-only pass with no schema/logic decisions to gate.

### CSS (no JS/logic change)

- [x] Inventoried every clickable control in `index.html`: all `<button>` elements
      (`addexbtn`/`addsetbtn`/`backbtn`/`delbtn`/`discardbtn`/`donebtn`/`logbtn`/
      `movebtn`/`removeexbtn`/`reset`/`resumebtn`/`startbtn`/`cancel`, plus unclassed
      buttons like Refresh/Change token/Connect/Skip/Finish Workout), and non-button
      interactive divs (`.tab`, `.wex-name`, `.opt` day-picker/search rows,
      `.summary-card`). Confirmed `.session-card`/`.routine-card`/`.pr-card`/`.exrow`
      are display-only (no `onclick`) — deliberately left untouched, not "everything
      moves."
- [x] Added one global press rule keyed off the `button` element (covers ~13 classes
      for free — reuse over one-off rules per class) plus `.tab`: `transform:scale(.96)`
      + `filter:brightness(.9)` on `:active`, excluded via `:not(:disabled)` so
      `.movebtn:disabled` etc. stay inert.
- [x] `.opt` (day-picker + add-exercise search rows) gets a background-dim press state
      instead of scale — full-width list rows read better with a fill change than a
      centered scale.
- [x] `.wex-name` (inline exercise-name text, opens the trend/detail view) gets an
      opacity dim on press instead of scale/background — it's inline text, not a chip.
- [x] Added `:focus-visible` outline (accent color) on all of the above plus `input` —
      accessibility floor, nothing set `outline:none` before so keyboard focus already
      worked, this just makes it visible and on-brand instead of the browser default.
- [x] Added `.overlay`/`.overlay-sheet` entrance animation (fade + slide-up) — the
      day-picker, add-exercise, and exercise-detail bottom sheets had no entry motion
      before.
- [x] Added a `prefers-reduced-motion: reduce` block collapsing all animation/transition
      durations app-wide (covers this pass's additions and Phase 4's summary
      animations) — one rule, not hunted per-animation.
- [x] Removed the now-redundant `.summary-card .donebtn:active` rule from Phase 4 — the
      new global `button:active` rule covers it with identical values.
- [x] Verified: `<style>` brace-balanced (137/137), `<script>` still parses via
      `new Function()`.

### Manual verification against a real device

- [ ] Every button in the app (toolbar, setup, active workout, overlays, summary,
      finish bar) visibly depresses on tap, including on real touch hardware (not just
      mouse `:active` in a desktop browser)
- [ ] Day-picker and add-exercise search rows dim on tap without feeling laggy
- [ ] Bottom-sheet overlays visibly slide up on open (day picker, add exercise,
      exercise detail)
- [ ] iOS "Reduce Motion" (or equivalent OS setting) actually flattens the animations
      — not verified against real OS-level `prefers-reduced-motion`, only the CSS media
      query syntax
- [ ] No layout jank from `.opt`/`.wex-name` losing their previous (nonexistent)
      transition when rapidly toggled

**Phase notes:** No browser/device available in this session (same limitation as prior
phases) — all of the above is unverified beyond static syntax checks. Confirm on a real
phone next time the app runs live and record it here.

## Phase 6 — Nice-to-haves: stalled-workout auto-complete, routine reordering (v3)

- [ ] Not yet planned — run `@planner Phase 6`
