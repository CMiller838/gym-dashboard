# Phase 3 (v3) — In-workout exercise history/trend view (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-have 5 from `docs/outline-v3.md`. No new dependencies, no new endpoints — this
phase reads `allLogsCache`, already fetched for existing PR logic, and adds a new render path
on top of it.

## 0. What investigation found (read this before touching code)

- The exercise name is rendered at `.wex-name` (`~962`) inside `renderActiveWorkout()`
  (`892-991`): `<div class="wex-name">${esc(entry.name)}</div>`. `entry` at that point carries
  `name`, `sets[]`, `lastTime[]`, `restSeconds`, `restEndMs`, `exerciseId`, `slotEntryId` — the
  `exerciseId` needed to look up history is already on hand, no plumbing required. No row-level
  click handler exists yet; only child buttons (`logbtn` `941`, `removebtn` `965`, move buttons
  `958-959`) have their own handlers.
- `allLogsCache` (declared `239`, populated `557`/`853` via `apiAll`) is an array of workout log
  entries, each with `exercise` (id), `weight`, `repetitions`/`reps`, `date` (ISO string), `id`.
  One entry per logged set.
- `computeBestByExercise(logs)` (`734`) returns `{ [exerciseId]: { w: maxWeight, v: maxVolume } }`
  — already computes lifetime best weight and best volume across all cached logs. Reusable
  as-is by filtering its result to one exercise id rather than duplicating the max logic.
- `lastTimeForExercise(exerciseId, logs)` (`767`) returns the most recent day's `{weight, reps}`
  pairs — not reused directly here (this phase needs the *series* over time, not just the last
  day) but confirms the log-filtering/date-grouping shape already used elsewhere in the file.
- Phase 1 (v3)'s `preBest`/`recomputeBestForExercise` do **not** exist yet (grepped, zero hits)
  — this phase must not assume them; it computes stats directly from `allLogsCache` via
  `computeBestByExercise`, same as the current PR code does.
- Existing overlay pattern (`openAddExercise` `1090`, `showDayPicker` `830`): build a
  `div.overlay` containing a `div.overlay-sheet`, set its `innerHTML`, append to
  `document.body`, wire a cancel/close click handler, remove the node on dismiss. This phase's
  detail view reuses that exact pattern rather than inventing a new modal mechanism.
- No `<canvas>`/`<svg>`/chart code anywhere in `index.html` today (grepped, zero hits) — the
  trend graph is entirely new. Decision Gate 1 (below) resolved this: **inline SVG**, hand-built
  polyline + circles, `viewBox`-scaled — no dependency added.
- `esc()` (`399`) escapes `&`, `<`, `>`, `"` — every piece of `entry.name` (API-derived) written
  into the new overlay's `innerHTML` must go through it, per the existing stored-XSS invariant.
  Numeric values (weights, dates formatted as plain digits/slashes) do not need escaping, but
  route them through fixed numeric formatting (`toFixed`/`Number`), never raw string
  concatenation of anything that could contain user/API text.

## 1. Decision Gate resolution

**Decision Gate 1 (graph rendering): Path A — inline SVG (hand-built polyline + circles,
`viewBox`-scaled)**, confirmed by the user. Rejected canvas (needs manual resize/retina
handling, not inspectable as markup) and CSS-bar sparkline (loses actual line-trend shape,
which is the point of "trend view").

## 2. Decisions (planner's own calls — Tier 3, no gate needed)

- **Lifetime stats shown:** best weight (`w`), best volume (`v`) — both from
  `computeBestByExercise`, so this phase never duplicates that max logic — plus **total sets
  logged** (count of this exercise's entries in `allLogsCache`) and **last performed** (most
  recent `date` among those entries, formatted `YYYY-MM-DD` or locale date string, whichever the
  existing date-formatting helper elsewhere in the file already uses — grep for the formatter
  used near `lastTimeForExercise`/PR toast code and reuse it rather than writing a new one).
- **Trend series:** one point per calendar day this exercise was logged, value = that day's max
  weight (same "day" grouping already implied by `lastTimeForExercise`'s "most recent day"
  concept — if no existing `dayKey`-style helper is found by grep, bucket by the date portion of
  the ISO `date` string, e.g. `date.slice(0,10)`, which is equivalent and needs no new helper).
  Sort ascending by date. Cap at the most recent **20** points so the graph stays legible and
  the SVG stays small — older history is still reflected in the lifetime stats above, just not
  plotted point-by-point.
- **New functions, not reuse:** `computeExerciseStats` and `buildTrendPoints` are new (no
  existing function returns this shape); `renderTrendSvg` is new (no SVG code exists to reuse).
  `showExerciseDetail` reuses the existing overlay open/close pattern rather than a new modal
  mechanism.
- **Detail view layout:** overlay sheet with (top to bottom) exercise name (`esc`'d) as a
  heading, a 4-stat row (best weight / best volume / total sets / last performed), the SVG
  graph, a close button. No editing/deleting from this view — it's read-only history, per the
  roadmap's "detail view with lifetime stats and a trend graph," nothing about editing.

## 3. Changes

### `computeExerciseStats(exerciseId, logs)` — new function
Returns `{ bestWeight: number|null, bestVolume: number|null, totalSets: number, lastPerformed: string|null }`.
- `bestWeight`/`bestVolume`: `computeBestByExercise(logs)[exerciseId]?.w` / `?.v`, or `null` if
  the exercise has no entries (don't call `computeBestByExercise` twice if the caller already
  has a cached result available — accept it as a second optional pre-computed param if that's
  cheaper at the call site, otherwise compute inline).
- `totalSets`: `logs.filter(l => l.exercise === exerciseId).length`.
- `lastPerformed`: max `date` string among that filtered set (ISO strings sort lexically, so
  `Math.max`-style reduce on the raw strings is sufficient — no `Date` parsing needed), or
  `null` if empty.

### `buildTrendPoints(exerciseId, logs)` — new function
Returns `Array<{date: string, weight: number}>`, ascending by date, at most 20 entries (most
recent 20 calendar days with a logged set for this exercise; older points dropped, not
averaged).
- Filter `logs` to `exercise === exerciseId`.
- Group by day-key (existing helper if grep finds one, else `date.slice(0,10)`); within each
  day take the max `weight`.
- Sort ascending by day-key, then slice to the last 20.

### `renderTrendSvg(points)` — new function
Returns an SVG markup string (no external escaping needed — inputs are numbers/formatted
numbers, never raw API strings).
- If `points.length === 0`: return a placeholder string, e.g. a `<div class="trend-empty">`
  message ("No history yet") — not an empty SVG.
- If `points.length === 1`: render a single `<circle>` at mid-height, no `<polyline>` (a
  polyline needs 2+ points to show a line).
- Otherwise: compute `minW`/`maxW` across `points`; if `minW === maxW` (all sessions same
  weight), render a flat horizontal line at mid-height rather than dividing by zero. Map each
  point to `x` = evenly spaced across a fixed `viewBox` width (e.g. `0..300`), `y` = inverted
  linear scale of weight into a fixed height (e.g. `0..100`, higher weight = smaller `y`).
  Build one `<polyline points="x1,y1 x2,y2 ...">` plus one `<circle cx cy r>` per point. Wrap in
  `<svg viewBox="0 0 300 100" preserveAspectRatio="none" class="trend-svg">...</svg>` so CSS can
  size it responsively via `width:100%`.

### `showExerciseDetail(exerciseId, name)` — new function
Follows the `openAddExercise`/`showDayPicker` overlay pattern:
1. `const stats = computeExerciseStats(exerciseId, allLogsCache);`
2. `const points = buildTrendPoints(exerciseId, allLogsCache);`
3. Build `overlay` / `overlay-sheet` innerHTML: heading `esc(name)`, 4-stat row from `stats`
   (formatting `null` stats as `"—"`, not `"null"`), `renderTrendSvg(points)`, close button.
4. Append to `document.body`; wire close button (and overlay-background click, matching the
   existing pattern's dismiss behavior) to remove the node.

### Hook into `renderActiveWorkout()` (`~962`)
Change the static `.wex-name` div into a clickable element that calls
`showExerciseDetail(entry.exerciseId, entry.name)`, e.g. wrap the existing `esc(entry.name)`
markup with an `onclick` attribute referencing a global-scope-reachable call (matching how
other inline handlers in this render function are wired, e.g. `logbtn`/`removebtn` — grep their
exact `onclick="..."` construction at `941`/`965` and mirror it) rather than introducing a new
event-delegation mechanism for one element. Add a `cursor: pointer` affordance (existing
`.wex-name` CSS rule, or a new modifier class) so it reads as tappable.

## 4. Edge cases the implementation must hold

- Exercise with zero logged history (brand new, never logged before this workout) →
  `computeExerciseStats` returns all-`null`/`0` stats, `buildTrendPoints` returns `[]`,
  `renderTrendSvg` shows the "No history yet" placeholder instead of an empty graph.
- Exactly one logged day for the exercise → single `<circle>`, no polyline, no divide-by-zero.
- All logged sessions have identical max weight → flat line, no `NaN` from a `0/0` scale
  division.
- More than 20 distinct logged days → only the most recent 20 are plotted; lifetime stats
  (best weight/volume/total sets) still reflect the full history, not just the plotted window.
- `entry.name` containing HTML-significant characters (e.g. an exercise named `<script>` from a
  malicious/edited wger exercise database entry) → must render literally, not execute, via
  `esc()` in the overlay heading — same invariant as the existing `.wex-name` render.
- Tapping the exercise name mid-set-entry (inputs focused) → opening the overlay must not lose
  in-progress set data; since this only reads `allLogsCache`/`entry` and doesn't touch
  `entry.sets`, no state mutation risk exists here, but manual verification should confirm
  no dropped keystrokes/values from an in-focus input when the overlay opens.
- Missing `entry.exerciseId` (defensive — shouldn't happen given current render code, but guard
  anyway) → `showExerciseDetail` should no-op or show the empty state rather than throwing.

## 5. Self-test additions (existing `runSelfTest`, `~1437`)

Both new functions are pure data transforms over a `logs` array — testable without any DOM/SVG
rendering:
1. Fixture: a small hand-built `logs` array covering 2+ exercises, 3+ distinct days for one of
   them, and one exercise with a single log entry. Assert `computeExerciseStats` returns the
   expected `bestWeight`/`bestVolume`/`totalSets`/`lastPerformed` for each fixture exercise,
   including the `null`/`0` case for an exercise id not present in the fixture at all.
2. Same fixture: assert `buildTrendPoints` returns ascending-by-date points, one per day
   (max weight within a day collapsed correctly when two logs share a day), and that a fixture
   with 25+ distinct days is capped to 20.

## 6. Explicitly out of scope

- Editing or deleting past logs from the detail view — read-only per the roadmap's exit
  condition ("detail view ... showing lifetime stats and a graph").
- Volume-over-time as a second graph line/toggle — only the weight trend is plotted; volume
  remains a lifetime stat, not a series. Add later if requested.
- Any change to `computeBestByExercise` itself, or to Phase 1 (v3)'s not-yet-built `preBest` —
  this phase reads current cached logs directly, unaffected by whichever phase lands first.
