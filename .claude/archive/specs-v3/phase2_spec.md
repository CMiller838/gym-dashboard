# Phase 2 (v3) — Rest-timer reliability and audio overhaul (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-haves 1 and 4 from `docs/outline-v3.md`. No new dependencies (Wake Lock is a
native browser API, already-available `AudioContext`/`navigator.vibrate` are extended, not
replaced), no new files beyond this spec and `tasks.md`.

Out of scope per roadmap: the background/locked-phone case. This phase only guarantees the
alert while the tab is open, whether currently visible or briefly backgrounded and returned
to within the same session. No service worker.

## 0. What investigation found (read this before touching code)

- `tickRestTimers()` (`996-1013`) polls every entry's absolute `entry.restEndMs` timestamp
  every second via `restTickInterval = setInterval(tickRestTimers, 1000)` (`983`, set in
  `launchDay`). When `remaining <= 0` it clears `entry.restEndMs = null` (`1005`) and removes
  the timer's DOM box (`1007`) — **no sound, no vibration, nothing fires today**. Because the
  remaining time is always recomputed from `Date.now() - entry.restEndMs` rather than counted
  down locally, the timer already self-corrects for setInterval drift/throttling on every
  tick that does run — the only real gaps are (a) no alert fires at zero, (b) a backgrounded
  tab can have its 1s interval throttled by the browser for up to ~60s so the alert-that-never-
  fires becomes an alert-that-fires-very-late, and (c) nothing keeps the screen awake so a
  user resting with the phone face-up can have the display sleep and the tab throttle harder.
- `beep(freqs)` (`505-521`) plays each frequency in `freqs` as a fixed-length triangle-wave
  blip via Web Audio, fixed gain `0.25` (`515-516`), only if `audioCtx` exists (silently
  no-ops otherwise, `507`). `audioCtx` is created lazily in `primeAudio()` (`496-501`) on a
  user gesture — already-established pattern for iOS autoplay restrictions, unaffected by
  this phase.
- Two existing call sites, both in the PR/set-log path (`1202-1209`): PR: `beep([880,1175,1568])`
  + `vibrate([50,40,50,40,150])`; plain set log: `beep([880])` + `vibrate(35)`. These are the
  two "distinct" sounds that already exist; the timer-end alert must be audibly different
  from both, and per the roadmap's exit condition, louder by default than these.
- `vibrate(pattern)` (`1147-1149`) is a thin `navigator.vibrate` wrapper, already silently
  no-ops when unsupported — reuse as-is.
- A `visibilitychange` listener already exists (`1432-1434`) but only calls `updateTimer()`
  (elapsed-workout-time text refresh) — it does **not** call `tickRestTimers()`, so a rest
  timer that expired while the tab was hidden waits for the next (possibly throttled)
  `setInterval` tick to notice, rather than firing the instant the tab becomes visible again.
  A sibling `pageshow` listener (`1435`) has the same gap.
- No Wake Lock API usage anywhere in `index.html` (grepped, zero hits) — this is new. Native
  `navigator.wakeLock.request('screen')`, Chrome/Edge/Safari 16.4+ support, no Firefox — must
  feature-detect and no-op silently on unsupported browsers, same pattern as `vibrate`.
- `launchDay` (`839-984`) starts `restTickInterval` at `983`, right before returning — the
  natural place to also acquire the wake lock for the workout session. `finishWorkout`
  (`1376-`) is the natural place to release it.

## 1. Decisions (planner's own calls — no Decision Gates raised)

The roadmap's prescribed approach (absolute-timestamp self-correction, already in place, +
Wake Lock + `visibilitychange` catch-up, tab-open-and-visible/briefly-backgrounded case only)
is directly followable with the existing code shape — no schema change, no new dependency, no
fork in the approach. Per planning instructions these are Tier 3 calls decided here, not put
to the user:

- **Reuse `beep()`, don't replace it.** Add an optional second parameter,
  `beep(freqs, gain = 0.32)`, replacing the hardcoded `0.25`/`0.0001`→`gain` ramp target.
  Bumping the shared default from `0.25` to `0.32` makes the two existing call sites (set-log,
  PR) louder too, satisfying "every timer/cue/alert... louder" without touching those call
  sites. The timer-end alert passes an explicit higher `gain` (`0.5`) on top of that.
- **Timer-end sound/pattern:** `beep([1200,800,1200,800], 0.5)` (a fast high-low-high-low
  buzz) + `vibrate([100,80,100,80,100])`. Chosen to be clearly distinct from the existing
  single blip (`[880]`) and the ascending triad (`[880,1175,1568]`) — alternating pitch is a
  different shape from both, not just a different frequency, and repeats/vibrates more
  insistently since a missed rest alert is the actual bug being fixed.
- **No new helper function for the timer alert.** One call site (`tickRestTimers`) — inline
  the `beep(...)`/`vibrate(...)` pair directly rather than wrapping them in a new
  `playRestAlert()` for a single caller.
- **Catch-up fix:** change the existing `visibilitychange` and `pageshow` listeners (`1432-
  1435`) to call `tickRestTimers()` instead of (`pageshow`) / in addition to (`visibilitychange`,
  which already needs `updateTimer()` too — `tickRestTimers()` already calls `updateTimer()`
  internally at `999`, so calling only `tickRestTimers()` from both listeners is a strict
  superset, no need to call both) — see §2.
- **Wake Lock lifecycle:** acquire once in `launchDay` right after `restTickInterval` is set
  (`983`); the browser auto-releases a wake lock whenever the document becomes hidden, so
  re-acquire on the same `visibilitychange` handler when the tab becomes visible again and a
  workout is active; release explicitly in `finishWorkout`. Module-level `let wakeLockSentinel
  = null;` alongside the existing `let audioCtx = null;` (`246`).

## 2. Changes

### `beep` (`505-521`)
Signature becomes `beep(freqs, gain = 0.32)`. Replace the two hardcoded `0.25`/`0.0001`
constants at `515-516` with `gain`/`gain * 0.0004` (keep the near-zero ramp start
proportional, or simply keep `0.0001` as the ramp-start floor and only parameterize the peak
`linearRampToValueAtTime(gain, ...)` — peak value is what matters for loudness, ramp-start
floor is inaudible either way). Existing call sites (`1204`, `1209`) are unchanged — they
pick up the new `0.32` default automatically.

### `tickRestTimers` (`996-1013`)
In the `remaining <= 0` branch (`1004-1008`), before `entry.restEndMs = null; setActive(w);`,
add:
```
beep([1200,800,1200,800], 0.5);
vibrate([100,80,100,80,100]);
```
Fires exactly once per expiry because `restEndMs` is nulled in the same branch immediately
after — a later tick sees `!entry.restEndMs` and returns early (`1002`) before reaching this
code again, no dedicated "already alerted" flag needed.

### Wake Lock: new module state + two lifecycle points
Alongside `let audioCtx = null;` (`246`):
```
let wakeLockSentinel = null;
async function acquireWakeLock(){
  try{
    if("wakeLock" in navigator) wakeLockSentinel = await navigator.wakeLock.request("screen");
  }catch(e){ /* unsupported or denied — timers still work, just no screen-stay-awake */ }
}
function releaseWakeLock(){
  try{ wakeLockSentinel?.release(); }catch(e){ /* no-op */ }
  wakeLockSentinel = null;
}
```
- `launchDay`: call `acquireWakeLock()` right after `restTickInterval = setInterval(...)`
  (`983`). Fire-and-forget (don't `await` — must not block the workout screen render on it).
- `finishWorkout`: call `releaseWakeLock()` — placement: as early as convenient in the
  function body, before or after the API calls, doesn't matter functionally since the
  workout is ending either way.

### `visibilitychange` / `pageshow` listeners (`1432-1435`)
Replace:
```
document.addEventListener("visibilitychange", () => {
  if(document.visibilityState === "visible" && getActive()) updateTimer();
});
window.addEventListener("pageshow", () => { if(getActive()) updateTimer(); });
```
with:
```
document.addEventListener("visibilitychange", () => {
  if(document.visibilityState === "visible" && getActive()){
    tickRestTimers();
    acquireWakeLock();
  }
});
window.addEventListener("pageshow", () => { if(getActive()) tickRestTimers(); });
```
`tickRestTimers()` internally calls `updateTimer()` (`999`), so the elapsed-time refresh
these listeners existed for is preserved; the catch-up rest-alert check comes for free from
the same call.

## 3. Edge cases the implementation must hold

- Tab hidden while a rest timer is running, comes back visible after the timer's already
  expired → `tickRestTimers()` runs immediately from the `visibilitychange` handler, sees
  `remaining <= 0`, fires the alert once — the user doesn't have to wait for the next
  (possibly throttled) 1s interval tick.
- Tab hidden and returned to *before* the timer expires → `tickRestTimers()` just refreshes
  the countdown display; no alert, no double-count against the later on-time interval tick
  (same "cleared once" guard as the normal path).
- No active workout when `visibilitychange`/`pageshow` fires → both listeners already
  early-out on `getActive()` being falsy; unchanged.
- Wake Lock unsupported (Firefox, older Safari) or denied by the OS → `acquireWakeLock`
  catches and no-ops; rest timer alerting is unaffected (it never depended on the wake lock,
  only benefits from the screen/tab staying more active).
- `finishWorkout` called with no wake lock ever acquired (unsupported browser) →
  `releaseWakeLock`'s optional chaining on `wakeLockSentinel?.release()` is a safe no-op.
- Multiple simultaneous rest timers (one per entry) expiring in the same tick → each entry's
  branch in the `forEach` fires its own `beep`/`vibrate` pair independently; overlapping Web
  Audio oscillators are expected and fine (same as today if two PR sounds could theoretically
  overlap).
- `beep()` called with no `audioCtx` yet (user hasn't triggered `primeAudio()` this session)
  → unchanged existing no-op at `507`, silently skips sound but `vibrate` still fires.

## 4. Self-test additions (existing `runSelfTest`, `1437`)

No pure-logic branch is being added that's meaningfully unit-testable without a live
`AudioContext`/`Vibration`/`WakeLock` API (all three are browser-environment side effects,
not data transforms) — self-tests here are limited to the one piece of actual logic:

1. Fixture: entry with `restEndMs = Date.now() - 1000` (already expired) passed through the
   `remaining <= 0` branch logic in isolation (extract the "is expired" check
   `Math.max(0, Math.ceil((entry.restEndMs - Date.now())/1000)) <= 0` as the thing under
   test, since `tickRestTimers` itself is DOM+state coupled) — assert it evaluates true, and
   an entry with `restEndMs = Date.now() + 5000` evaluates false. This locks in the
   self-correcting absolute-timestamp math the rest of this phase depends on, without needing
   to mock Web Audio/Vibration/Wake Lock.

## 5. Explicitly out of scope

- Backgrounded/locked-phone alerting (service worker, push notification, or OS-level
  scheduled notification) — flagged `[opus?]` in the roadmap as a future `@architect` decision
  if on-device testing shows this phase's tab-open bar isn't sufficient. Not planned or
  stubbed here.
- A user-facing mute/volume control — the existing `ponytail:` comment at `503-504` already
  covers why (iOS ringer switch already silences WebAudio; add a persisted toggle only if it
  annoys). Unchanged by this phase.
- Any change to how rest duration itself is chosen/started (`entry.restSeconds`,
  `entry.restEndMs` assignment at `1247`) — this phase only changes what happens at zero and
  how promptly zero is noticed.
