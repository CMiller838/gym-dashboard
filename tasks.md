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
- [ ] Confirm empirically whether the live wger API returns `WorkoutLog.date` as a date or a datetime; record the answer in the phase notes — **not done: needs a live API call, see phase notes below**
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
