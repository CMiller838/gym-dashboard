# Phase 2 — Active workout: keep it, get back to it, make the tap feel right (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-haves 4 (persistent bar), 3 (routing back to main), 2 (sound), 6 (tick target).

Decision gates answered (relayed via the coordinator):

- **Gate 1: Path A — minimal.** In-memory `showMain` flag, a back button in the workout
  header, the bottom bar *replaces* the toolbar's buttons while a workout is active, and the
  dead resume-banner code is deleted. A reload mid-workout lands back on the workout screen.
- **Gate 2: Path A — enlarge and separate.** Tick goes to 44×40; the row-delete ✕ moves out
  from under it into the set-number cell.
- **Gate 3: Path A — always-on two-tier WebAudio beep.** No mute toggle, no audio asset.

**No new dependencies and no new files** beyond this spec and the `tasks.md` update — the beep
is a WebAudio oscillator, per `CLAUDE.md`'s "never add a new dependency without confirming".

All line numbers below are **post-Phase-1** (current `index.html`). The roadmap's numbers have
drifted by ~7-15 lines; use these.

---

## 1. Findings the implementation must be built on

### 1.1 Confirmed: the resume banner is unreachable, and there is no way to leave a workout

`render()` (`439-442`) opens with:

```
const active = getActive();
if(active){ renderActiveWorkout(); return; }
```

Every main-screen renderer (`renderHistory` 495, `renderPRs` 563, `renderRoutines` 598) is only
reached *past* that guard, i.e. only when there is no active workout. They all prefix their
markup with `resumeBannerHtml()` (`429-437`), which returns `""` whenever `getActive()` is
null — so **the resume banner has never once been visible**. Phase 1's `#resumeMins` span
(`434`) is wired into markup that never renders.

`renderActiveWorkout` (`769`) offers only the ✕ discard button (`780`). There is no back, and
`setTab` (`427`) → `render()` bounces straight back into the workout.

So must-have 4 is not "add a bar alongside the banner" — it is "make leaving the workout
possible at all", which requires a view-state flag in `render()`. The bar is then the only
resume affordance and the banner is deleted.

Also note, since it is being deleted: `resumeBannerHtml` interpolates `${w.dayName}`
**unescaped** (`434`). `dayName` is API-derived (`launchDay` 747: `day.name || structure.name`).
It is an unreachable stored-XSS hole today; the replacement bar must use `esc()`, per the
`CLAUDE.md` invariant.

### 1.2 Confirmed root cause: the routing dead-end is a destroyed header element

`renderActiveWorkout` overwrites the entire header (`775`):

```
document.getElementById("topHeader").innerHTML = `…<div class="wname">…</div>…`;
```

That destroys `<div class="sub" id="headerSub">` (`192`). Nothing ever restores it. Then
`render()` at `447` does:

```
document.getElementById("headerSub").textContent = "syncing…";
```

`headerSub` is `null`, and line `447` sits **outside** the `try` (which starts at `450`), so
`render()` throws `TypeError` and dies before painting anything. The user is left staring at
the dead workout screen. That is must-have 3's dead-end, and it is a single shared bug:

- `finishWorkout` (`1144-1163`) already does the right thing — `clearActive()`, `activeTab =
  "history"`, `render()` — and still dead-ends.
- `discardWorkout` (`1166-1195`) calls `render()` and dead-ends the same way.
- The new back button would dead-end too.

**Fix it once, in `render()`**, not three times at the call sites.

Same bug, second symptom: the header keeps `class="topbar"` when the workout markup is written
into it, so the entire `.workout-header` CSS block (`104-109`) — sticky flex row, `.wname`,
`.wtimer`, `.discardbtn` — has never applied. The class swap belongs in the same fix.

### 1.3 Confirmed: the tick's neighbour makes a bigger tick worse, not better

`.logbtn` is 30×24 (`145-146`), with `.delbtn` 30×18 (`148`) stacked 3px below it inside
`.rowbtns` (`144`), in a 34px-wide `.actioncell` (`143`). `removeSetRow` (`907-928`) only
confirms when the set is **logged** (`916`) — an unlogged row is deleted with no confirmation.
Growing the tick downward into that gap trades a missed tap for a destructive one, hence
Gate 2 Path A.

### 1.4 Sound: WebAudio, with one real constraint

`triggerSetFeedback` (`1067-1076`) already has the two-tier structure (`vibrate` 1029-1031) to
hang sound off. The constraint: the beep fires at the *end* of `logSet` (`1120`), after
`await apiPost` (`1097`). An `AudioContext` created or resumed after an `await` is outside the
user-gesture task and stays `suspended` on iOS. It must be created/resumed **synchronously in
`logSet`'s prefix, before the first `await`**.

### 1.5 Free win: the bar's timer stays live with no extra code

`restTickInterval` (`864-865`, 1 Hz) is started by `renderActiveWorkout` and cleared only by
`finishWorkout`/`discardWorkout`. Backing out to the main screen does **not** clear it, so
`tickRestTimers` (`878-895`) keeps calling `updateTimer()` (`881`), which repaints `#resumeMins`
(`874-875`). Moving that span into the bar means the bar's minute count self-updates.
**Do not add a clear-on-back.** `tickRestTimers`' `rest_*` lookups already no-op behind
`if(box)` guards when the workout DOM is absent.

---

## 2. Target design

All work is inside `index.html`. Roughly: ~50 lines added, ~15 deleted.

### 2.1 New state and functions

```
let showMain = false;              // module-level, beside `activeTab` (222). NOT persisted.
                                   // true = user backed out of an active workout to browse.

renderMainHeader() -> void         // Idempotent. Restores <header id="topHeader"> to
                                   // className "topbar" and the main-screen markup
                                   // (<h1>🏋️ Gym Log</h1> + <div class="sub" id="headerSub">),
                                   // guaranteeing #headerSub exists for its callers.

renderToolbar() -> void            // Paints #mainToolbar for the current state and shows it:
                                   //   getActive() -> single full-width resume button:
                                   //     "▶ {esc(dayName)} · <span id="resumeMins">N</span> min"
                                   //     onclick -> renderActiveWorkout()
                                   //   otherwise  -> the existing Refresh / Change token buttons

backToMain() -> void               // showMain = true; render();

primeAudio() -> void               // Lazily creates `audioCtx` (AudioContext ||
                                   // webkitAudioContext) and calls resume(). try/catch, no-op
                                   // on failure. MUST be called synchronously inside a user
                                   // gesture (see 2.4).

beep(freqs) -> void                // freqs: number[] of Hz, played in sequence ~70ms apart.
                                   // try/catch, no-op if audioCtx is null/unusable.
```

`let audioCtx = null;` beside the other module-level state.

### 2.2 Navigation and header ownership (Gate 1A + must-have 3)

| Site | Line | Change |
| --- | --- | --- |
| state | ~222 | add `let showMain = false;` and `let audioCtx = null;` |
| `render()` | 441-442 | `if(active && !showMain){ renderActiveWorkout(); return; }` |
| `render()` | before 446 | call `renderMainHeader()` **first**, then `renderToolbar()`; drop the direct `mainToolbar.style.display = "flex"` (446) — `renderToolbar` owns that |
| `render()` | 464-465 | unchanged: `#headerSub` is now guaranteed to exist |
| `showSetup()` | 387-388 | call `renderMainHeader()` then `renderToolbar()` in place of the direct `display = "flex"`; same null-`headerSub` exposure |
| `renderActiveWorkout()` | 770-781 | set `showMain = false` at the top (any entry into the workout screen cancels the flag); set `topHeader.className = "workout-header"`; add a back button as the first child of the header |
| `renderActiveWorkout()` | 774 | keep `mainToolbar.style.display = "none"` — the finish bar owns the bottom here |
| `finishWorkout` / `discardWorkout` | 1163, 1194 | unchanged — the fixed `render()` now lands them on the main screen |

Workout header markup (`775-781`) becomes three flex children so `.workout-header`'s
`justify-content:space-between` puts back left, title centre-left, discard right:

```
<button class="backbtn" onclick="backToMain()">‹</button>
<div class="wtitle"><div class="wname">{esc(dayName)}</div><div class="wtimer" id="wtimer">0 min</div></div>
<button class="discardbtn" onclick="discardWorkout()">✕</button>
```

`esc(w.dayName)` is already applied at `777` — keep it.

### 2.3 The persistent bar (Gate 1A, must-have 4)

`#mainToolbar` (`196-199`) stays the single fixed bottom element; `renderToolbar()` rewrites
its contents. Its active-workout form is one full-width button:

- label: `▶ ` + `esc(w.dayName)` + ` · <span id="resumeMins">` + minutes + `</span> min`
- minutes computed exactly as `updateTimer` does: `Math.max(0, Math.floor((Date.now() - w.startedAtMs)/60000))`
- `onclick="renderActiveWorkout()"`

Deletions:

- `resumeBannerHtml()` (`429-437`) — delete the function.
- Its **nine** call sites, each `resumeBannerHtml() + tabsHtml()` → `tabsHtml()`:
  `448`, `489`, `498`, `516`, `566`, `580`, `587`, `601`, `604`.
- `.resume-banner` CSS block (`38-43`) — delete.

`updateTimer` (`868-876`) is **unchanged**: it already paints `#wtimer` if present and
`#resumeMins` if present, and no-ops otherwise. The span simply lives in the bar now.

CSS to add next to `.toolbar` (`97-101`):

```
.toolbar .resumebtn{flex:1; background:var(--accent); color:#fff; border:none;
  border-radius:12px; padding:14px 16px; font-weight:800; font-size:14px;
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis;}
```

`padding:14px` on a 14px font gives a ~46px-tall target, and the ellipsis rule stops a long
`dayName` ("Push Day A — Upper Hypertrophy") wrapping the bar to three lines.

### 2.4 Sound (Gate 3A, must-have 2)

Placed beside `vibrate()` (`1029-1031`), same defensive shape — never let audio break logging.

- `primeAudio()` is called as the **first statement of `logSet`** (`1079`), before any `await`.
  It is also harmless to call on every tap (creates once, `resume()` is idempotent).
- `beep(freqs)`: for each frequency, one `OscillatorNode` (`type:"triangle"`) → one `GainNode`
  → `destination`, scheduled at `audioCtx.currentTime + i*0.07`, note length ~0.07s. Envelope:
  gain `0.0001` → `0.25` over ~5ms (`linearRampToValueAtTime`), then
  `exponentialRampToValueAtTime(0.0001)` over the note — the ramp is what stops the click at
  note edges. `osc.stop()` at note end; nodes are collected automatically after stopping.
- `triggerSetFeedback` (`1067-1076`) gains one line per branch, mirroring the vibrate tiers:
  - normal set: `beep([880])`
  - PR: `beep([880, 1175, 1568])` (rising A5–D6–G6)

`triangle` over `sine` (audible over gym noise) and over `square` (harsh at 880Hz). Volume
0.25 is deliberate: this plays through a phone speaker held at arm's length.

Add a `ponytail:` comment recording the known ceiling: **no mute toggle** — on iOS the ringer
switch silences WebAudio, on Android it does not; add a persisted toggle only if it annoys.

### 2.5 Tap targets (Gate 2A, must-have 6)

CSS changes:

| Selector | Line | From | To |
| --- | --- | --- | --- |
| `.setrow .logbtn` | 145-146 | `width:30px; height:24px; border-radius:7px; font-size:13px` | `width:44px; height:40px; border-radius:10px; font-size:16px` |
| `.setrow .actioncell` | 143 | `width:34px` | `width:50px` |
| `.setrow .setnum` | 138 | `width:22px` | `width:44px; white-space:nowrap` |
| `.setrow .delbtn` | 148 | `width:30px; height:18px` | `width:26px; height:26px; margin-left:2px; vertical-align:middle` |
| `.setrow .prevcell` | 139 | `font-size:12px` | `font-size:11px; white-space:nowrap` |
| `.settable td` | 137 | `padding:4px` | `padding:3px 2px` |
| `.workout-header .discardbtn` | 109 | `padding:4px 8px` | add `min-width:44px; height:44px` |
| `.workout-header .backbtn` | new | — | `background:none; border:none; color:var(--text); font-size:26px; line-height:1; min-width:44px; height:44px; padding:0;` |
| `.workout-header .wtitle` | new | — | `flex:1; min-width:0;` |

Markup changes in `renderActiveWorkout` — **both** the logged (`793-802`) and unlogged
(`806-815`) row branches:

- `.rowbtns` wrapper (`144` CSS, `798`/`811` markup) is removed; `<td class="actioncell">`
  contains only the `.logbtn`.
- `<td class="setnum">` becomes `${si+1}` **plus** the delete button:
  `<td class="setnum">${si+1}<button class="delbtn" onclick="removeSetRow(${idx},${si})">✕</button></td>`
- Delete the now-unused `.setrow .actioncell .rowbtns` rule (`144`).

Width budget — the table is `width:100%` with five columns. At 360px viewport (16px page
padding each side, 16px card margin, 16px card padding → ~264px of table): setnum 44 +
prevcell ~52 + actioncell 50 = 146, leaving ~118px split across the two number inputs (~59px
each). That fits a 3-digit weight at `font-size:14px`. **This is tight and must be checked
visually at 360px and 320px** — see the manual checklist. If 320px overflows, the cheap lever
is shortening the Previous string from `50kg×5` to `50×5` in `prevStr` (`791`); the column
header already says "Previous". Do that before touching the input font size.

### 2.6 Edge cases the implementation must hold

- Workout finished/discarded from another client while `showMain` is true → `getActive()` is
  null, `render()` takes the normal main path, `renderToolbar()` repaints Refresh / Change
  token. No stale resume bar.
- Tapping the resume bar → `renderActiveWorkout()` sets `showMain = false` and hides the
  toolbar; back → `backToMain()` shows it again. No third state.
- `setTab` (`427`) while `showMain` is true → stays on the main screen (flag persists across
  tab switches). Correct and intended.
- Reload / PWA relaunch while `showMain` is true → flag resets to `false`, user lands in the
  workout. Intended per Gate 1A; record it in a comment so it doesn't read like a bug.
- `startWorkout` (`691-692`) with a workout already active → `renderActiveWorkout()`, which
  clears `showMain`. Unchanged.
- `resetToken()` (`410-418`) clears `ACTIVE_KEY` and reloads — unaffected.
- Long `dayName` → ellipsis (2.3). Empty/missing `dayName` → falls back to `structure.name` at
  creation time (`747`); the bar must still render if it is somehow empty (button reads
  "▶ · N min", ugly but not broken — do not add a placeholder).
- `AudioContext` unavailable / blocked → `primeAudio` and `beep` swallow it; vibration and
  confetti still fire and the set still logs.
- `render()`'s stale-generation guard (`459`, `484`) is untouched — `renderMainHeader()` and
  `renderToolbar()` run before the network call, so a superseded render cannot repaint chrome
  over a fresher one.

### 2.7 Explicitly out of scope (record, don't fix)

- Persisting the minimized state across reloads (Gate 1A rejected it).
- A mute toggle (Gate 3A rejected it) — `ponytail:` comment only.
- `.movebtn` (26×22, `117`), `.removeexbtn` (`122`) and `.addsetbtn` tap sizes — Phase 4's
  design pass owns those; only the tick is in the exit condition.
- Swipe-to-delete or any gesture layer on set rows.
- **Hook for Phase 3:** the post-workout summary replaces `render()` at the end of
  `finishWorkout` (`1163`). Leave that call site clean and obvious; do not pre-build a summary
  screen here.

---

## 3. Checks

### 3.1 Automated — add to the existing `runSelfTest()` (`1202`, `#selftest`)

The Phase 2 surface is DOM and audio, so there is exactly one thing worth a runnable check:
the regression from 1.2, which is cheap to assert and is the bug that caused the dead-end.

```
Case 7: header restore.
  Set topHeader.innerHTML to arbitrary workout-ish markup and className to "workout-header"
  (simulating renderActiveWorkout), call renderMainHeader(), then assert:
    - document.getElementById("headerSub") is not null
    - document.getElementById("topHeader").className === "topbar"
  Then call renderMainHeader() a second time and assert both again (idempotence).
```

No network, no `getActive()`, no timers. Keep the existing closing
`console.log("selftest: N checks, M failed")` summary. Do not add assertions over `beep`,
`renderToolbar` or `render` — they need audio hardware or the live API.

### 3.2 Manual — real device / real API

- Start a workout → back "‹" → main screen renders fully (tabs, stats, history) with **no
  console error**, and the bottom bar names the in-progress routine.
- The bar's minute count increments while sitting on the main screen (proves 1.5).
- Tap the bar → returns to the workout with all logged sets and rest timers intact.
- Switch tabs (History / PRs / Routines) while backed out → stays on the main screen, bar
  persists on all three.
- Finish a workout → lands on the History tab, header reads "🏋️ Gym Log" + session count,
  toolbar shows Refresh / Change token again.
- Discard a workout → same, no dead-end.
- Every set tap plays the blip; a PR plays the rising three-note flourish plus the existing
  confetti/toast. Sound works on the **first** tap of a fresh page load (the iOS gesture
  constraint in 1.4).
- Tick button is comfortable with a thumb; ✕ next to the set number is not hit by accident.
- Set rows do not overflow horizontally at 360px **and** 320px viewport width, with a 3-digit
  weight (e.g. `100`) and 2-digit reps entered.
