# v4 Outline — Background Reliability, PR Medals, Routine Preview

v3 (`docs/outline-v3.md`, roadmap in `docs/roadmap.md`) is complete. This batch is a
fresh round of real-usage feedback, not a continuation of v3's scope.

## Problem

Since v3 shipped, real usage surfaced gaps in two categories: (1) the rest-timer alert
is still not reliable enough in practice — inaudible over music, and silent entirely
once the phone is locked or the app is backgrounded — and (2) three features that don't
exist yet would remove daily friction: seeing which set was a PR at a glance (not just
in the moment it happens), previewing a routine's exercises/last-lift without starting
a session, and a trend graph that's actually readable.

## Target users

Same as v3: solo lifter using this as a personal log against their own wger account.
No multi-user concerns.

## Must-haves

1. **Louder timer audio** — v3's audio overhaul (distinct sounds, raised volume) still
   isn't loud enough to cut through music during a set. Raise output further; needs
   on-device verification against real music playback, not just quiet-room testing.
2. **Background/locked-phone timer alerts** — vibration and an actual OS notification
   must fire when the timer ends while the app is backgrounded or the phone is locked,
   not just foreground-and-visible (which v3 already covers). This is the case v3's
   outline explicitly scoped out and flagged as a possible service-worker escalation.
   **Decided** (see `docs/ARCHITECTURE.md` ADR 001, and target device confirmed as
   Android): ship ADR 001's Option A — a minimal service worker whose only job is
   hosting `showNotification()`, armed by a page-side `setTimeout` when the tab goes
   hidden with a live rest timer. No `fetch`/`push`/background-sync handlers — scoped
   strictly to local notification delivery, nothing else, per the no-backend invariant.
   Known ceiling: works on Android/Chrome (locked screen, backgrounded, vibration,
   rests under ~5 min); does not work on iOS Safari at all (WebKit suspends the page on
   lock/background, and there's no scheduled-notification API to fall back on) — not a
   target for this build since the daily device is Android, but worth remembering if
   iOS is ever added as a target later.
3. **Persistent PR medals** — a medal/icon marks the exact set that was a PR (weight or
   volume), visible both in the current routine's set list and in history — not just
   as the transient toast/summary-screen badge that exists today. Recomputed, not
   cached: if that set is later edited to no longer be the record, or deleted, the
   medal is removed (and may move to whichever set is now the actual record). Builds on
   the existing `classifySetPR`/PR-tracking logic from v3 Phase 1.
4. **Routine preview view** — tapping a routine's name (outside an active session) opens
   the same exercises + last-time-hit layout the active-workout start view already
   shows, but read-only — no session/log is created. Each exercise row also shows its
   current PR (weight and/or volume), tying into must-have 3.
5. **Readable, 3-month exercise trend graph** — the existing in-workout trend graph
   (`buildTrendPoints`/`renderTrendSvg`) currently plots the last 20 *days-with-data*
   points with no axis labels, values, or dates — an arbitrary window, unverified
   against any real time range. Rework it to: (a) show actual values and dates on/near
   the points, and (b) pull from a fixed trailing 3-calendar-month window instead of
   "last 20 logged days."

## Nice-to-haves

None surfaced this round — everything raised was placed as a must-have.

## Constraints

- No new dependency without confirming with the user first (standing project rule).
- No backend — wger's API remains the only server-side state. A service worker for
  must-have 2, if adopted, must only enable local notifications, not any server-push
  mechanism.
- Solo build, same vanilla HTML/CSS/JS single-file constraint as the rest of the app.
- Must-have 2's service worker is scoped to local notification delivery only (see ADR
  001) — no `fetch`/`push`/background-sync handlers without a separate architecture
  decision, same bar as adding a new dependency.

## Non-goals

- Multi-user or shared-routine features — still out of scope.
- Per-exercise how-to-do-it video/animation content — still parked in `docs/FUTURE.md`.
- Server-side/push notifications — must-have 2 stays local-device-only regardless of
  whether a service worker is adopted to deliver it.
