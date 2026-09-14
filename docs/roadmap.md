# Roadmap

v3's roadmap is complete and archived at `.claude/archive/roadmap-v3.md`.

## v4 — Background reliability, PR medals, routine preview

Source outline: `docs/outline-v4.md`. Fresh round of scope, not a continuation of v3.

## Phase 1 — Louder timer audio

Raise rest-timer audio output further so it cuts through music during a set;
verify on-device against real playback, not just quiet-room testing.

## Phase 2 — Background/locked-phone timer alerts [opus?]

Fire vibration + an OS notification when the rest timer ends while the app is
backgrounded or the phone is locked, via the minimal service worker decided in
ADR 001 (`docs/ARCHITECTURE.md`) — `showNotification()` only, armed by a
page-side `setTimeout` on visibility change, Android-only, no `fetch`/`push`/
background-sync handlers. Sequenced after Phase 1 as the other half of
timer-alert work, but kept as its own phase rather than merged with it: this is
the app's first service worker and a genuine architectural fork, while Phase 1
is a same-day on-device audio tweak — collapsing them would drag the simple
task under the same weight as the fork.

## Phase 3 — Persistent PR medals

Mark the exact set that is the current weight/volume PR with a medal in both
the active routine's set list and history, recomputed (not cached) so edits or
deletions move or remove the medal. Builds on `classifySetPR` from v3 Phase 1.

## Phase 4 — Routine preview view

Depends on Phase 3. Tapping a routine's name outside an active session opens a
read-only reuse of the active-workout start view (exercises + last-time-hit),
with each exercise row also showing its current PR from Phase 3's data — no
session/log is created.

## Phase 5 — Readable 3-month exercise trend graph — done

Rework `buildTrendPoints`/`renderTrendSvg` to show actual values/dates on the
points and pull from a fixed trailing 3-calendar-month window instead of the
last 20 logged days. Independent of Phases 1-4; sequenced last since it has no
dependency on the rest of this batch.

Verified: `trendWindowBounds`/`buildTrendPoints`/`trendLabelIndices`/`renderTrendSvg`'s
time-proportional x-scaling reproduced and asserted in an isolated Node logic test (11
checks, all passing); full file syntax-checked with `node --check`. In-browser
`#selftest` and visual manual checks not run this session (no browser automation
available in the sandbox).
