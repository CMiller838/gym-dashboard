# Phase 1 — Date and time correctness (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-haves 5 (elapsed time), 7 (history sort), 1 (last-performed values).

Decision gates answered by the user:
- **Gate 1:** do both — fix the confirmed recorded-duration bug *and* apply defensive fixes
  for the observed live-timer bug.
- **Gate 2:** Path A — client-side sort by `date`, then `time_start`, then `id`, as one shared
  comparator reused by the Previous-column lookup and later phases.
- **Gate 3:** Path A — a `#selftest` block in `index.html` running `console.assert` over the
  pure helpers.

No new dependencies. No new files beyond this spec and `tasks.md`.

---

## 1. Findings that the implementation must be built on

### 1.1 Confirmed: UTC/local date mismatch (root cause of the wrong recorded duration)

`index.html:365-368`:

- `todayISO()` derives the day from `new Date().toISOString().slice(0,10)` — **UTC**.
- `nowTimeISO()` derives the clock time from `d.toTimeString().slice(0,8)` — **local**.

Both are written to the same wger session record in `launchDay` (`index.html:716-721`:
`date: todayISO(), time_start: nowTimeISO()`), and `finishWorkout` patches
`time_end: nowTimeISO()` (`index.html:1131`). So the stored `date` and the stored times come
from two different clocks. In UK summer time (UTC+1) any workout started between 00:00 and
01:00 local is filed under the **previous** day while carrying a `00:xx` local start time.

Same root cause, second site: the streak loop at `index.html:490-495` does
`checkDate.setHours(0,0,0,0)` (local midnight) and then `checkDate.toISOString().slice(0,10)`.
Local midnight at UTC+1 is 23:00 UTC the day before, so **every** iteration tests the wrong
day key and the streak is systematically off by one for the whole of BST. Fix the shared
derivation once and both sites are correct — do not patch them separately.

### 1.2 Disproven: the "adopted session" suspicion in the roadmap

`docs/roadmap.md` suspected `startWorkout` adopts an existing unfinished wger session, which
would leave `startedAtMs` meaning "reopened" rather than "started". It does not.
`startWorkout` (`index.html:672-688`) only loads the routine structure and calls `launchDay`,
which always `POST`s a fresh session (`716`). The duplicate-session guard is purely the
error branch at `736-737` (wger returns 500/unique and the user is told to finish the other
session). `startedAtMs` (`729`) is therefore always the true start of *this* session, and it
survives reloads because the active workout is persisted to `localStorage`
(`setActive`/`getActive`, `index.html:230-231`). **The elapsed-time arithmetic is correct.**
Do not rework `startedAtMs` to read wger's `time_start`.

### 1.3 Observed but not reproduced: live timer showing wrong minutes

Second pass over every place elapsed time is computed or displayed found no arithmetic error
(see 1.2). The only code-level explanation consistent with the report is **staleness, not
miscalculation**:

- `index.html:843-845` — the timer is repainted by `setInterval(updateTimer, 30000)`. Mobile
  browsers and installed PWAs throttle or fully suspend timers when the tab is backgrounded
  or the screen locks. Between sets the phone screen sleeps for minutes; on unlock the header
  still shows the last value computed before suspension, and stays wrong until the next tick
  fires. Nothing recomputes on `visibilitychange`, `pageshow` or `focus` — grep confirms
  there are no such listeners anywhere in the file.
- `index.html:856` uses `Math.round`, so labels flip at the half-minute; combined with a 30 s
  tick the display can read a full minute away from the user's own clock even when awake.
- `resumeBannerHtml` (`index.html:417`) computes its minutes once at render time and is never
  updated at all — the same staleness class, on the main screen.

**Record in the code and in the phase notes: observed but not reproduced.** The fixes below
are defensive; they remove every stale-display path found, but no failing arithmetic was
identified. If the symptom recurs after this phase, the next step is capturing
`Date.now() - startedAtMs` alongside the rendered string at the moment it looks wrong.

### 1.4 Confirmed: history ordering ties on a day-granularity field

`index.html:436-440` fetches `/workoutsession/?ordering=-date` and `/workoutlog/?ordering=-date`
through `apiAll`. `WorkoutSession.date` is day-granularity, so two sessions on one day tie and
fall back to whatever order wger's paginator returns — which can also vary across page
boundaries inside `apiAll`. The array is then consumed in fetch order by `renderHistory`
(`479`, `511` `sessions.slice(0, 30)`) and the stats block (`486-498`).

### 1.5 Previous column: verify, don't rebuild

`lastTimeForExercise` (`index.html:630-638`) already implements the required fallback (most
recent time the exercise was *ever* logged, not just last session), `buildEntriesFromDay`
(`653`) populates `entry.lastTime`, and it renders in the Previous column and pre-fills set
inputs (`656-658`). Two real defects in it:

1. It sorts with `new Date(b.date) - new Date(a.date)` — the same ad-hoc ordering Gate 2
   replaces with the shared comparator.
2. It groups "the most recent day's sets" by **exact string equality** on `l.date`
   (`634-635`). This is only correct if wger returns `WorkoutLog.date` as a date-only string.
   If this wger instance returns a full datetime for logs, every set of the same session has a
   different timestamp and the Previous column silently collapses to a single set. The
   implementation must be robust to both shapes (see `dayKey` below) **and** the builder must
   confirm empirically which shape the live API returns — log one real `/workoutlog/` record
   and record the answer in the phase notes.

Known ceiling, deliberately not fixed in this phase: logs are fetched with `limit=500`
(`438`, `712`), so an exercise not performed within the last 500 logged sets shows a blank
Previous column. Mark with a `ponytail:` comment; revisit only if it bites.

---

## 2. Target design

All work is inside the existing `<script>` in `index.html`. Helper functions go next to the
existing date helpers (`index.html:356-369`).

### 2.1 New / changed pure helpers

```
localDateISO(d = new Date()) -> string        // "YYYY-MM-DD" from LOCAL getFullYear/
                                              // getMonth+1/getDate, zero-padded.
                                              // No toISOString, no locale strings.

todayISO() -> string                          // becomes: return localDateISO();

dayKey(v) -> string                           // "YYYY-MM-DD" from an API date field of
                                              // either shape:
                                              //   "2026-09-07"            -> slice(0,10)
                                              //   "2026-09-07T21:30:00Z"  -> localDateISO(new Date(v))
                                              // null/undefined -> ""

compareSessionsDesc(a, b) -> number           // newest first. Ordered keys:
                                              //   1. dayKey(b.date) vs dayKey(a.date)   (string compare)
                                              //   2. (b.time_start||"") vs (a.time_start||"")
                                              //   3. (b.id||0) - (a.id||0)
                                              // Records missing time_start sort AFTER same-day
                                              // records that have one. Comparator is total and
                                              // stable-safe: never returns NaN.

sortSessionsDesc(list) -> array               // non-mutating: [...list].sort(compareSessionsDesc)
```

`compareSessionsDesc` operates on any object with `{date, time_start?, id}`, so it serves
workout sessions and workout logs alike — that is the reuse Gate 2 asked for, and Phase 3's
PR/history figures will consume the same function.

Lexicographic comparison on `"YYYY-MM-DD"` is chronological; do not construct `Date` objects
inside the comparator.

### 2.2 Call sites to change

| Site | Line (pre-edit) | Change |
| --- | --- | --- |
| `todayISO` | 365 | delegate to `localDateISO()` |
| streak loop | 494 | `checkDate.toISOString().slice(0,10)` → `localDateISO(checkDate)` |
| `render()` fetch | 436-440 | after the generation guard (`444`), run `sessions = sortSessionsDesc(sessions)` before anything consumes it (stats `486-498`, `renderHistory` `461`). Keep the server-side `ordering=-date` query param — it still cuts the working set. |
| `lastTimeForExercise` | 632 | sort with `compareSessionsDesc` |
| `lastTimeForExercise` | 634-635 | `mostRecentDate` → `mostRecentDay = dayKey(exLogs[0].date)`; filter with `dayKey(l.date) === mostRecentDay` |
| `updateTimer` | 856 | `Math.round` → `Math.floor` |
| `updateTimer` | 851-858 | also update the resume banner's minutes element if present (see 2.3) |
| `renderActiveWorkout` | 843-845 | delete `timerInterval` and its `setInterval(updateTimer, 30000)`; `tickRestTimers` (already 1 Hz, `848`) calls `updateTimer()` each tick. One interval instead of two. |
| `finishWorkout` / `discardWorkout` | 1138, 1164 | remove the now-dead `clearInterval(timerInterval)` lines and the `let timerInterval` declaration (`~226`) |
| new listener | near `render()` at 1178 | `visibilitychange` + `pageshow` → if `document.visibilityState === "visible"` and `getActive()`, call `updateTimer()` |
| `resumeBannerHtml` | 417-419 | wrap the minutes in `<span id="resumeMins">` so `updateTimer` can refresh it without a re-render |
| `finishWorkout` | 1131 | add a `ponytail:` comment noting the cross-midnight ceiling (see 2.4) |

`updateTimer` becomes the single elapsed-time painter: it reads `getActive()`, computes
`Math.floor((Date.now() - w.startedAtMs) / 60000)`, and writes to `#wtimer` if present and
`#resumeMins` if present. It must remain a no-op when neither element exists.

### 2.3 Edge cases the implementation must hold

- `getActive()` returns `null` → `updateTimer` returns immediately (existing behaviour, keep).
- Element missing (main screen vs workout screen) → skip that element, don't throw.
- Clock moved backwards / `startedAtMs` in the future → `Math.max(0, …)` stays.
- `time_start` `null` on wger sessions created by other clients → comparator must not throw.
- `date` missing entirely → `dayKey` returns `""`, sorts last, no `Invalid Date`.
- BST/GMT transition: `localDateISO` uses local calendar fields only, so a DST shift cannot
  move the recorded day.
- `dayKey` on a datetime crossing local midnight (e.g. `23:30Z` at UTC+1) resolves to the
  local day, matching what the history list shows.

### 2.4 Explicitly out of scope (record, don't fix)

- **Cross-midnight sessions.** wger's session model is `date` + `time_start` + `time_end`, so a
  workout from 23:30 to 00:15 stores `time_end < time_start` and wger renders a nonsense
  duration. Not representable in the API; leave a `ponytail:` comment at `finishWorkout`
  naming the ceiling. Do not invent a workaround.
- **`daysAgo`** (`360-363`) parses `"YYYY-MM-DD"` as UTC midnight and subtracts local `now`.
  It feeds only the approximate "Last 7d" counter; a ±1 day boundary wobble is accepted.
  Leave it, note it in the phase notes.
- **`fmtDate`** (`356-359`) renders correctly at UTC+0/+1 and is only cosmetic. Untouched.
- **The 500-log fetch window** for the Previous column (see 1.5).
- Reworking `startedAtMs` to derive from wger's `time_start` (see 1.2).

---

## 3. Self-test block (Gate 3, Path A)

At the end of the existing `<script>`, gated behind the URL hash so it never runs for real
users:

```
runSelfTest() -> void        // console.assert per case; counts cases; ends with a single
                             // console.log("selftest: N checks, M failed").
                             // Called only when location.hash === "#selftest".
```

Cases (pure functions only — no network, no DOM):

1. `localDateISO(new Date(2026, 0, 5, 0, 30))` → `"2026-01-05"`; zero-padding of month and
   day; a late-evening local time does not roll to the next day.
2. `localDateISO` vs `toISOString().slice(0,10)` divergence: construct a local-midnight date
   and assert `localDateISO` returns that local day (the regression the streak loop had).
3. `dayKey("2026-09-07")` → `"2026-09-07"`; `dayKey("2026-09-07T21:30:00Z")` →
   the local day of that instant; `dayKey(null)` → `""`.
4. `compareSessionsDesc` orders: different days by day; same day by `time_start` descending;
   same day and same `time_start` by `id` descending; a `null` `time_start` sorts after a
   present one on the same day; comparator returns `0` for identical inputs.
5. `sortSessionsDesc` does not mutate its input and puts two same-day sessions in
   later-`time_start`-first order (the exact must-have 7 regression).
6. `lastTimeForExercise` over a fixture array: returns `[]` for an unknown exercise; returns
   only the most recent day's sets in ascending `id` order; falls back to an older day when
   the exercise is absent from the newest day (the must-have 1 fallback); returns all sets of
   a session when the fixture uses **datetime** `date` values that differ by seconds (the 1.5
   defect).

Fixtures are inline literals in `runSelfTest`. No framework, no fixtures file, no assertions
over render functions.

Manual verification (not automated — needs the real API and a phone):

- Start a workout, background the app / lock the screen for ≥3 minutes, reopen → header
  minutes match wall clock immediately, without waiting for a tick.
- Reload mid-workout → elapsed time continues from the real start.
- Finish a workout, check the session in wger → `date` is the local day and the recorded
  duration matches the session length.
- History tab with two sessions on one day → later session listed first.
- Previous column shows the prior session's sets, including for an exercise skipped last
  session (fallback path).
