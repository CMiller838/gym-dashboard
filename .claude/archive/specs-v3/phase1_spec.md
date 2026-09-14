# Phase 1 (v3) — Data integrity: last-time baseline and PR tracking (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-haves 2 and 3 from `docs/outline-v3.md`. No new dependencies, no new files
beyond this spec and `tasks.md`.

## 0. What investigation found (read this before touching code)

Must-haves 2 and 3, **as originally worded**, are already correct in the current code —
confirmed by direct line-level inspection, not assumed:

- **Must-have 2** (`entry.lastTime` must not update mid-session): `entry.lastTime` is
  assigned exactly once, in `buildEntriesFromDay` (~`783`), from `lastTimeForExercise`
  called over the pre-session log snapshot fetched by `launchDay`. It is read-only
  afterward (`renderActiveWorkout` ~`910`, ~`957`) and never reassigned during the active
  workout. There is no bug here as originally described.
- **Must-have 3** (PR = heaviest weight in *any* completed set): `computeBestByExercise`
  (~`724-735`) already tracks heaviest weight and heaviest single-set volume across every
  logged set in one pass; `classifySetPR` (~`739-742`) and `logSet`'s PR block (~`1251`)
  fire on either track independently. No dedicated max-test gate exists anywhere.

**The real, still-live bug** (surfaced during planning, not in the original roadmap
wording): deleting or unmarking a logged set does **not** recompute PR state. `w.best`
is seeded once from historical logs at `launchDay` (`861`) and only ever grows via
`Math.max` inside `logSet` (`1252-1255`) — it never shrinks. `w.prs` (`recordPR`,
`1172-1181`) is a live current-value record per exercise (read by the summary,
`1303`/`1335-1347`), not an append-only log, so a stale PR from a deleted/corrected set
sticks around and is displayed as if still true. The three call sites that delete or
unmark a set — `removeSetRow` (`1025-1046`, DELETE at `1037`), `removeExercise`
(`1060-1074`, delete loop `1069-1071`), `unlogSet` (`1280-1296`, DELETE at `1288`) — do
not touch `w.best` or `w.prs` at all today. There is no in-app "edit weight/reps" path
(logged-set inputs are `disabled`, `916-917`); correcting a typo goes through
`unlogSet` + re-log, so fixing the delete/unlog path covers the edit case too.

This phase therefore has two parts: (1) lock in the already-correct behavior with
regression self-tests so it can't silently regress, and (2) fix the real PR-staleness
bug on delete/unlog.

Decision gates answered by the user:
- **Gate 1** (must-have 2, no gap found): Path A — no code change, add a regression
  self-test only.
- **Gate 2** (must-have 3, no gap found): Path A — no code change, add a regression
  self-test only.
- **Gate 3** (recompute strategy for the real bug): Path A — eager recompute on every
  delete/unlog, backed by a new frozen `w.preBest` baseline captured once at
  `launchDay`, kept live throughout the workout (not deferred to summary time).

## 1. New state: `w.preBest`

Added at `launchDay` (~`861`), alongside the existing `w.best` initialization:

```
w.preBest = computeBestByExercise(logs)   // frozen historical baseline, same call as
w.best    = computeBestByExercise(logs)   // the existing w.best seed — call it twice,
                                          // do not share one object between the two
                                          // fields (w.best is mutated afterward, w.preBest
                                          // must never be)
```

`w.preBest[exerciseId]` is never written again after this line for the lifetime of the
workout. It is the "what had to be beaten" reference for every PR reconciliation.

**Migration for in-flight workouts** (resumed from `localStorage`, predate this fix):
at the existing migration check (~`888`, `if(!w.best) w.best = computeBestByExercise(...)`),
add a sibling `if(!w.preBest) w.preBest = computeBestByExercise(logs)`. This is a
best-effort re-derivation from whatever historical log snapshot is available at resume
time (`launchDay` already refetches `logs` on resume when `allLogsCache` is empty, `842`)
— a `ponytail:` comment should note that a workout resumed *mid-session* after this
migration line runs will treat "everything logged so far this session" as if it were
part of the frozen baseline, since the true pre-session baseline can no longer be
recovered once `w.best` has already been mutated by earlier sets. Acceptable one-time
ceiling for the version boundary; do not attempt to reconstruct it further.

## 2. New pure-ish helper: `recomputeBestForExercise`

```
recomputeBestForExercise(w, exerciseId) -> void
```

Mutates `w.best[exerciseId]` and reconciles `w.prs` in place. Call after any deletion or
unlog completes (API delete done, local array already updated) — see call sites below.

Logic:
1. Collect every currently-`logged` set for `exerciseId` across all of `w.entries` (an
   entry matches on `entry.exerciseId === exerciseId`; only sets with `.logged === true`
   count — this is what makes `unlogSet` and post-splice `removeSetRow` naturally exclude
   the removed/unmarked set, no separate "excluding the deleted one" logic needed).
2. From that collected set list, find `wSet` = the set with the highest `weight`, and
   `vSet` = the set with the highest `weight * reps` (independently — same two-track
   split as `computeBestByExercise`, just also keeping the winning set's `{weight, reps}`
   instead of only the number, because a surviving PR record needs those fields).
3. `pre = w.preBest[exerciseId] || { w: 0, v: 0 }`.
4. `w.best[exerciseId] = { w: Math.max(pre.w, wSet ? wSet.weight : 0), v: Math.max(pre.v, vSet ? vSet.weight * vSet.reps : 0) }`.
5. `weightStillPR = !!wSet && wSet.weight > pre.w`; `volumeStillPR = !!vSet && (vSet.weight * vSet.reps) > pre.v`.
   (A track can only be "still PR" from a *session* set, never from `pre` itself — this
   is why historical sets never need their own reps tracked.)
6. Find the existing `w.prs` record for `exerciseId` (same lookup `recordPR` already uses,
   `1172-1181`). If `weightStillPR`, upsert its `weightPR` sub-object with `wSet`'s
   `{weight, reps}` (match whatever field names `recordPR` currently writes — read
   `recordPR` before wiring this, do not guess a new shape); if not, delete the
   `weightPR` sub-object from the record if present. Same for `volumePR` / `vSet`.
   If the record ends up with neither `weightPR` nor `volumePR`, remove the whole record
   from `w.prs` (don't leave an empty husk).
7. No-op safely if `exerciseId` has no `w.prs` record and no session sets remain — i.e.
   never throws on an exercise that was never a PR.

`computeBestByExercise` itself is untouched — this is a sibling helper, not a
refactor, because it needs the winning *set* (for `reps`), not just the winning number.

## 3. Call sites to change

| Site | Line (pre-edit) | Change |
| --- | --- | --- |
| `launchDay` | ~`861` | add `w.preBest = computeBestByExercise(logs)` next to the existing `w.best` seed (§1) |
| migration check | ~`888` | add `if(!w.preBest) w.preBest = computeBestByExercise(logs)` sibling to the existing `w.best` migration line |
| `removeSetRow` | `1025-1046` | after the existing splice from `entry.sets` (~`1043`) and before `renderActiveWorkout()`, call `recomputeBestForExercise(w, entry.exerciseId)` |
| `removeExercise` | `1060-1074` | after the delete loop (`1069-1071`) and entry removal (`1072`), call `recomputeBestForExercise(w, exerciseId)` using the exerciseId captured before the entry was removed |
| `unlogSet` | `1280-1296` | after `logged=false; logId=null` (`1289-1290`) and before `renderActiveWorkout()`, call `recomputeBestForExercise(w, entry.exerciseId)` |

## 4. Edge cases the implementation must hold

- Deleting a set for an exercise that was never a PR → `recomputeBestForExercise` is a
  no-op on `w.prs` (no record to touch), `w.best[exerciseId]` stays at `pre` if no
  session sets remain.
- Deleting the *only* set that made a track a PR, with no other session sets for that
  exercise remaining → that track's sub-object is removed from `w.prs`; the whole record
  is removed if the other track also isn't currently held.
- Deleting the PR-setting set while a *smaller* remaining session set still beats `pre`
  on that track → the record is updated (downgraded) to the remaining set's numbers, not
  deleted outright.
- Two sets tie on weight (one is `wSet`) → tie-break is irrelevant, both would produce
  the same `w.best.w`; picking either as `wSet` for the reps field is acceptable (record
  which one non-deterministically, no spec requirement to prefer earliest/latest).
- `w.preBest[exerciseId]` undefined (exercise never performed before this session) →
  treated as `{ w: 0, v: 0 }`; any first session set is a PR on both tracks, consistent
  with existing `classifySetPR` behavior for a first-ever exercise.
- `recomputeBestForExercise` must never touch `w.best`/`w.prs` entries for any
  `exerciseId` other than the one passed in.
- Calling `recomputeBestForExercise` twice in a row with no state change between calls
  is idempotent (safe to call defensively; not required to skip redundant calls).

## 5. Self-test additions (existing `#selftest` block)

Regression locks (part 1 — no behavior change, just proving current correctness):

1. Fixture: logs array containing a day-old completed session plus a synthetic
   "already logged this session" entry with today's date and a higher `id`. Call
   `lastTimeForExercise` with the array **excluding** the synthetic entry (the actual
   contract `buildEntriesFromDay`'s single call site relies on) and assert it returns the
   day-old session's sets — then assert that calling it **including** the synthetic entry
   would instead return the synthetic entry (most-recent-day grouping), proving why
   `buildEntriesFromDay` must only ever be called once, before any current-session sets
   exist. Add a one-line source comment at the `buildEntriesFromDay` call site (~`817`)
   pointing at this test.
2. Fixture asserting `computeBestByExercise` gives a `weightPR`-only result for a
   low-rep heavy set (e.g. 100kg × 1) with no minimum-rep/"test set" gate involved —
   explicit regression case for "any completed set counts, not just a dedicated max
   test."

New behavior (part 2 — the real fix):

3. `recomputeBestForExercise` fixture: exercise with `preBest = {w:70, v:400}`; one
   session set of 85kg×1 makes `weightPR` fire (`w.best.w` → 85, `w.prs` gets a
   `weightPR`); remove that set from the fixture's logged-sets list and call
   `recomputeBestForExercise` — assert `w.best[exerciseId]` reverts to `{w:70, v:400}`
   and the `weightPR` sub-object (or the whole record, if `volumePR` also absent) is
   gone.
4. Typo-correction fixture: log 85kg×1 (typo, PR fires), "delete" it, "relog" 65kg×1
   (below `preBest.w` of 70) — assert final `w.best.w === 70` and no `weightPR` record
   remains for the exercise.
5. Partial-downgrade fixture: two session sets, 85kg×1 and 75kg×1, both above
   `preBest.w = 70`; `weightPR` holds 85kg. Remove the 85kg set only — assert the record
   downgrades to 75kg rather than being deleted (75 still beats `preBest.w`).
6. Isolation fixture: recomputing exercise A's PR state must leave exercise B's
   `w.best`/`w.prs` entries byte-for-byte unchanged.
7. Migration fixture: `w.preBest` absent on a fixture workout object → the migration
   line derives it from the supplied `logs` without throwing, and a subsequent
   `recomputeBestForExercise` call behaves normally afterward.

Fixtures are inline literals in `runSelfTest`, matching the existing style (no framework,
no fixtures file).

## 6. Explicitly out of scope

- Editing a logged set's weight/reps directly through wger's own web UI (outside this
  app) is not detected or reconciled — this app only reacts to deletes/unlogs it
  performs itself. Known ceiling, not fixed here.
- No change to `computeBestByExercise`'s existing return shape or call sites — the new
  helper is additive.
- No UI change to how PRs are displayed; this phase only fixes what state is *stored*.
