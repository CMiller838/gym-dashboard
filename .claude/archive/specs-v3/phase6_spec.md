# Phase 6 (v3) — Stalled-workout auto-complete, routine/exercise reordering (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers the outline's two nice-to-haves, independent of Phases 1–5 (no shared code with the
timer/PR/summary/history work). No new dependency, no new external endpoint.

## 0. What investigation found (read this before touching code)

- `renderRoutines(routines)` (`791`) sorts routines client-side by `created` date descending
  (`~798`). No `order`/`sortOrder` field is referenced anywhere for the routine list itself, and
  this app has **no routine create/edit UI** (grepped `createRoutine`/`editRoutine`/`newRoutine`
  — none found; routines are read-only, built in wger itself). The only `order` field that
  exists anywhere in the API data is on **slots/slot-entries** within a routine's day structure
  (`day.slots[].order`, `slot.entries[].order`, read+sorted at `958-959`) — that governs the
  exercise plan within a routine template, a different concept from the order routines appear in
  this app's list, and not reachable from any UI this app has. `.swagger.json` in the repo is a
  dead 404 stub. Confirmed via Decision Gate: routine list reordering is **local-only**
  (localStorage), not persisted to wger.
- `startWorkout(routineId)` (`987`): client-side guard at `988` (`if(getActive())` returns to the
  in-memory active session). Server-side duplicate guard is wger's own unique constraint on
  (routine, day, date) — `launchDay()` (`1024-1060`) POSTs to `/workoutsession/?format=json`
  (`1031-1036`); a 500/"unique" error is caught (`1052-1057`) and surfaced as an alert. This guard
  is untouched by this phase — auto-completing a stale session (which sets `time_end`) is what
  lets a *new* session be started afterward without hitting that constraint, satisfying this
  phase's exit condition.
- `launchDay()` builds the local active-workout object `w` (`1038-1048`), including
  **`startedAtMs: Date.now()`** (`1044`) — a client-local timestamp already captured at session
  start, with no parsing of API date/time strings needed for a staleness check. `setActive(w)`
  (`1049`) persists it to `localStorage[ACTIVE_KEY]`.
- `finishWorkout()` (`1564-1588`): confirms with the user (`1568`, blocking `confirm()`), then
  PATCHes `/workoutsession/${w.sessionId}/` with `{time_end: nowTimeISO()}` (`1573`), builds the
  summary (`1579`), clears active state and the rest-timer interval (`1580-1581`), and either
  returns to `render()` (zero-set workout, `1585`) or shows the summary screen (`1586-1587`). The
  `confirm()` at `1568` makes this function unsuitable to call as-is from an unattended
  auto-complete path — see Section 2 for the extraction.
- Timer/interval landscape: `restTickInterval` (`336`, started `1168`, 1 Hz) runs
  `tickRestTimers()` (`1182+`) only while the active-workout screen is on screen, and is cleared
  on finish/discard (`1581`, `1608`). No existing interval tracks elapsed *session* time. Existing
  ms-duration constant convention: `EXINDEX_TTL_MS = 7 * 24 * 60 * 60 * 1000` (`322`) — no
  existing constant conflicts with a 3-hour threshold.
- `render()` (`632+`) reads `getActive()` once per call (`634`) and branches straight to
  `renderActiveWorkout()` if there's an active session and the user hasn't backed out
  (`635`) — this is the natural place to run a staleness check before that branch, since `render()`
  already runs on every app boot, tab switch, and manual refresh.
- No existing drag-and-drop code anywhere in the file (grepped `drag`, `Sortable`, etc. — none;
  the only `touchstart` listener, `1788`, is an unrelated passive no-op for scroll perf).
- Exercise order within an active workout is already local-only, driven by array order of
  `w.entries` and reordered today via up/down buttons — `moveExercise(idx, dir)` (`1236-1246`),
  wired from `.movebtn` buttons in the per-exercise card (`1132-1134`). This phase adds
  drag-and-drop as an additional way to reorder the same array — the up/down buttons stay (cheap
  accessibility/fallback, no reason to remove a working control).
- localStorage key convention: `SCREAMING_SNAKE_CASE` JS constant holding an underscore-separated
  string, e.g. `TOKEN_KEY = "wger_api_token"` (`319`), `ACTIVE_KEY = "active_workout"` (`320`).

## 1. Decision Gate — resolved

**Routine list reordering — persistence.** Gated because wger's `/routine/` model shows no
evidence of a writable order field (Section 0) and the roadmap's exit condition wording depends
on which path is taken. **User selected Path A: local-only order via localStorage** (a new
`routine_order` key). This is what the evidence supported (Path A was also the recommendation) —
routine order does not sync across devices/reinstalls, which is an accepted trade-off, not a bug.

No other gates raised:
- **Tier 1 (schema/data-shape change, new dependency/endpoint):** not triggered — no API schema
  changes, no new external endpoint, no new dependency (drag-and-drop implemented with native
  Pointer Events, no library — see Section 2).
- **Tier 2 (roadmap's stated approach unfollowable, or clearly better path)** beyond the gate
  above: the 3-hour threshold doesn't conflict with any existing timeout constant (checked
  Section 0), so no gate needed there.

## 2. Decisions (planner's own calls — Tier 3, no gate needed)

- **Drag mechanism:** native Pointer Events (`pointerdown`/`pointermove`/`pointerup`), not the
  HTML5 `dragstart`/`dragover` Drag and Drop API and not a library. HTML5 native DnD is unreliable
  on iOS Safari, which matters because this is a mobile-first PWA (per `CLAUDE.md`); Pointer
  Events work uniformly across touch and mouse in one implementation. One shared helper is used
  for both reorderable lists (routines, active-workout exercises) rather than writing the drag
  logic twice.
- **Stale-session finish path:** extract the post-`confirm()` body of `finishWorkout()`
  (currently `1569-1587`: wake-lock release, PATCH `time_end`, build summary, clear active state,
  clear interval, remove finish bar, route to summary or main) into a new shared function,
  `finalizeWorkout(w)`, called both by `finishWorkout()` (after its existing `confirm()` gate) and
  by the new auto-complete path (no confirm — that's the whole point of "auto"). This is a pure
  reuse of existing, already-correct logic, not new behavior.
- **Where the staleness check runs:** (a) inside `render()`, immediately after `getActive()`
  (`634`), before the existing branch to `renderActiveWorkout()` — covers app boot, tab
  switches, and manual refresh; (b) inside the existing `tickRestTimers()` 1 Hz loop (`1182+`),
  which already runs continuously while the active-workout screen is open — covers a session that
  goes stale while the user is looking straight at it. No new `setInterval` is added (reuses the
  existing 1 Hz tick — ladder rung 2). No service worker or background task is added (this repo's
  architecture explicitly has none) — a session can only be auto-completed while this app is open
  in a tab on the device that started it; this is a documented limitation, not a bug (Section 4).
- **Routine order fallback rule:** any routine not yet present in the persisted `routine_order`
  list is sorted after all ordered routines, using the existing `created`-date-descending order
  among themselves (i.e. new/unordered routines land at the bottom in today's default order,
  not scattered).
- **Exercise-list drag scope:** applies only to the in-progress `w.entries` array during an active
  workout (already fully local, never sent to wger) — no interaction with the routine's
  `slot.entries[].order` field, which is a separate concept read once at workout start and not
  written back.

## 3. Changes

### New constants (near `319-322`)
- `SESSION_STALL_MS = 3 * 60 * 60 * 1000` — matches the existing `EXINDEX_TTL_MS` ms-constant
  style.
- `ROUTINE_ORDER_KEY = "routine_order"` — matches the existing `*_KEY` string-constant style.

### `isSessionStale(w)` — new pure function
Signature: `isSessionStale(w: {startedAtMs: number} | null): boolean`. Returns
`!!w && (Date.now() - w.startedAtMs) > SESSION_STALL_MS`. No DOM/API access — pure, testable.

### `finalizeWorkout(w)` — new function, extracted from `finishWorkout()`
Signature: `async function finalizeWorkout(w): void`. Body = current `finishWorkout()` lines
`1569-1587` verbatim (wake-lock release, PATCH `time_end` with existing try/catch and alert-on-
failure, `buildSummary(w)`, `clearActive()`, clear `restTickInterval`, remove `#finishBar`, set
`activeTab = "history"`, then either `render()` on a zero-set workout or populate
`summary`/`summaryCard` and call `renderSummary()`). No behavior change versus today's
`finishWorkout()` — pure extraction.

### `finishWorkout()` (`1564-1588`) — reduced to confirm + delegate
Keeps `getActive()`, the zero-active early return, `totalSets` computation, and the `confirm()`
prompt (`1564-1568` unchanged); on confirm, calls `await finalizeWorkout(w)` instead of inlining
the rest.

### `autoCompleteStaleSession(w)` — new function
Signature: `async function autoCompleteStaleSession(w): void`. No `confirm()`. Calls
`await finalizeWorkout(w)` directly. Called only from the two hook points below, never from user
interaction.

### `render()` (`632+`) — stale check before the active-workout branch
At `634`, after `const active = getActive();`, insert: if `active` and `isSessionStale(active)`,
`await autoCompleteStaleSession(active)` then re-run this render pass (equivalent to calling
`render()` again now that `getActive()` will return `null`) instead of falling into the existing
`635` branch. Non-stale active sessions fall through to the existing, unchanged `635` branch.

### `tickRestTimers()` (`1182+`) — stale check on the existing 1 Hz tick
At the top, after the existing `getActive()`/`if(!w) return;` guard, add: if
`isSessionStale(w)`, fire-and-forget `autoCompleteStaleSession(w)` then call `render()` and
return — skip the rest of the existing rest-timer tick logic for this tick.

### `attachDragReorder(containerEl, itemSelector, onReorder)` — new shared helper
Signature:
`function attachDragReorder(containerEl: HTMLElement, itemSelector: string, onReorder: (newIndexOrder: number[]) => void): void`.
Wires Pointer Events (`pointerdown`/`pointermove`/`pointerup`/`pointercancel`) on
`containerEl` to let items matching `itemSelector` be picked up and reordered via drag; on drop,
calls `onReorder` once with the new 0-based index order (e.g. `[2,0,1]` meaning old index 2 is
now first). Does not itself know what a "routine" or "exercise" is — pure list-reorder mechanics,
usable by any container/list. Idempotent to call again on re-render (each `renderX()` call
re-attaches to the freshly-rendered DOM, matching how this file already re-renders wholesale on
every state change — no persistent-DOM diffing exists here to preserve listeners across renders).

### `loadRoutineOrder()` / `saveRoutineOrder(ids)` — new functions
- `loadRoutineOrder(): number[]` — reads `localStorage[ROUTINE_ORDER_KEY]`, `JSON.parse`s it,
  returns `[]` on missing/corrupt data (same defensive pattern as the existing
  `exercise_name_cache` parse at `325-331`).
- `saveRoutineOrder(ids: number[]): void` — `JSON.stringify`s and writes
  `localStorage[ROUTINE_ORDER_KEY]`.

### `renderRoutines(routines)` (`791`) — sort by persisted order + drag wiring
Replace the `created`-date-only sort (`~798`) with: build an `id -> index` map from
`loadRoutineOrder()`; sort routines by that index when present, falling back to the existing
`created`-descending comparator for routines absent from the map (Section 2's fallback rule —
unordered routines keep today's relative order, appended after ordered ones). After rendering the
list, call `attachDragReorder(listEl, ".routine-card", onReorder)` where `onReorder` maps the new
index order back to routine IDs (using the currently-rendered, already-sorted `routines` array)
and calls `saveRoutineOrder(newIds)`, then re-renders the routine list in place (no full `render()`
network refetch needed — this is a pure client-side reorder of already-fetched data).

### `renderActiveWorkout()` (`1067+`) exercise cards (`~1089-1142`) — drag wiring
After rendering the per-exercise cards (which already include the `moveExercise` up/down buttons,
unchanged), call `attachDragReorder(listEl, ".wex-card", onReorder)` where `onReorder` reindexes
`w.entries` to the new order, calls `setActive(w)`, and calls `renderActiveWorkout()` — the same
persistence/re-render pattern `moveExercise()` (`1236-1246`) already uses, just triggered by drag
instead of a button tap.

### UI prototype + restyle (drag affordance/visuals)
Not a direct-code task for the visual feel. Produce a UI prototype (via `ui-prototyper`) of the
drag interaction for both lists using fake/dummy data — a drag handle or long-press-to-lift
affordance, the lifted item's visual state (elevation/shadow, follows the pointer), placeholder/
gap indicator for the drop position, and the settle animation on drop — covering both the routine
list and the active-workout exercise list (same visual language for both, since they share
`attachDragReorder`). Once a direction is chosen, apply it via `restyle-from-prototype`, which
adapts the relevant CSS and wires the chosen visual states into `attachDragReorder`'s pointer
event handlers — without changing the reorder/persistence logic in Section 3 above.

## 4. Edge cases the implementation must hold

- App reopened after 3+ hours away → `render()`'s stale check fires before any UI paints the
  stale workout, auto-completes it silently (no `confirm()`), and the user lands on the normal
  post-finish flow (main view if zero sets logged, summary screen otherwise) — exactly like a
  manual finish, just without the prompt.
- Session goes stale while the workout screen is left open and on-screen → caught by the
  `tickRestTimers()` hook within 1 second of crossing the threshold, same auto-complete path.
- Auto-complete's PATCH fails (offline, server error) → same fallback as today's `finishWorkout()`
  catch block: an alert reports the sets are safe but the finish time wasn't recorded, and local
  state still clears (Section 2 — `finalizeWorkout` is a verbatim extraction, no new error
  handling invented).
- A session started on another client (e.g. the wger mobile app, or this app on a different
  device) never populates this device's `localStorage[ACTIVE_KEY]`, so it can never be
  auto-completed by this device's stale check — this phase's exit condition is scoped to sessions
  started through this app on the device running it, matching the architecture's no-backend,
  no-service-worker design. Documented, not fixed.
- Routine list: a routine present in `routine_order` but since deleted from wger simply has no
  matching entry in the freshly-fetched `routines` array — it's never rendered and never affects
  sort order; no active pruning of stale IDs from localStorage is needed.
- Routine list: a brand-new routine (not yet dragged, absent from `routine_order`) appears after
  all manually-ordered routines, in today's existing `created`-descending order among the
  unordered set (Section 2).
- Exercise-list drag during an active rest timer countdown → dragging is a pointer-only
  interaction on the card, independent of the running `restTickInterval`; reordering
  `w.entries` does not reset or interfere with any in-progress rest timer state on the dragged or
  other entries.
- Dragging a fully-completed exercise card (all sets logged) → still draggable; drag reorders
  position only, `isDone`/per-set `logged` state travels with the entry object, unaffected.
- Single-item lists (one routine, one exercise) → `attachDragReorder` attaches without error;
  `onReorder` simply never fires since there's nothing to reorder against.

## 5. Self-test additions (existing `runSelfTest`)

`isSessionStale` is a pure function — testable without DOM:
1. `isSessionStale({startedAtMs: Date.now()})` → `false` (just started).
2. `isSessionStale({startedAtMs: Date.now() - 4*60*60*1000})` → `true` (4h old > 3h threshold).
3. `isSessionStale({startedAtMs: Date.now() - 2*60*60*1000})` → `false` (2h old < 3h threshold).
4. `isSessionStale(null)` → `false` (no active session is never "stale").

`loadRoutineOrder`/`saveRoutineOrder` — testable without DOM (localStorage is available in the
existing test environment, matching how other localStorage-backed helpers are already tested):
5. `saveRoutineOrder([3,1,2])` then `loadRoutineOrder()` → `[3,1,2]`.
6. `loadRoutineOrder()` on a missing/corrupt key → `[]`, never throws.

## 6. Explicitly out of scope

- Any UI element or copy distinguishing an auto-completed session from a manually-finished one
  (e.g. a "auto-completed after 3 hours" banner) — the roadmap's exit condition only requires the
  session not pollute history/stats, which `finalizeWorkout` already satisfies by setting
  `time_end`; a distinguishing banner is a future nice-to-have, not required here.
- Persisting routine order to wger's API — resolved by the Decision Gate as local-only
  (Section 1); revisiting this requires confirming wger actually gains a writable order field on
  `/routine/`, not assumed here.
- Any change to `slot.entries[].order`/`day.slots[].order` or the routine-structure fetch at
  `991` — that data is read-only input to building a workout, untouched by this phase.
- A background/service-worker-driven auto-complete that fires while the app isn't open — this
  repo has no service worker by design (`CLAUDE.md`); auto-complete only runs while the app is
  open, per Section 4.
- Any reordering UI for anything other than the two lists named in the roadmap (routines,
  active-workout exercises) — e.g. no reordering of workout history, no reordering of sets within
  an exercise.
