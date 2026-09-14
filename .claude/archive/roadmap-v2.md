# Roadmap

Sequenced from the `idea-interview` must-have list (2026-09). One parked idea —
per-exercise how-to-do-it animation — is in `docs/FUTURE.md` and is not part of this
roadmap.

Phases are ordered by real dependency, not by size: the date/time bugs come first
because two later phases read the same ordering code, and the UI pass comes last so
the restyle sees the finished markup (the bottom resume bar and the summary screens
included) rather than being applied twice.

Per `.claude/rules/roadmap-gating.md`, a phase is marked `— done` in the same commit
as the code that finished it. Detailed specs are written per phase by
`@planner Phase N`, immediately before that phase is built — not now.

---

## Phase 1 — Date and time correctness

**Goal:** Find and fix the real root causes behind the wrong elapsed-time display and
the wrong history date/sort, and confirm the existing "last time" lookup is correct
once ordering is trustworthy.

Covers must-haves 5 (elapsed time), 7 (history sort), 1 (last-performed values).

**Scope flag — unscoped until investigated.** Both bugs are reported by symptom; their
causes are not confirmed. Two independent prime suspects, and they are *not* assumed to
share a cause:

- Elapsed time: `startedAtMs` is set to `Date.now()` in `launchDay` (index.html:729),
  including on the path where `startWorkout` adopts an existing unfinished wger session
  via the duplicate-session guard — so the timer may count from "reopened" rather than
  "started", and wger's own session start field is unused.
- History order: sessions are fetched with `ordering=-date` (index.html:438) against a
  day-granularity `date` field, so same-day sessions tie and fall back to arbitrary
  order.

**Why must-have 1 is here, not in a feature phase:** the last-performed value is already
implemented — `lastTimeForExercise` (index.html:630) already falls back to the most
recent time an exercise was ever logged, `buildEntriesFromDay` populates `entry.lastTime`,
and it renders in a Previous column. It shares the date-ordering code under suspicion, so
this phase verifies it rather than rebuilding it. If verification shows it genuinely
doesn't work, the remaining work stays in this phase.

**Exit condition:** elapsed time is correct across a resumed/adopted session and a page
reload; history lists in true recency order including multiple sessions on one day; the
Previous column shows the correct prior values, including the fallback case.

---

## Phase 2 — Active workout: keep it, get back to it, make the tap feel right

**Goal:** Make the in-progress workout impossible to lose track of — a persistent
bottom bar that resumes it from anywhere — and fix the navigation dead-ends and tap
feedback around set logging.

Covers must-haves 4 (persistent bar / don't lose progress), 3 (routing back to main
after completing or deleting a routine), 2 (sound on set completion), 6 (bigger tick
button).

**Scope flag — smaller than reported, in one respect.** Progress is not actually being
deleted: `clearActive()` is only called from `finishWorkout` (index.html:1137) and
`discardWorkout` (1163, 1175), and the active workout already persists in localStorage
with a resume banner on the main screen (417-419). So must-have 4 is an affordance
problem, not a data-loss bug — the work is the always-visible bar and the resume
routing, and there is already a persistent `.toolbar` element outside the re-rendered
`content` div (196-199) for it to live alongside.

Must-haves 2 and 6 are genuinely small and ride along because they touch the same set
row: `triggerSetFeedback` (1048) already exists with `navigator.vibrate`, so sound is a
few lines beside it, and no new dependency is needed for it. Must-have 6 is `.logbtn`
CSS (145-147) plus a tap-target check.

**Exit condition:** navigating away from an active workout leaves a tappable bar naming
the in-progress routine that returns to the workout screen; completing or deleting a
routine lands on the main screen; every set-completion tap plays a sound; the tick
button meets a comfortable thumb target.

---

## Phase 3 — Post-workout summary (Status: Complete — logic/UI built and self-tested; manual on-device verification against the live API still outstanding, see `tasks.md`)

**Goal:** After finishing a workout, show a short slideshow of what was achieved —
total weight lifted, PRs hit, muscle groups trained.

Covers must-have 8.

**Scope flag — the riskiest phase, and the one most likely to grow.** Only part of the
data exists:

- PRs: half-built already. `computeBestByExercise` (index.html:620) and the `sessionBest`
  map maintained during `logSet` (1093-1097) give per-exercise bests; a session-vs-history
  comparison for "PRs hit this session" is a small addition on top.
- Total weight lifted: not computed anywhere today. Straightforward, but new.
- Muscle groups: **not present in the app at all.** This needs muscle/category metadata
  that the cached `exercise_index_v1` (`loadExerciseIndex`, index.html:322) may not
  store, which means either a cache-schema bump plus a re-fetch, or extra
  `/exerciseinfo/` reads at summary time. If this turns out to cost a slow extra fetch
  on every workout finish, dropping muscle groups from the slideshow is the cheap exit —
  that call belongs in the phase spec, not here.

Depends on Phase 1 (PR/history figures are only trustworthy once date ordering is) and
Phase 2 (the summary is the screen the finish flow routes into).

**Exit condition:** finishing a workout shows the summary before returning to the main
screen, with correct volume and PR figures; muscle groups either shown or explicitly
dropped with the reason recorded.

---

## Phase 4 — UI modernization

**Goal:** A full visual design pass over the app via `ui-prototyper` →
`restyle-from-prototype`, applied once the functional work is finished.

Covers must-have 9.

**Sequencing decision (confirmed with the user):** this phase runs last. The bottom
resume bar (Phase 2) and the summary screens (Phase 3) are a persistent screen-agnostic
element and a whole new screen type respectively — both need to exist in the prototypes
before a design language is locked, otherwise they get styled ad-hoc against a system
that never modelled them. Restyling last also means the small tweaks in Phase 2 aren't
restyled twice. Cost of deferring is low: it's one `<style>` block (index.html:16-186)
with `:root` tokens already at 17-21.

**Scope flag — full design pass, not a tweak.** `restyle-from-prototype` restructures
markup as well as styles, so every data binding, `onclick` handler and selector in the
restyled regions has to be carried across in the same edit. The invariants in
`CLAUDE.md` still hold through the restyle — in particular every API-derived string
stays behind `esc()` in any new render path.

**Exit condition:** a chosen prototype's design language is applied to the live app with
all interactivity intact — set logging, the resume bar, the summary, tab navigation and
the token flow all still work against the real wger API.
