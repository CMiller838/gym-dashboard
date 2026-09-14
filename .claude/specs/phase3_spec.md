# Phase 3 — Persistent PR medals

## 0. What investigation found (from dispatch, no re-scan needed)

- `classifySetPR(prev, weight, reps)` (index.html:943-946) compares one set against a
  `prev = {w, v}` best-ever record and returns `{weightPR, volumePR}` (strict `>`, equal is not a
  PR). It stays as-is — Phase 3 builds a new, separate helper for "which set holds the medal
  right now," it does not replace this toast-time check.
- Call site (index.html:1578-1599, inside the set-logging handler after `apiPost` to
  `/workoutlog/`) reads `prev = w.best[entry.exerciseId]`, calls `classifySetPR`, then updates
  `w.best[exerciseId]` in place and pushes into `w.prs` for a toast. None of this renders a
  persistent per-row badge today — `w.best`/`w.prs` are a running tracker for the toast only.
- `w.best` is initialized once per active workout via `computeBestByExercise(logs)`
  (index.html:1142, migrated at 1169) using whatever `allLogsCache` held at workout-start. It is
  *not* what Phase 3's medal recompute should read from directly, since it only tracks a running
  max value, not which specific logged set holds it.
- `renderActiveWorkout()` (index.html:1163+) takes no params, reads `getActive()` internally.
  `w.entries` is `[{slotEntryId, exerciseId, name, restSeconds, restEndMs, lastTime, sets}]`;
  each `entry.sets[si]` is `{weight, reps, logged, logId, ...}`. Outer loop `w.entries.forEach`
  (1185), inner loop `entry.sets.forEach((s, si) => ...)` (1190) builds one `<tr>` per set,
  branching on `s.logged` (logged row: 1193-1202, unlogged row: 1203+). Medal markup belongs in
  the logged-row branch only (unlogged sets have no `logId`, can't be a historical PR holder).
- `renderHistory(sessions, logsBySession, routineById)` (index.html:770-836): `logsBySession` is
  `{sessionId: [log, ...]}`, each log shaped `{id, session, exercise, weight, repetitions, date}`
  (raw wger API shape — note `repetitions`, not `reps`, and `exercise`, not `exerciseId`). Per
  session, sets are re-grouped by exercise into `exGroups[exercise]` (805-809), then for each
  exercise a `setStr` is built by joining all of that session's sets for that exercise into one
  comma-separated plain-text string (~816) — there are no individual per-set DOM elements today,
  so marking one set means splitting that join into per-set spans.
- `allLogsCache` (index.html:338) is the one in-memory store of "all" logs: fetched via
  `apiAll('/workoutlog/?format=json&ordering=-date&limit=500')`, capped at the 500 most recent
  logs app-wide (not per exercise). Two refresh points:
  - `render()` (index.html:726-737): unconditionally refetches fresh every time the main tabs
    (History/PRs/etc.) are shown, then overwrites `allLogsCache`. **History is always fresh.**
  - `launchDay()` (index.html:1120-1124): only fetches if `allLogsCache` is falsy, then freezes
    it for the rest of that active workout — it is *not* refreshed again while a workout is in
    progress, even though `apiDelete('/workoutlog/:id/')` calls happen mid-workout at
    index.html:1366, 1399, 1617, 1750 with no corresponding cache invalidation.
  - Net effect: `allLogsCache` alone is stale for anything logged/deleted *during the current
    active workout* — this is the one gap Phase 3's design has to route around (see Decision 3
    below); it is not a new bug, `w.best`/`lastTimeForExercise` already inherit the same
    staleness today and are accepted as-is.
- Self-test block (index.html:1852-1900, `classifySetPR` covered at 1864-1873): bare `{ }` blocks
  with inline fixtures and `assert(fn(...) === expected, "fnName: case")` lines, no test runner
  wrapper. New logic follows the same shape.
- `docs/roadmap.md:26-30` (Phase 3 text) — confirmed verbatim; Phase 4 (line 32) explicitly
  depends on Phase 3's PR data for a routine-preview row, so the medal-holder lookup needs to be
  a reusable function, not logic buried inline in one render path.

## 1. Decisions (Tier 3 — decided here, not gated)

- **New shared helper `exercisePRHolders`, placed next to `classifySetPR` (~index.html:947)**,
  rather than duplicating max-scanning logic inside both `renderActiveWorkout` and
  `renderHistory`. Both render paths already need "which logId is the current weight/volume
  best for this exercise" — one pure function, two call sites.
- **Tie-break rule: lowest `id` wins.** wger log `id`s are backend auto-increment PKs, so lowest
  id among equal-value entries is the earliest one created. If two sets tie on weight (or
  volume), the earlier one keeps the medal rather than a later duplicate "stealing" it. wger's
  `date` field is day-granularity, not a timestamp, so `date` can't be used as the tie-break —
  `id` is the only reliably-ordered field available.
- **Active-workout medal pool = `allLogsCache` (frozen at workout start) merged with this
  workout's own already-logged sets from `entry.sets`, recomputed every `renderActiveWorkout()`
  call.** This routes around the `allLogsCache` staleness noted above without adding a cache
  invalidation mechanism or an extra network fetch: the frozen cache is a valid baseline for
  everything before this workout started, and `entry.sets` (already in memory, updated
  synchronously on log/unlog/delete) covers everything that happened since. Recomputing the
  merge on every render (rather than caching the merged result) is what makes edits/deletes
  during the workout move or remove the medal live.
- **`renderHistory` gains a 4th parameter, `logs`** (the same flat array `render()` already
  builds at index.html:726-728, right before deriving `logsBySession` from it) so history can
  scope the PR search to the exercise's full fetched history, not just the current session's
  subset in `logsBySession[sessionId]`. This is a function-signature change, not a stored-data
  shape change — no new field is added to any record.
- **Medal presentation:** two independent small inline badges, `🏆` for the current weight-PR
  holder and `🔥` for the current volume-PR holder — both can appear on the same set if one set
  holds both. Plain glyphs, no new dependency, no escaping needed (static text, not API data).
- **Known, unchanged limitation:** the 500-log fetch cap is shared app-wide across all exercises,
  not per-exercise, so an infrequently-logged exercise's true all-time PR could in theory fall
  outside the fetched window. `computeBestByExercise`/`w.best` already carry this same limitation
  today — Phase 3 does not fix it, just inherits it. Noted under Edge cases, not gated.

## 2. Changes

### index.html — new helper (~line 947, immediately after `classifySetPR`)

```
exercisePRHolders(records): { weightLogId: number|null, volumeLogId: number|null }
```
- `records`: array of `{logId, weight, reps}` for **one exercise only** — callers normalize
  their own record shape before calling (wger logs use `id`/`repetitions`, active-workout sets
  use `logId`/`reps` already).
- Returns `{weightLogId: null, volumeLogId: null}` for an empty array.
- Otherwise scans once for the record with max `weight` (ties broken by lowest `logId`) and once
  for the record with max `weight * reps` (same tie-break), independently — the two can point to
  different `logId`s or the same one.

### index.html — `renderActiveWorkout()` (index.html:1163+)

- Before the per-set inner loop, per `entry` (once per exercise, not per set):
  - Build `historical = (allLogsCache || []).filter(l => l.exercise === entry.exerciseId).map(l => ({logId: l.id, weight: l.weight, reps: l.repetitions}))`.
  - Build `thisSession = entry.sets.filter(s => s.logged && s.logId).map(s => ({logId: s.logId, weight: s.weight, reps: s.reps}))`.
  - `const holders = exercisePRHolders(historical.concat(thisSession));`
- In the logged-set row branch (~1193-1202), for each `s` with `s.logged`:
  - If `s.logId === holders.weightLogId`, render a `🏆` badge.
  - If `s.logId === holders.volumeLogId`, render a `🔥` badge.
  - Insert both inside the existing `setnum` cell (small inline span after the set number) —
    no new `<td>`, keeps the row layout unchanged.

### index.html — `render()` call site (index.html:726-752)

- Update the call to `renderHistory` (index.html:752) to pass the 4th argument:
  `renderHistory(sessions, logsBySession, routineById, logs)`.

### index.html — `renderHistory(sessions, logsBySession, routineById, logs)` (index.html:770-836)

- New 4th parameter `logs` — the full flat array (already fetched fresh every call per
  investigation above).
- Per exercise group inside the per-session loop (~805-821), before building `setStr`:
  - `const exLogs = logs.filter(l => l.exercise === id).map(l => ({logId: l.id, weight: l.weight, reps: l.repetitions}));`
  - `const holders = exercisePRHolders(exLogs);`
- Change the `setStr` construction (~816) from a single joined plain-text string to a per-set
  mapped-then-joined string, e.g. each set renders as its own inline span:
  `sets.map(l => \`<span class="prset">${weight}×${reps}${l.id===holders.weightLogId?' 🏆':''}${l.id===holders.volumeLogId?' 🔥':''}</span>\`).join(", ")`
  — exact class names/markup are the builder's call as long as each set is its own span (needed
  so the badge attaches to one specific set, not the whole exercise row) and existing styling of
  the joined text is preserved as closely as possible.

## 3. Edge cases

- **Set deleted mid-workout**: existing delete handlers (index.html:1366, 1617) already call
  `renderActiveWorkout()` after the `apiDelete` succeeds and `entry.sets.splice(...)`, so the
  merge pool (`historical + thisSession`) is naturally recomputed next render with that set
  gone — medal moves to the next-highest remaining set or disappears if none remain.
- **Set deleted from History (if/when history supports deletion)**: not currently in scope —
  `renderHistory` is read-only today per investigation; no delete path to guard there.
- **New PR logged this session**: covered by including `thisSession` sets in the active-workout
  pool — the just-logged set is visible to `exercisePRHolders` on the very next render even
  though `allLogsCache` itself is frozen for the rest of the workout.
- **Tie between two sets at the same weight/volume**: lower `logId` (earlier) keeps the medal —
  documented in Decisions.
- **First-ever set for an exercise**: `exercisePRHolders` on a single-record array returns that
  record's `logId` for both `weightLogId` and `volumeLogId` — trivially wins both.
- **Exercise with only unlogged sets in the active workout**: `thisSession` is empty, `holders`
  falls back to whatever `historical` alone produces (or `{null, null}` if the exercise has no
  history at all) — no medal shown on any still-unlogged row, matching the roadmap's "logged
  sets only" intent.
- **500-log fetch cap**: shared app-wide, not per-exercise — pre-existing limitation, unchanged
  by this phase (see Decisions).

## 4. Tests (self-test block, index.html ~1900+, same `assert()` pattern)

Add one new block covering `exercisePRHolders`:
- Empty array → `{weightLogId: null, volumeLogId: null}`.
- Single record → both fields equal that record's `logId`.
- Distinct weight-PR and volume-PR holders (e.g. one heavy-low-rep set, one lighter-high-rep set
  with greater weight*reps) → `weightLogId` and `volumeLogId` differ and each points to the
  correct record.
- Exact tie on weight between two records with different `logId`s → lower `logId` wins.
- Records where weight is constant but reps vary → `volumeLogId` picks the highest-volume record
  independent of `weightLogId`.

## 5. Explicitly out of scope

- No new stored field/flag on any set or log record — medal state is never persisted, only
  computed at render time (per roadmap).
- No change to `classifySetPR` or the existing toast/`w.prs` logging-time flow.
- No cache-invalidation mechanism for `allLogsCache` — routed around instead, per Decision 3.
- No fix for the 500-log fetch cap.
- No history-side delete/edit UI — history stays read-only; medal recompute there just rides on
  the fresh fetch `render()` already does.
