# v3 Outline — Session & Exercise Tracking, Reliability, and Feel

## Problem

Two classes of problem, bundled into one v3: (1) data-integrity bugs where the app
shows or records the wrong thing — a stale "last time" baseline overwriting mid-set,
ambiguous PR logic — and (2) the in-gym experience feels unreliable and flat: rest-timer
alerts can be missed when the phone is locked or the app is backgrounded, and
interactions give little feedback. v3 fixes the trust-eroding bugs and makes the core
loop (log a set, rest, get alerted, repeat) feel responsive.

## Target users

Same as today: solo lifter using this as a personal workout log against their own wger
account. No multi-user or shared-account concerns.

## Must-haves

1. **Reliable rest-timer alerts** — the timer must fire visibly/audibly whenever the app
   is open and in view, without adding a service worker. Approach: store an absolute
   end-timestamp (`Date.now() + duration`) rather than a counting-down value, so drift
   from throttled `setInterval`/`setTimeout` self-corrects; hold a Screen Wake Lock while
   a rest timer is running (released when it ends) to keep the screen on and the alert
   visible; on `visibilitychange` back to visible, compare against the stored
   end-timestamp and fire the alert immediately if it's already past, catching up
   timers that elapsed while the tab was briefly backgrounded. This does not cover the
   phone-locked/app-fully-backgrounded case (see Constraints — that needs a service
   worker and is a scoped `@architect` decision if the lighter tier above proves
   insufficient in testing, not silently dropped).
2. **Fix "last time" baseline overwrite** — the previous-session comparison value shown
   next to a set must not update while a set is in progress; it should reflect the
   last *completed* session until the current set is itself completed.
3. **Clarify PR tracking** — a PR is the heaviest weight logged in *any* completed set,
   not only a dedicated single-rep max test. Both count.
4. **Audio overhaul** — increase master volume and give timer completions, cues, and
   alerts distinct, recognizable sounds from each other.
5. **In-workout history/trend view** — tapping an exercise name during an active
   routine opens a detail view with lifetime stats and a trend graph for that exercise.
6. **Polished summary view** — redesign the workout-completion screen with smoother
   transitions/animations and cleaner stat formatting.
7. **Feedback on every touched interaction** — every screen/interaction v3 actually
   modifies (timer, set logging, summary, history view) gets a visible/audible response
   to the interaction. Scoped to what v3 touches — not a retrofit of untouched parts of
   the app.

## Nice-to-haves (this project, later in v3)

- **Auto-complete stalled workouts** — automatically finish an exercise or session that
  exceeds 3 hours, so abandoned sessions stop polluting history/stats. Real problem,
  but the app is usable without it while the must-haves above ship first.
- **Routine drag-and-drop reordering** — rearrange routines and exercise lists by
  dragging. Convenience, not a blocker for core session/exercise tracking.

## Constraints

- No new dependency without confirming with the user first (standing project rule).
- No backend — wger's API remains the only server-side state (standing architecture
  invariant).
- Reliable background rest-timer alerts likely want a service worker for local
  notifications, which this app currently has none of by design. Before adopting one,
  explore lighter alternatives (e.g. Notification API without a service worker, audio
  + vibration while the tab is alive, wake-lock to keep the screen active during a rest
  period) and only escalate to a service worker via `@architect` if those don't meet
  the reliability bar.
- Solo build, same vanilla HTML/CSS/JS single-file constraint as the rest of the app.

## Non-goals

- Per-exercise how-to-do-it video/animation content — already parked in
  `docs/FUTURE.md`, stays out of v3 too.
- Server-side/push notifications — any notification work stays local-device only, per
  the no-backend constraint.
- Multi-user or shared-routine features.
