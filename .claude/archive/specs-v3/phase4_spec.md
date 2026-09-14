# Phase 4 (v3) — Polished summary view (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-have 6 from `docs/outline-v3.md`. Depends on Phase 1 (v3) only in that the
underlying volume/PR figures must already be correct before locking in their formatting —
no new dependencies, no new endpoints, no change to what data the summary reads.

## 0. What investigation found (read this before touching code)

- `summaryTotals(entries)` (`764-774`) sums logged sets only: `{ sets, reps, volume }`, where
  `volume += w*r` per logged set. `w`/`r` come from `+s.weight || 0` / `+s.reps || 0` — since
  wger allows decimal weights, `volume` can be a non-integer float (e.g. `157.5`), and there is
  no cap on magnitude, so large workouts can produce long unformatted numbers.
- `buildSummary(w)` (`1399-1415`) returns `{ durationMin, totals, prs, muscles }`.
  `durationMin` is `Math.floor` of elapsed minutes (already an integer, no PR precision issue).
  `prs` is `w.prs` as accumulated live during the workout by `recordPR()` (`1271`) — summary
  does **not** call `computeBestByExercise` itself, it just reads what's already been recorded.
  `muscles` is a `{cat, sets}[]` sorted descending by `sets`, built from `exerciseCatMap()`.
- `summaryCards()` (`1417-1421`) returns a plain string array driving which card is shown:
  always `["volume","prs"]`, plus `"muscles"` if any muscle groups were logged. This is the
  existing carousel/dots content model — reused as-is, not touched by this phase's data tasks.
- `renderSummary()` (`1423-1460`) does a **direct `innerHTML` replacement of `#content`** —
  it is not overlay-based (unlike `openAddExercise`/`showDayPicker`/`showExerciseDetail`, which
  append/remove a `.overlay` node). Raw numbers are interpolated directly with no formatting:
  `${summary.totals.volume}kg` (`1432`), `${r.weightPR.weight}kg × ${r.weightPR.reps}` (`1441`),
  `${r.volumePR.volume}kg vol` (`1442`), `${summary.totals.sets} sets · ${summary.totals.reps}
  reps · ${summary.durationMin} min` (`1433`). `esc()` (`408`) is already correctly applied to
  every API-derived string in this function — `r.name` (`1444`) and `m.cat` (`1449`) — this
  phase must preserve that, not touch the escaping.
- `nextSummaryCard()` (`1462-1467`) advances `summaryCard` and re-renders, or calls
  `closeSummary()` once past the last card. `closeSummary()` (`1469-1473`) clears `summary`/
  `summaryCard` state and calls `render()` — no DOM node to remove since it was never an overlay.
- Opened from `finishWorkout()` (`1475+`), which builds `summary = buildSummary(w)` then calls
  `renderSummary()`. Card advance/close are wired via inline `onclick="nextSummaryCard()"` on
  both the card body (`1455`) and the button (`1458`, with `event.stopPropagation()`).
- CSS for the affected classes (`69-83`) has **no transitions or animations at all** today —
  `.summary-card` is a static flex column, `.summary-hero`/`.summary-sub` are static text
  styles, `.summary-dots .dot` toggles an `active` background with no transition property. This
  confirms the redesign is purely additive polish, not a fix to broken behavior.
- No existing number-formatting helper in the file (grepped for `toLocaleString`,
  `Intl.NumberFormat`, a `fmt`-prefixed numeric function — only `fmtDate` (`417`, date-only) and
  `fmtRest` (`973`, rest-timer seconds) exist, neither applicable to weight/volume numbers). A
  new formatting helper is warranted per the ladder (rung 2 found nothing to reuse).

## 1. Decision Gates

None raised. Checked against this project's gating rules and none apply:
- **Tier 1 (schema/data-shape change, new dependency/endpoint):** not triggered — this phase
  changes no return shape of `summaryTotals`/`buildSummary`/`summaryCards`, adds no dependency
  (animations are plain CSS/JS, no library), and calls no new endpoint.
- **Tier 2 (roadmap's stated approach unfollowable, or clearly better path):** not triggered —
  "redesign transitions/formatting on top of existing correct data" is directly followable as
  written; nothing in the investigation surfaced a better path.
- **Tier 3 (reuse vs. build):** decided below, no gate needed.

## 2. Decisions (planner's own calls — Tier 3, no gate needed)

- **Screen mechanism:** keep the existing direct `innerHTML`-replacement-of-`#content` pattern
  (not converting to the `.overlay` pattern used by `openAddExercise`/`showExerciseDetail`).
  Converting it would be a structural change with no stated benefit — the roadmap asks for
  transitions/formatting polish, not a mechanism change — and CSS transitions work the same
  either way.
- **Carousel/dots structure:** keep `summaryCards()`'s existing card-list/dots model as-is;
  the redesign restyles how a card and the dots look/animate, not what cards exist or their
  order.
- **Number formatting scope:** introduce one new pure helper, `formatKg(n)`, used everywhere a
  weight/volume figure is rendered in the summary (`summary.totals.volume`, `r.weightPR.weight`,
  `r.volumePR.volume`). It rounds to a sensible display precision and adds thousands separators
  for readability, but the underlying `summaryTotals`/`buildSummary`/`w.prs` numbers are
  untouched — formatting is applied only at render time in `renderSummary()`, so no data schema
  changes and no re-derivation risk.
- **Animation/transition mechanism:** left for the UI-prototype step (see Section 3) rather than
  decided here — the exact class-toggle/transition approach is a visual design choice, not an
  architectural one, and prescribing it in this spec would just be redone by the prototype.

## 3. Changes

### `formatKg(n)` — new function
Pure formatting helper, no DOM/API access. Signature: `formatKg(n: number): string`.
- Round to at most 1 decimal place, and drop the decimal entirely when it's `.0` (e.g. `157.5`
  stays `"157.5"`, `500` stays `"500"`, `500.04` becomes `"500"` — never show more than one
  decimal digit of noise from float weight math).
- Add thousands separators for readability (`toLocaleString(undefined, {maximumFractionDigits:1})`
  covers both rounding and grouping in one call — no need for manual string splitting).
- `formatKg(0)` → `"0"`; `formatKg(null)`/`formatKg(undefined)` → `"0"` (defensive; summary
  numbers are always initialized to `0` upstream, but the helper should not throw or print
  `"NaN"` if ever called with a missing value).

### `renderSummary()` (`1423-1460`) — formatting call sites only
Replace each raw numeric interpolation of a weight/volume figure with `formatKg(...)`:
- `1432`: `${formatKg(summary.totals.volume)}kg`
- `1441`: `${formatKg(r.weightPR.weight)}kg × ${r.weightPR.reps}`
- `1442`: `${formatKg(r.volumePR.volume)}kg vol`
`summary.totals.sets`/`reps`/`durationMin` (`1433`) are already-integer counts with no
grouping/precision issue at realistic workout scale — leave unformatted. No change to `esc()`
usage, no change to `summaryTotals`/`buildSummary`/`summaryCards` return values.

### UI prototype + restyle (transitions and visual polish)
Not a direct-code task. Produce a UI prototype (via `ui-prototyper`) of the redesigned
post-workout summary screen using fake/dummy data matching the real shapes (`totals.volume`,
`totals.sets/reps`, `durationMin`, a `prs[]` list with both weight-PR and volume-PR cases, a
`muscles[]` list, and the dots/card-count states), covering:
- Entry transition when the summary first opens (replacing the current instant swap).
- Card-to-card transition on `nextSummaryCard()` (currently an instant re-render with no
  visual continuity).
- Dot indicator state change animation.
- Any hover/press affordance on the `donebtn`/card tap area.
Once a direction is chosen, apply it to `index.html` via `restyle-from-prototype`, which will
adapt the existing `.summary-hero`/`.summary-sub`/`.summary-card`/`.summary-dots` CSS (`69-83`)
and any minimal class-toggle wiring in `renderSummary()`/`nextSummaryCard()` needed to drive the
chosen transition — without altering the card content logic, the `formatKg` call sites above, or
`esc()` usage.

## 4. Edge cases the implementation must hold

- Decimal-weight volume (e.g. total volume `157.5`) → `formatKg` shows `"157.5"`, not
  `"157.50000000000003"` (float drift) or `"158"` (over-rounded).
- Large volume totals (e.g. `12500`) → thousands separator applied (`"12,500"` under default
  locale), not a raw run of digits.
- Zero-PR workout (`summary.prs.length === 0`) → existing "No PRs this time" message path
  (`1435-1436`) is untouched; `formatKg` is never called on that branch.
- A PR entry with only a `weightPR` or only a `volumePR` (not both) → only the present branch's
  `formatKg` call fires (`1441`/`1442` are independent `if` blocks already); no assumption that
  both exist.
- Rapid repeated taps on the card/`donebtn` while a transition is mid-animation (post-restyle)
  → `nextSummaryCard()`'s index advance/`closeSummary()` trigger logic (`1462-1467`) is unchanged
  by this phase, so behavior under fast tapping is whatever it already is today — restyle work
  should avoid introducing a new race (e.g. a transition that can be re-triggered mid-flight and
  desync the visible card from `summaryCard`'s actual value), but this phase does not add new
  debounce/lock logic beyond what the chosen prototype's transition needs.

## 5. Self-test additions (existing `runSelfTest`)

`formatKg` is a pure function — testable without DOM:
1. `formatKg(157.5)` → `"157.5"`; `formatKg(500)` → `"500"`; `formatKg(500.04)` → `"500"`.
2. `formatKg(12500)` → contains a thousands separator (`"12,500"` under default locale — assert
   via `.includes(",")` or an exact match, whichever the existing self-test's assertion style
   uses elsewhere in the file).
3. `formatKg(0)`, `formatKg(null)`, `formatKg(undefined)` → all `"0"`, never `"NaN"`.

## 6. Explicitly out of scope

- Any change to what data `summaryTotals`/`buildSummary`/`summaryCards` compute or return —
  this phase only changes how existing correct numbers are displayed and animated.
- Converting the summary screen to the `.overlay` pattern — stays a direct `#content` replacement
  (Section 2).
- New summary cards/metrics beyond volume, PRs, and muscle groups — the roadmap's exit condition
  is "existing summary data ... still correct and intact," not new data.
- Any change to `computeBestByExercise`, `recordPR`, or Phase 3 (v3)'s exercise-detail trend
  view — unrelated code paths, untouched by this phase.
