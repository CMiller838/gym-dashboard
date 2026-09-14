# Phase 1 — Louder timer audio

Target file: `index.html` (single-file app, no build step, no new dependencies).

Goal (from `docs/roadmap.md`): raise rest-timer audio output further so it cuts through
music during a set; verify on-device against real playback, not just quiet-room testing.

Out of scope: mute toggle, volume slider/UI, service-worker/background audio (that's
Phase 2's "Background/locked-phone timer alerts"), any change to when/why `beep()` is
called (call-site trigger logic untouched).

## 0. What investigation found (from dispatch, no re-scan needed)

- `let audioCtx = null;` — index.html:345.
- `primeAudio()` — index.html:656 — creates/resumes the `AudioContext` on first user
  interaction (required for iOS autoplay policy).
- `beep(freqs, gain = 0.32)` — index.html:665-681 — builds one oscillator per
  frequency in `freqs`, `osc.type = "triangle"` (672), gain envelope
  `gainNode.gain.linearRampToValueAtTime(gain, t0+0.005)` then exponential decay to
  `t0+0.07`, `osc.connect(gainNode).connect(audioCtx.destination)` — no compressor in
  the chain today.
- `ponytail:` comment at index.html:663 — deliberate no-mute-toggle constraint (iOS
  ringer switch silences WebAudio, Android doesn't). Stands unchanged.
- Call sites: index.html:1269 `beep([1200,800,1200,800], 0.5)` (loudest — timer
  expiry), index.html:1470 `beep([880,1175,1568])` (default gain), index.html:1475
  `beep([880])` (default gain), index.html:1481 `primeAudio()`.
- Current loudest call already passes gain 0.5, near the envelope's practical clipping
  ceiling on a single oscillator; raw amplitude alone is exhausted as a lever. Multiple
  simultaneous oscillators (the 3-tone confirmation chord) can still sum past 0dBFS and
  clip without a limiter.

## 1. Decisions (Tier 3 — decided here, not gated)

- **Waveform: `triangle` → `square` for all `beep()` oscillators.** Square wave's
  stronger odd-harmonic content reads as louder/sharper against a music mix than a
  gain bump on a triangle wave, for the same peak amplitude. One-line change, applies
  uniformly to every call site since they all route through `beep()`.
- **Modest default gain increase: `gain = 0.32` → `gain = 0.4`.** Kept conservative
  because square-wave harmonics already buy most of the perceived loudness gain;
  pushing raw gain further is what the compressor exists to make safe, not what should
  carry the whole improvement.
- **Loud call site gain increase: `0.5` → `0.65`** (index.html:1269, timer-expiry
  beep — the one that most needs to cut through music). Left as an explicit argument
  at the call site, unchanged pattern.
- **Add one shared `DynamicsCompressorNode`, created once, not per-beep.** Created
  alongside `audioCtx` in `primeAudio()` (same lifecycle — both live only once the
  context exists) and connected once: `compressorNode.connect(audioCtx.destination)`.
  New module-level `let compressorNode = null;` declared next to `audioCtx` at
  index.html:345. `beep()`'s chain becomes
  `osc.connect(gainNode).connect(compressorNode)` instead of connecting straight to
  `audioCtx.destination` — this is the "safety net" the roadmap calls for when the
  3-tone chord's oscillators sum. No new dependency: `DynamicsCompressorNode` is a
  native WebAudio API node.
- **Compressor settings — brick-wall-ish limiter, not a musical compressor:**
  `threshold = -6`, `knee = 0`, `ratio = 20`, `attack = 0.003`, `release = 0.1`. Fast
  attack/high ratio/zero knee catches summed-oscillator peaks before they clip, without
  audibly "pumping" a two-tone beep. These are one-time constants set right after the
  node is created in `primeAudio()`.
- **Reuse `beep()`/`primeAudio()` in place — no new functions.** The change is
  entirely: two constant tweaks, one waveform string, one new node wired into an
  existing chain. Doesn't warrant new abstractions.

## 2. Changes

### `let audioCtx = null;` (index.html:345)

Add sibling declaration: `let compressorNode = null;`.

### `primeAudio()` (index.html:656)

After `audioCtx` is created/resumed, if `compressorNode` is not yet created: create a
`DynamicsCompressorNode`, set the five params above, connect it to
`audioCtx.destination`, assign to module-level `compressorNode`.

### `beep(freqs, gain = 0.32)` (index.html:665-681)

- Signature default: `gain = 0.32` → `gain = 0.4`.
- `osc.type = "triangle"` → `osc.type = "square"`.
- Connection: `osc.connect(gainNode).connect(audioCtx.destination)` →
  `osc.connect(gainNode).connect(compressorNode)`.

### Call site index.html:1269

`beep([1200,800,1200,800], 0.5)` → `beep([1200,800,1200,800], 0.65)`.

Other call sites (1470, 1475, 1481) unchanged — they already rely on the (now raised)
default gain.

## 3. Edge cases

- `beep()` called before `primeAudio()` has ever run (shouldn't happen given existing
  call-site ordering, but if `compressorNode` is still `null`): guard identically to
  how `audioCtx` is already assumed non-null at these call sites — no new guard needed
  beyond what exists today, since `compressorNode` is created in the same place and at
  the same time as `audioCtx`.
- Multiple overlapping `beep()` calls in quick succession (e.g. rapid re-triggers)
  share the single `compressorNode` — this is intentional and is exactly the scenario
  the compressor protects against.
- Square wave at higher gain (0.4/0.65) plus compressor limiting: verify the confirm
  chord (`[880,1175,1568]`) doesn't sound distorted/harsh on-device — this is a
  judgment call only a real-device listen can confirm, not something to unit-test.

## 4. Manual on-device verification (no automated test — this is audio perception)

- [ ] Load the app on a phone (not desktop quiet-room), play music/video at a normal
      volume, trigger the rest-timer expiry beep — confirm it's clearly audible over
      the music, louder than before the change.
- [ ] Trigger the 3-tone confirm chord (`[880,1175,1568]`) same conditions — confirm no
      audible clipping/distortion now that gain rose and compressor was added.
- [ ] Trigger both beeps back-to-back rapidly — confirm no harsh clipping from
      overlapping oscillator sums (the case the compressor exists for).
- [ ] Confirm `ponytail:` no-mute-toggle behavior is unaffected (iOS ringer switch
      still silences it, Android still doesn't) — no code path here should touch that.

## 5. Explicitly out of scope

- Mute/volume UI — not requested, contradicts the deliberate no-toggle constraint.
- Any change to *when* beeps fire (call-site trigger conditions) — untouched.
- Background/locked-screen audio delivery — that's Phase 2.
