# Roadmap

v3 — sequenced from `docs/outline-v3.md` (2026-09). v2's roadmap is complete and
archived at `.claude/archive/roadmap-v2.md`. Non-goals from the outline (how-to-do-it
video content, server-push notifications, multi-user) are out of scope for this
roadmap entirely.

Phases are ordered by real dependency, not by size: the data-integrity bug fixes come
first because a later phase (the summary redesign) displays the exact PR figures they
correct; timer reliability and the audio overhaul are bundled because firing a rest-timer
alert "audibly" *is* the audio work; and the cross-cutting interaction-feedback pass
runs last, once every screen it touches (timer, set logging, summary, history view) is
in its final v3 shape — mirroring v2's "restyle last" rationale so nothing gets
polished twice.

Per `.claude/rules/roadmap-gating.md`, a phase is marked `— done` in the same commit
as the code that finished it. Detailed specs are written per phase by
`@planner Phase N`, immediately before that phase is built — not now.

---

## Phase 1 — Data integrity: last-time baseline and PR tracking

**Goal:** Fix the two "the app shows/records the wrong thing" bugs before anything
downstream (the summary redesign) renders the values they produce.

Covers must-haves 2 (last-time baseline overwrite) and 3 (PR = heaviest weight in any
completed set, not just a dedicated max test).

Both are logic fixes to existing state/calc code — `entry.lastTime` and the
`sessionBest` / `computeBestByExercise` path (index.html) — not new screens, so they're
bundled as one small, low-risk phase ahead of everything that reads their output.

**Exit condition:** the Previous-set value shown next to an in-progress set stays pinned
to the last *completed* session until the current set is itself completed; a PR is
recognized from any completed set's weight, not only a dedicated max-test set.

---

## Phase 2 — Rest-timer reliability and audio overhaul [opus?]

**Goal:** Make rest-timer alerts impossible to miss while the app is open and in view,
and give every timer/cue/alert a distinct, louder sound.

Covers must-haves 1 (reliable rest-timer alerts) and 4 (audio overhaul).

Bundled because they're the same code path: the timer already stores an absolute
`restEndMs` end-timestamp and polls it every second (`tickRestTimers`), but today it
silently clears when it reaches zero — no sound fires at all. Making the alert fire
"audibly" and adding a Wake Lock + `visibilitychange` catch-up is inseparable from
building the distinct/louder sounds it needs to play; splitting them would mean touching
`tickRestTimers` and the existing `beep()` helper twice.

**Scope flag — background/locked-phone case is explicitly out.** Per the outline, this
phase covers only the tab-open-and-visible case (Wake Lock + absolute-timestamp
self-correction + visibilitychange catch-up), not a fully backgrounded or locked phone.
If on-device testing during this phase shows that bar isn't met, escalating to a service
worker is a scoped `@architect` decision made at that point, not assumed here — tagged
`[opus?]` because that potential escalation is a genuine architectural fork (this app
has no service worker today by design), not because the lighter tier itself is complex.

**Exit condition:** a rest timer fires a distinct, audible alert whenever the app is
open and in view, including after being backgrounded and returning within the same
tab session; set-completion, PR, and timer-end sounds are all distinguishable from each
other at a higher default volume.

---

## Phase 3 — In-workout exercise history/trend view (Status: logic/UI built and self-tested; manual on-device verification outstanding, see `tasks.md`)

**Goal:** Tapping an exercise name during an active routine opens a detail view with
lifetime stats and a trend graph for that exercise.

Covers must-have 5.

Mostly additive — a new detail screen reading existing logged-set history — so it has
no hard dependency on Phases 1–2, but is sequenced after Phase 1 so the trend data it
displays (PR/history figures) is already correct rather than needing a second pass.

**Exit condition:** tapping an exercise name mid-workout opens a history/trend view
showing lifetime stats and a graph for that exercise, escaped per the app's
API-derived-string invariant.

---

## Phase 4 — Polished summary view (Status: logic/CSS built and self-tested; manual on-device verification outstanding, see `tasks.md`)

**Goal:** Redesign the workout-completion screen with smoother transitions/animations
and cleaner stat formatting.

Covers must-have 6.

Depends on Phase 1: the summary displays PR and volume figures, which must already be
correct before the redesign locks in how they're formatted — otherwise the formatting
work gets redone once the underlying figures change. Independent of Phases 2 and 3.

**Exit condition:** the post-workout summary screen has polished transitions and stat
formatting, with all existing summary data (volume, PRs, muscle groups) still correct
and intact.

---

## Phase 5 — Feedback on every touched interaction (Status: CSS built app-wide at explicit user request, broader than the original "what v3 touches" scope below; manual on-device verification outstanding, see `tasks.md`)

**Goal:** Every screen/interaction v3 actually modified — timer, set logging, summary,
history view — gets a visible/audible response to the interaction.

Covers must-have 7.

Runs last by definition: its scope is explicitly "what v3 touches," which isn't fully
known until Phases 1–4 land. Doing it earlier risks covering an interaction that a
later phase then changes, requiring the feedback work to be redone — the same
double-work reasoning v2 used to run its UI pass last.

**Exit condition:** every interaction touched by Phases 1–4 (timer start/end, set
logging, summary appearance, opening the history view) has a visible or audible
response; no untouched part of the app is retrofitted.

---

## Phase 6 — Nice-to-haves: stalled-workout auto-complete, routine reordering

**Goal:** Pick up the two lower-priority items the outline explicitly scopes into v3
("later in v3") once the must-haves above ship.

Covers the outline's two nice-to-haves: auto-completing a session/exercise that's been
open past 3 hours, and drag-and-drop reordering of routines/exercise lists.

Both are independent of Phases 1–5 (session-timeout housekeeping and routine-list
ordering don't share code with the timer/PR/summary/history work above) — sequenced
last only because the outline ranks them below the must-haves, not because of a code
dependency.

**Exit condition:** a session/exercise left open past 3 hours auto-completes instead of
polluting history/stats; routines and exercise lists can be reordered by drag-and-drop.

---

## Assumptions and flags (planner, v3 roadmap pass)

- Read against the live `index.html`: `restEndMs`/`tickRestTimers` already use an
  absolute end-timestamp and poll every second, but no sound or Wake Lock exists yet on
  timer completion, and `visibilitychange` today only re-syncs the elapsed-workout
  clock (`updateTimer`), not a rest-timer catch-up alert — Phase 2's "reliable alerts"
  work is real, not just a volume/tone tweak.
- Phase 2's `[opus?]` tag is a heads-up for a possible service-worker escalation, not a
  verdict — `@planner Phase 2` and testing decide for real whether the lighter tier
  (Wake Lock + timestamp + visibilitychange) meets the reliability bar.
- Nice-to-haves are sequenced as Phase 6 rather than deferred to `docs/FUTURE.md`,
  since the outline frames them as "this project, later in v3," not out of scope.
