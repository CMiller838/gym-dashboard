# Phase 3 — Post-workout summary (spec)

Target file: `/home/cody/~ProjectsAI/gym/index.html` (single file, no build step).
Covers must-have 8 (post-workout summary of what was achieved).

Decision gates answered (relayed via the coordinator):

- **Gate 1: Path B — tap-to-advance full-screen cards.** Three cards (Volume / PRs / Muscle
  groups), a dot indicator, "Done" on the last card. Not a single scrolling stats panel.
- **Gate 2: Path A, widened.** Keep the existing live-detection model — the summary lists
  exactly what the app celebrated mid-workout, one source of truth — but the rule itself
  becomes **two independent tracks**: heaviest weight (existing) and heaviest single-set
  volume, `weight × reps` (new). Both fire confetti/toast live; both appear in the summary.
  This is **not** a purely additive change: `logSet`'s PR check and
  `computeBestByExercise`'s return shape both change.

**Muscle groups: decided IN, not gated** — see §1.1 for the investigation and the recorded
fallback. **No new dependencies and no new files** beyond this spec and the `tasks.md`
update, per `CLAUDE.md`.

All line numbers below are **post-Phase-2** (current `index.html`).

---

## 1. Findings the implementation must be built on

### 1.1 The muscle-groups question, settled

`loadExerciseIndex` (`324-347`) stores exactly one thing per exercise (`339`):

```
items.push({ id: info.id, name });
```

No `category`, no `muscles`, no `equipment`. Grep confirms those field names appear
**nowhere** in the file. So the roadmap's premise holds: muscle data is not in the app today.

But the roadmap's cheap-exit trigger — "a slow extra fetch on every workout finish" — is
**not met**, for two reasons:

1. **The bytes are already being downloaded and thrown away.** Line `334` fetches
   `/exerciseinfo/?format=json&limit=200` through `apiAll`. wger's *exerciseinfo*
   representation is the nested one — it carries `category`, `muscles`,
   `muscles_secondary`, `equipment` and `images` alongside `translations` in the same
   response. `pickEnglishName` (`298-305`) reads `translations` and the rest is discarded.
   Keeping one more field per exercise costs **zero extra requests**.
2. **The only real cost is timing, and it is fixable off the critical path.**
   `loadExerciseIndex` has exactly one call site — `openAddExercise` (`1016`) — so the cache
   is frequently cold when a workout finishes. The fix is a fire-and-forget warm-up at
   *workout start*, not at finish (see §2.5): the index loads during the 45 minutes of actual
   lifting. It also makes the exercise picker instant, which is a free side win.

**Decision: muscle groups stay in.** Implemented as a cache-schema bump to
`exercise_index_v2` holding `{ id, name, cat }`, warmed at workout start, read
**synchronously** at summary time. The summary never awaits a fetch.

**Recorded fallback, in priority order** (the builder resolves this on the first real fetch,
and records the answer in the `tasks.md` phase notes):

- `info.category.name` present → use it. wger's categories (Chest, Back, Legs, Arms,
  Shoulders, Abs, Calves) are exactly the "muscle groups" granularity must-have 8 wants.
- `info.category` absent but `info.muscles[]` present → fall back to the muscle `name` list.
  Coarser labels are preferred, so only do this if `category` genuinely isn't there.
- **Neither present → drop the muscle card.** The summary becomes two cards, the dot
  indicator adapts (§2.7), and the reason is recorded in the phase notes. This is the
  roadmap's cheap exit and it stays available; it is just not the expected outcome.

Deliberately **not** storing `muscles` / `muscles_secondary` / `equipment`: `cat` is one
short string per exercise, the finer anatomical names ("Pectoralis major") are worse labels
for this screen, and the index is ~1400 entries in `localStorage`. `ponytail:` comment the
category-granularity ceiling; upgrade to per-muscle only if the card proves too coarse.

### 1.2 Total volume: genuinely new, but needs no API call

Grep confirms no volume/tonnage computation exists anywhere in the file. It does not need
one either: `finishWorkout` (`1188`) still holds the full active workout in memory via
`getActive()`, and every logged set already carries its own `weight` and `reps` locally
(`logSet` `1150-1153`). The totals are a reduce over `w.entries`, **zero network**.

Critical ordering constraint: `finishWorkout` calls `clearActive()` at `1202`. The summary
must be built from `w` **before** that line, not after.

### 1.3 PR detection today, and what the two-track rule changes

`computeBestByExercise` (`675-683`) returns `{ [exerciseId]: heaviestWeightEver }` — a bare
number per exercise, weight only. It has exactly **two** call sites, `789` (`launchDay`) and
`811` (`renderActiveWorkout` migration). `renderPRs` (`602-635`) does **not** use it — it
builds its own separate `{weight, reps, date}` map inline. So the return shape is free to
change without touching the PRs tab.

`logSet` (`1156-1160`):

```
const prevBest = w.sessionBest[entry.exerciseId];
const isPR = (prevBest !== undefined) && weightVal > prevBest;
if(prevBest === undefined || weightVal > prevBest){
  w.sessionBest[entry.exerciseId] = weightVal;
}
```

Two behaviours here are deliberate and must survive the widening:

- **An exercise never logged before is not a PR** (`prevBest === undefined` → `isPR` false),
  but it still seeds the baseline. There is nothing to beat on your first attempt.
- `computeBestByExercise` skips `weight <= 0` (`679`), so bodyweight/unweighted work never
  registers a PR. Single-set volume is `weight × reps`, so the same guard excludes it from
  the volume track for free — no second guard needed.

**The migration hazard.** `sessionBest`'s value type changes from `number` to
`{w, v}`. Line `811` guards with `if(!w.sessionBest)`, which is falsy-only — a workout
already in progress at upgrade time would keep its old number-valued map and the new code
would read `prev.w` off a number, yielding `undefined` and silently disabling PR detection
for that workout. **Do not add a shape sniff.** Rename the field to `w.best` instead: the
`if(!w.best)` guard then re-derives naturally for any pre-upgrade workout, and the stale
`sessionBest` key is simply ignored. Rename is the same edit count as a shape check and
removes the hazard entirely.

Known ceiling to `ponytail:` comment at `811`: re-deriving from `allLogsCache` mid-workout
folds *this session's own* already-POSTed sets into the "best ever" baseline, so a workout
in flight across the upgrade loses its remaining PR detection. One-time, self-healing on the
next workout, not worth code.

### 1.4 The toast is weight-shaped and must be generalised

`showPRToast(name, weight, prevBest)` (`1093-1103`) hardcodes the weight framing:

```
🏆 New PR! <span class="prsub">${esc(name)} — ${weight}kg${prevBest ? ` (was ${prevBest}kg)` : ""}</span>
```

A volume PR needs `90kg × 10 = 900kg (was 850kg)`, which this signature cannot express.
`triggerSetFeedback` (`1108-1119`) passes `prevBest` straight through (`1113`). Both
signatures change in §2.4. `esc(name)` stays — `entry.name` is API-derived.

### 1.5 Screen routing: the summary does not need a `render()` guard

Phase 2 established `render()`'s guard (`478-481`) and the `showMain` flag (`228`). The
summary is simpler than that and must **not** add a third flag to `render()`:
`renderSummary()` paints the header, `content` and toolbar itself, and the markup it writes
contains **no** tabs, no back button and no discard button. Nothing on the summary screen can
reach `setTab` (`431`) or `render()`. So the only exit is the Done button, and no guard is
needed. Do not add `summary` to the `render()` guard — it buys nothing and adds a state
another screen has to reason about.

---

## 2. Target design

All work is inside `index.html`. Roughly ~120 lines added, ~5 changed in place.

### 2.1 Changed: `computeBestByExercise` (two tracks, one pass)

```
computeBestByExercise(logs) -> { [exerciseId]: { w: number, v: number } }
                              // w = heaviest single-set weight ever logged
                              // v = heaviest single-set VOLUME (weight × reps) ever logged
                              // Same loop, same `weight <= 0 -> continue` guard (679).
                              // Reps read defensively: parseFloat(l.repetitions ?? l.reps ?? 0)
                              //   — logSet POSTs `repetitions` (1145); older wger used `reps`.
                              // w and v are tracked INDEPENDENTLY: the heaviest-weight set
                              //   and the highest-volume set are usually different sets.
```

Call sites to update: `789` (`sessionBest:` → `best:`) and `811` (`w.sessionBest` →
`w.best`, per §1.3).

### 2.2 New pure helpers (these are what make §3's TDD possible)

Both are pure — no DOM, no network, no `getActive()` — specifically so `runSelfTest` can
cover the branch logic. This is the only new indirection in the phase; everything else is
inline.

```
classifySetPR(prev, weight, reps) -> { weightPR: boolean, volumePR: boolean }
                              // prev: the { w, v } record for this exercise, or undefined.
                              // undefined prev        -> { false, false }   (first-ever, §1.3)
                              // weight > prev.w       -> weightPR true
                              // weight*reps > prev.v  -> volumePR true
                              // Tracks are independent; both, either or neither may be true.
                              // Strictly greater: equalling a best is not a PR.

summaryTotals(entries) -> { sets: number, reps: number, volume: number }
                              // Reduce over entries[].sets, counting ONLY s.logged === true.
                              // volume += (+s.weight || 0) * (+s.reps || 0)
                              // Blank/NaN weight or reps contribute 0, never NaN.
```

### 2.3 Changed: `logSet`'s PR check (`1156-1160`)

Replaces the block quoted in §1.3:

```
const prev = w.best[entry.exerciseId];
const pr = classifySetPR(prev, weightVal, repsVal);
const isPR = pr.weightPR || pr.volumePR;
// seed/raise both tracks independently, including the first-ever case
w.best[entry.exerciseId] = {
  w: Math.max(weightVal, prev ? prev.w : 0),
  v: Math.max(weightVal * repsVal, prev ? prev.v : 0)
};
if(isPR) recordPR(w, entry, weightVal, repsVal, prev, pr);
```

`isPR` still drives `triggerSetFeedback` at `1164`, so a set that is a volume PR but not a
weight PR **does** get the full confetti/vibrate/flourish treatment — that was the explicit
requirement.

`w.best` is mutated on the live object; the existing `setActive(w)` call in `logSet` already
persists it. Do not add a second write.

### 2.4 New: `recordPR`, and the generalised toast

```
recordPR(w, entry, weight, reps, prev, pr) -> void
                              // Upserts into w.prs (array), ONE record per exerciseId:
                              //   { exerciseId, name, weightPR: null | {weight, reps, prev},
                              //                       volumePR: null | {weight, reps, volume, prev} }
                              // Finds the existing record for entry.exerciseId or pushes a new one,
                              // then overwrites ONLY the track(s) that fired this set.
                              // Per-track storage is required: hitting a weight PR on set 1
                              // (100kg×3) and a volume PR on set 3 (90kg×10) must not let the
                              // later set overwrite the weight figure and claim a 90kg weight PR.
                              // Later hits on the same track strictly beat earlier ones (w.best
                              // was already raised), so a plain overwrite is correct.
```

`w.prs` is initialised to `[]` in `launchDay` (§2.5) and defaulted with `w.prs || []` at
every read site, so a workout already in flight at upgrade time degrades to an empty PR list
rather than throwing.

Toast signature changes (`1093`, and its one call site `1113`):

```
showPRToast(name, label, detail) -> void
                              // 🏆 {label}! <span class="prsub">{esc(name)} — {detail}</span>
                              // label:  "Weight PR" | "Volume PR" | "Weight + Volume PR"
                              // detail: caller-built from numbers only, e.g.
                              //           weight: "100kg (was 95kg)"
                              //           volume: "90kg × 10 = 900kg (was 850kg)"
                              // `name` stays behind esc() (§1.4). `detail` contains no
                              // API-derived strings — keep it that way.
```

`triggerSetFeedback(isPR, x, y, name, weight, prevBest)` (`1108`) → its trailing two params
become `(…, name, label, detail)`; the non-PR branch (`1114-1118`) is untouched.

**UI naming decision (mine, per the coordinator's instruction):** the two kinds are labelled
**"Weight PR"** and **"Volume PR"** everywhere they surface — toast, summary card, and any
badge. A set hitting both reads **"Weight + Volume PR"** in the toast and shows two badges in
the summary. No other synonyms ("tonnage", "1RM", "new best") anywhere in the UI.

### 2.5 Changed: `launchDay` and the index warm-up

| Site | Line | Change |
| --- | --- | --- |
| `launchDay` active-workout literal | `789` | `sessionBest: computeBestByExercise(logs)` → `best: computeBestByExercise(logs)` |
| `launchDay` active-workout literal | `~790` | add `prs: []` |
| `launchDay`, after `setActive` | `~791` | add `loadExerciseIndex().catch(() => {});` — fire-and-forget, **not awaited**. Warms `exercise_index_v2` during the workout so the muscle card is available at finish (§1.1). A failure here must never affect starting a workout. |
| `renderActiveWorkout` | `811` | `if(!w.best) w.best = computeBestByExercise(allLogsCache \|\| []);` + the `ponytail:` ceiling comment from §1.3 |

### 2.6 Changed: the exercise index cache (`v1` → `v2`)

| Site | Line | Change |
| --- | --- | --- |
| `EXINDEX_KEY` | `210` | `"exercise_index_v1"` → `"exercise_index_v2"` |
| `loadExerciseIndex` rebuild | `339` | `items.push({ id: info.id, name })` → `items.push({ id: info.id, name, cat: (info.category && info.category.name) \|\| "" })` |
| `loadExerciseIndex` rebuild | `~344` | add `localStorage.removeItem("exercise_index_v1")` beside the `setItem`, so the superseded blob doesn't sit in storage forever |
| new, near `loadExerciseIndex` | — | `exerciseCatMap()` (below) |

```
exerciseCatMap() -> { [exerciseId]: string } | null
                              // SYNCHRONOUS. Never fetches. Returns null if no index is
                              // available, which is the signal to drop the muscle card.
                              // Source order: the in-memory `exerciseIndex` (223) if set,
                              // else JSON.parse(localStorage[EXINDEX_KEY]) inside try/catch.
                              // TTL is deliberately NOT checked here — a week-old category
                              // label is still correct, and re-fetching is not an option on
                              // this path. Entries with an empty `cat` are omitted.
```

The picker is unaffected: `items.filter(x => x.name…)` (`1024`) and `items.find(x => x.id === id)`
(`1030`) ignore the extra field. The schema bump does force one re-pagination for existing
users — a cost they already pay weekly at `EXINDEX_TTL_MS` (`211`), and now on a background
path rather than in front of the picker.

### 2.7 New: the summary screen (Gate 1, Path B)

Module-level state beside `showMain` (`228`). Neither is persisted — a reload during the
summary lands on the main screen, which is correct: the workout is already saved to wger by
then and the summary is a celebration, not data.

```
let summary = null;           // { durationMin, totals: {sets,reps,volume}, prs: [], muscles: [] }
let summaryCard = 0;          // index into the visible card list
```

```
buildSummary(w) -> object     // Pure-ish (reads only w + exerciseCatMap()). Called BEFORE
                              // clearActive() (§1.2). Produces:
                              //   durationMin: Math.max(0, Math.floor((Date.now()-w.startedAtMs)/60000))
                              //                — same arithmetic as updateTimer/renderToolbar (443)
                              //   totals:      summaryTotals(w.entries)
                              //   prs:         w.prs || []
                              //   muscles:     [{ cat, sets }] desc by sets, or [] if
                              //                exerciseCatMap() is null / no entry resolves.
                              //                Tally: for each entry with >=1 logged set, add
                              //                its logged-set count to that exercise's category.

renderSummary() -> void       // Paints the whole screen for summaryCard. Owns the header,
                              // #content and #mainToolbar, exactly as renderActiveWorkout does.
                              //   - #mainToolbar.style.display = "none"   (as 814)
                              //   - renderMainHeader() (433) to restore a clean "🏋️ Gym Log"
                              //     header — the workout header's back/discard buttons must
                              //     NOT survive onto this screen
                              //   - #content.innerHTML = the active card + dot row + button

nextSummaryCard() -> void     // summaryCard++; last card -> closeSummary(); else renderSummary()

closeSummary() -> void        // summary = null; summaryCard = 0; render();
```

**Card list is built, not hardcoded to three.** Volume and PRs always render; the muscle card
is appended only when `summary.muscles.length > 0`. The dot row renders one dot per card in
the built list, so the two-card case (§1.1 fallback, or a cold index) is not a visual bug.

Card contents:

| Card | Shows |
| --- | --- |
| Volume | `{totals.volume}kg` as the hero figure, with `{totals.sets} sets · {totals.reps} reps · {durationMin} min` beneath |
| PRs | One row per `prs[]` record: exercise name + a "Weight PR" and/or "Volume PR" badge + the figures. Empty `prs` → an explicit "No PRs this time — still counts." line, **not** a blank card |
| Muscle groups | One row per `muscles[]` entry: `{cat} — {sets} sets`, sorted descending |

The whole screen is tap-to-advance: the card container carries the `onclick`, and the final
card's button reads "Done". `summaryCard` is clamped so a double-tap on the last card cannot
index past the end.

**Escaping (`CLAUDE.md` invariant):** every exercise `name` (from `w.prs[].name`, which
originates in `buildEntriesFromDay` `710-727` from wger) and every `cat` (straight from
`/exerciseinfo/`) goes through `esc()` (`349-357`). Numbers do not need it and should not get
it. This is a brand-new `innerHTML` render path, so it is exactly the case the invariant
exists for.

CSS: new `.summary-card`, `.summary-hero`, `.summary-sub`, `.summary-dots`/`.summary-dots .dot`,
`.pr-badge` rules next to the existing `.pr-card` block. Reuse the `--accent` token (`17-21`).
Keep it plain — Phase 4's design pass owns the real styling and will restyle this screen; do
not invest in polish here beyond legibility and a 44px Done button.

### 2.8 Changed: `finishWorkout` (the Phase 2 hook point)

Current tail (`1202-1207`): `clearActive()` → interval cleanup → `activeTab = "history"` →
`render()`.

```
const s = buildSummary(w);          // BEFORE clearActive() — §1.2
clearActive();
… existing interval / finishBar cleanup, unchanged …
activeTab = "history";
if(s.totals.sets === 0){ render(); return; }   // nothing logged: no summary, straight to main
summary = s; summaryCard = 0; renderSummary();  // replaces the render() at 1207
```

The `apiPatch` failure branch (`1197-1199`, the `alert`) is untouched — a failed `time_end`
patch must still show the summary, since the sets themselves are safe and that is what the
summary reports.

### 2.9 Edge cases the implementation must hold

- **Zero logged sets** → no summary at all (§2.8). Note the existing confirm at `1192`
  already tells the user how many sets they logged.
- **Cold exercise index at finish** (first-ever workout, or storage cleared) →
  `exerciseCatMap()` returns `null`, `muscles` is `[]`, two cards render, no fetch, no stall.
- **Exercise present in the workout but missing from the index** (added since the last index
  build) → omitted from the muscle tally only. It still counts in volume and PRs.
- **Bodyweight / zero-weight sets** → contribute 0 volume and can never register on either PR
  track (`679` guard, §1.3). Correct, and consistent with the PRs tab today.
- **Blank or `NaN` weight/reps on an unlogged set** → excluded by the `s.logged` filter in
  `summaryTotals`; the `|| 0` coercions are belt-and-braces.
- **Pre-upgrade workout in flight** → `w.best` re-derived at `811`, `w.prs` defaults to `[]`,
  summary shows volume and muscle groups with an empty PR card. Degrades, doesn't throw.
- **Same exercise hitting the same track twice** → `recordPR` overwrites that track; the later
  hit strictly beats the earlier one because `w.best` was already raised.
- **One set hitting both tracks** → one `w.prs` record with both sub-objects populated, two
  badges, one toast reading "Weight + Volume PR".
- **Reload / PWA relaunch while the summary is up** → `summary` resets to `null`, user lands
  on the main screen. Intended; add a comment so it doesn't read like a bug.
- **`durationMin` across midnight** → inherits Phase 1's recorded cross-midnight ceiling
  (phase1 spec §2.4). `startedAtMs` is a real timestamp so the summary's own figure is
  correct; it is wger's stored `time_end` that can't represent it. Nothing to do here.
- **Very long exercise names on a PR row** → ellipsis, same treatment as `.resumebtn`
  (phase2 spec §2.3). Do not truncate in JS.
- **Unit assumption:** the app hardcodes `kg` (`renderPRs` `632`, `showPRToast` `1096`) and
  ignores wger's `weight_unit`. The summary follows suit. `ponytail:` comment the ceiling;
  add unit handling only if a lb user actually appears.

### 2.10 Explicitly out of scope (record, don't fix)

- **Rep PRs** (more reps at a weight already hit) and **estimated 1RM** — Gate 2 chose two
  tracks, not four. If wanted later, they belong in `docs/FUTURE.md`.
- **Re-opening a past workout's summary from the History tab.** The summary is built from
  in-memory active-workout state; reconstructing it from wger logs is a different feature.
  YAGNI.
- **Sharing / screenshot / image export** of the summary.
- **Animating the card transitions** — Phase 4's design pass owns motion.
- **Changing `renderPRs` (`602-635`)** to show volume PRs. It has its own independent
  computation (§1.3) and is not in this phase's exit condition. Leave it alone; note the
  inconsistency in the phase notes so Phase 4 or a later pass can reconcile the two.
- **Storing `muscles` / `equipment` in the index** (§1.1).
- **A service worker / offline cache** for the exercise index — there is no service worker in
  this app by design (`ARCHITECTURE.md`).

---

## 3. Checks

### 3.1 Automated — add to the existing `runSelfTest()` (`1246-1313`, `#selftest`)

Same pattern as cases 1-7: one `assert(cond, label)` per claim, sharing the existing
`checks`/`failed` counters (`1247`) and the single closing
`console.log(\`selftest: ${checks} checks, ${failed} failed\`)` (`1312`). Inline literal
fixtures. No network, no DOM, no framework.

```
Case 8: computeBestByExercise returns two independent tracks.
  Fixture where the heaviest-weight set is NOT the highest-volume set
  (e.g. 100kg×2 = 200 vs 60kg×10 = 600) → asserts w === 100 AND v === 600.
  Asserts weight <= 0 logs are skipped entirely.
  Asserts a fixture using `repetitions` and one using `reps` both compute v.

Case 9: classifySetPR branch table.
  undefined prev              -> { weightPR:false, volumePR:false }   (first-ever)
  heavier weight, lower vol   -> weight only
  same weight, more reps      -> volume only
  heavier weight AND more reps-> both
  equalling prev.w exactly    -> weightPR false (strictly greater)
  lower on both               -> neither

Case 10: summaryTotals over a mixed entries fixture.
  Counts only s.logged === true; ignores unlogged rows entirely.
  A logged set with weight "" contributes 0 volume and does NOT produce NaN.
  sets / reps / volume all correct against a hand-computed fixture.

Case 11: recordPR upsert, per-track.
  Same exerciseId hit on the weight track then the volume track produces ONE record
  with BOTH sub-objects populated and the weight figures NOT overwritten by the later
  volume set (the §2.4 hazard).
```

Do not add assertions over `renderSummary`, `buildSummary`, `exerciseCatMap`,
`showPRToast` or `loadExerciseIndex` — they need the DOM, `localStorage` or the live API.
Cases 1-7 must still pass.

### 3.2 Manual — real device / real API

- Finish a workout with logged sets → the summary appears **before** the main screen, showing
  a plausible total volume; cross-check the figure by hand against two or three logged sets.
- Tap through: Volume → PRs → Muscle groups → Done → lands on the History tab with the
  finished session listed, toolbar showing Refresh / Change token again.
- Dot indicator matches the number of cards actually present.
- Finish a workout with **zero** sets logged → no summary, straight to the main screen.
- Beat a previous weight → confetti + a toast reading **"Weight PR"**, and that exercise
  appears on the summary's PR card with a Weight PR badge.
- Beat a previous single-set volume **without** beating the weight (e.g. same weight, more
  reps) → confetti + a toast reading **"Volume PR"**, and it appears with a Volume PR badge.
  This is the new behaviour and the main thing to verify.
- One set that beats both → a single toast reading "Weight + Volume PR" and a single summary
  row with two badges.
- An exercise logged for the **first time ever** → no PR, no confetti (§1.3), but it still
  counts toward volume and muscle groups.
- Muscle card names real categories (Chest / Back / Legs …) matching the exercises actually
  performed, with sensible set counts.
- **Confirm and record in the phase notes** whether `/exerciseinfo/` returns
  `category.name` — check one real response, then note it (§1.1). If it does not, apply the
  documented fallback and record which one.
- Start a workout on a fresh install (cold index) → workout start is not slowed by the
  warm-up fetch; finishing shortly after still shows volume and PR cards without a stall.
- Summary is legible and the Done button is comfortably tappable at 360px **and** 320px
  viewport width.
