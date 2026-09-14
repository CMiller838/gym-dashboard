# Phase 5 — Readable 3-month exercise trend graph

## 0. What investigation found (from dispatch, no re-scan needed)

- `buildTrendPoints(exerciseId, logs)` (index.html:1004-1014): groups logs by `dayKey` (max
  weight per day), sorts ascending, `.slice(-20)`. Feeds off `allLogsCache` (already fetched via
  `apiAll('/workoutlog/?format=json&ordering=-date&limit=500')`, per Phase 3's investigation) —
  the date field already exists per log (`l.date`, ISO `YYYY-MM-DD` via `dayKey`), so a 3-month
  cutoff is a filter change only, no new endpoint/schema.
- `renderTrendSvg(points)` (index.html:1017-1030): viewBox `0 0 300 100`, index-even x-spacing
  (`i/(n-1)*300`), plain circles/polyline, no text labels. Special-cased `points.length === 1`
  (single centered dot).
- Call site `showExerciseDetail` (index.html:1039-1060) calls both back-to-back synchronously,
  no params today beyond `exerciseId`/`logs`.
- Existing date/format helpers already available for reuse (index.html:561-586):
  `formatKg(n)` (locale weight formatting), `localDateISO(d)` (Date -> `YYYY-MM-DD`), `dayKey(v)`
  (log date -> `YYYY-MM-DD`). `fmtDate` exists but includes a weekday (`"Wed, Sep 3"`) — too long
  for compact SVG labels, not reused for this.
- CSS (index.html:200-203): `.trend-svg{overflow:visible}`, `polyline{stroke:var(--accent)}`,
  `circle{fill:var(--accent)}`, `.trend-empty` for the no-data state. No existing `text` rule —
  one needs adding.
- Self-tests (index.html:1961-1970) assert the old 2-point grouping behavior and an explicit
  20-day cap (`buildTrendPoints(9, manyLogs).length === 20`) — the cap assertion is being
  replaced, the grouping assertions stay conceptually the same (still one point per day, max
  weight, ascending).
- No schema/data-shape change and no new dependency — confirmed against this project's "never
  add a dependency without confirming" rule; stays inline SVG.

## 1. Decisions

### Confirmed by user (Decision Gates)
- **Gate 1 — X-axis spacing: time-proportional (Path B).** Point x-position is computed from its
  real date offset within the fixed 3-month window, not even index spacing. A training gap now
  visibly shows as a horizontal gap.
- **Gate 2 — Label density: endpoints + min/max only (Path B).** Only the first point, last
  point, min-weight point, and max-weight point get a text label (date + weight); all other
  points remain plain dots. Protects readability regardless of logging frequency.

### Tier 3 (decided here, noted, not gated)
- **Window is fixed to `[today - 3 calendar months, today]`, independent of data**, not derived
  from the first/last logged point. This is what makes Gate 1's time-proportional spacing
  meaningful (a point near the window's start edge visually reads as "near the 3-month-ago
  mark", not just "first data we have"). Recommendation: implement via a shared
  `trendWindowBounds(now)` helper (below) called from both `buildTrendPoints` (filtering) and
  `renderTrendSvg` (x-scaling), so both always agree on the same bounds.
- **Both `buildTrendPoints` and `renderTrendSvg` take an optional trailing `now = new Date()`
  param.** Recommendation: this is the only practical way to unit-test a "trailing from today"
  window deterministically — production call sites never pass it, tests do.
- **Calendar-month arithmetic via `Date.setMonth(getMonth()-3)`, not a 90-day subtraction** —
  matches the roadmap's "calendar-month" wording. Known JS quirk accepted as-is: subtracting 3
  months from a 31st can roll into the next month if the target month is shorter (e.g. May 31 -
  3 months lands in early March, not Feb 28/29) — noted under Edge cases, not fixed.
- **New pure helper `trendLabelIndices(points)`** returning the deduped, sorted set of indices to
  label (first, last, argmin-weight, argmax-weight — first occurrence on ties). Recommendation:
  keep this separate from `renderTrendSvg` and unit-test it directly on data, rather than
  asserting against rendered SVG markup (brittle, same self-test style already used for
  `exercisePRHolders` in Phase 3).
- **Old `points.length === 1` special case in `renderTrendSvg` is deleted.** The
  time-proportional x formula (Gate 1) naturally places a single point at its real date offset
  in the window, so the special case is now dead code, not a needed simplification.
- **Label format:** value via existing `formatKg(weight)`; date via a new compact local formatter
  (`month short + day`, e.g. `"Sep 3"` — NOT `fmtDate`, which includes a weekday and is too wide
  for an SVG label at this scale). Recommendation: inline `toLocaleDateString(undefined,
  {month:'short', day:'numeric'})`, no new named helper needed for one call site.
- **Label placement to avoid clipping/overlap:** vertical — place label above the point
  (`y-18`/`y-8` for value/date lines) unless the point's `y <= 25` (too close to the viewBox top),
  in which case place it below (`y+14`/`y+24`). Horizontal — `text-anchor: start` when `x <= 20`,
  `end` when `x >= 280`, `middle` otherwise, so edge labels don't run off the (visually-overflowing)
  viewBox. Recommendation: builder's exact pixel offsets can flex, this is the shape to follow.
- **No `esc()` needed for label text** — weight is always numeric (`parseFloat`'d already,
  formatted via `formatKg`) and date is always Date-derived, never a raw pass-through of
  API-provided free text, so this doesn't trigger the "escape all API-derived strings" invariant.

## 2. Changes

### index.html — new helper `trendWindowBounds` (~line 1002, immediately before `buildTrendPoints`)

```
trendWindowBounds(now = new Date()): { startISO: string, endISO: string }
```
- `endISO = localDateISO(now)`.
- `startISO`: clone `now`, `d.setMonth(d.getMonth() - 3)`, then `localDateISO(d)`.

### index.html — `buildTrendPoints(exerciseId, logs, now = new Date())` (index.html:1004-1014)

- Same per-day max-weight grouping into `byDay` as today (unchanged).
- Replace `.slice(-20)` with a filter: keep only `dk >= trendWindowBounds(now).startISO`
  (string comparison is safe — same-length `YYYY-MM-DD` ISO keys sort lexicographically same as
  chronologically).
- Return shape unchanged: ascending array of `{date, weight}`.

### index.html — `renderTrendSvg(points, now = new Date())` (index.html:1017-1030)

- Delete the `points.length === 1` special-cased return.
- Compute `{startISO, endISO} = trendWindowBounds(now)`; `startMs`/`endMs` from
  `new Date(startISO|endISO).getTime()`; `span = endMs - startMs` (always > 0 for a 3-month
  window, no guard needed).
- `xs = points.map(p => ((new Date(p.date).getTime() - startMs) / span) * 300)` — replaces the
  old `i/(n-1)*300` index spacing.
- Keep existing y normalization (min/max weight -> 0..100, flat-case fallback to `y=50`)
  unchanged.
- `labeled = trendLabelIndices(points)` (new helper, see below).
- For each labeled index, emit two `<text>` elements (value line + date line) per the placement
  rule in Decisions, using `formatKg(p.weight)` and the compact date formatter. Non-labeled
  points keep their existing plain `<circle>` only.

### index.html — new helper `trendLabelIndices(points)` (~line 1030, immediately after `renderTrendSvg` or inline above it — builder's call)

```
trendLabelIndices(points): number[]
```
- Empty/undefined input -> `[]`.
- Otherwise: `Set` containing `0`, `points.length-1`, the index of the first occurrence of
  `Math.min(...weights)`, and the index of the first occurrence of `Math.max(...weights)` —
  return as a sorted array (dedup via `Set` handles all-equal/short-array collisions naturally).

### index.html — CSS (~line 200-203, alongside existing `.trend-svg` rules)

- Add a `.trend-svg text{...}` rule (small font-size, `fill:var(--muted)` for the date line) and
  a modifier for the value line (e.g. `.trend-svg text.tv{fill:var(--fg); font-weight:600}` —
  exact class names/colors are the builder's call, following the existing CSS variable
  conventions already used by `.trend-svg circle`/`polyline`).

### index.html — call site `showExerciseDetail` (index.html:1043, 1055)

- No signature change needed — `buildTrendPoints(exerciseId, logs)` and `renderTrendSvg(points)`
  both keep working via their new `now` default; nothing to update here.

## 3. Edge cases

- **No logs in the 3-month window**: `buildTrendPoints` returns `[]`, `renderTrendSvg` keeps the
  existing `<div class="trend-empty">No history yet</div>` path — unchanged behavior even though
  older logs may exist outside the window (matches roadmap intent: window is fixed, not "widen
  until something is found").
- **Exactly one point in the window**: no longer special-cased; time-proportional x places it at
  its true offset in the window (e.g. a single log 2 weeks ago sits near the left, not centered).
  `trendLabelIndices` returns `[0]` (all four picks collapse to the same index) — one label only.
- **All points share the same weight (flat)**: y-normalization flat-case (`y=50` for all)
  unchanged; `trendLabelIndices` still resolves min/max to specific (first-occurrence) indices,
  which may coincide with the first/last index already selected — `Set` dedup means no double
  label at one point.
- **Calendar-month rollover quirk** (e.g. `Date.setMonth` from the 31st landing early in the
  target month when that month is shorter): accepted as-is per Decisions, not fixed — a rare,
  one-day-ish skew in the window boundary, not worth extra date-library logic for a trend chart.
- **Points very close together near a window edge**: label anchor clamping (`x<=20`/`x>=280`)
  keeps text from running off-canvas; `overflow:visible` on `.trend-svg` (existing CSS) means a
  slight bleed beyond the viewBox is tolerated, not a hard clip.
- **500-log app-wide fetch cap** (pre-existing, noted in Phase 3's spec too): still shared across
  all exercises, not per-exercise — an infrequently-logged exercise's older-than-500th log could
  in theory fall outside `allLogsCache` before the 3-month window even applies. Inherited
  limitation, not fixed by this phase.

## 4. Tests (self-test block, index.html ~1961, replacing the existing `buildTrendPoints` block)

- `trendWindowBounds(new Date("2026-09-15"))` -> `{startISO: "2026-06-15", endISO: "2026-09-15"}`.
- `buildTrendPoints`: fixture logs spanning both inside and before a fixed `now`'s 3-month window
  -> only in-window days appear, ascending order, per-day max-weight collapsing still holds
  (reuse/adapt the existing same-day-collapse assertions at index.html:1961-1964, now passing an
  explicit `now`).
- `buildTrendPoints`: no cap — feed >20 daily logs all inside the window (with a fixed `now`) ->
  all of them appear (replaces the old `length === 20` cap assertion with a "not truncated"
  assertion).
- `buildTrendPoints`: a log dated before the 3-month window with a fixed `now` -> excluded from
  the result.
- `trendLabelIndices`: empty array -> `[]`; single point -> `[0]`; ascending-then-descending
  weight fixture -> indices for first/last/min/max are all distinct and correct; a fixture where
  min or max coincides with first/last -> deduped, no repeated index in the result.

## 5. Explicitly out of scope

- No interactivity (tap/hover tooltips) — labels are always-on per Gate 2, not revealed on
  interaction.
- No charting dependency — stays hand-built inline SVG per the existing approach.
- No fix for the 500-log fetch cap.
- No change to `computeExerciseStats` or the stat cards above the graph in `showExerciseDetail`.
- No change to `dayKey`/`localDateISO`/`formatKg` themselves — reused as-is.
