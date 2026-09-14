---
name: planner-invocation
description: Efficiency protocol for invoking the planner agent in phase mode (spec + tasks breakdown) — name exact files, reference one prior phase as the format model, gate genuinely important decisions (architecture, reuse-vs-build, anything contradicting the dispatch prompt's assumptions) while auto-proceeding on trivial forks, and leave discovery/scanning to planner itself rather than pre-scanning in the coordinator session. Use whenever about to invoke @planner for a phase spec.
---

## PLANNER INVOCATION EFFICIENCY PROTOCOL

`@planner` (phase mode) calls burn tokens fast because a resumed agent replays
its whole prior transcript. Follow these rules whenever invoking `planner`
for a phase spec + tasks breakdown:

### Token budget

A phase-mode `planner` call should cost **roughly 100k subagent tokens or
less**. When the agent's result reports its token spend, check it against
this budget and tell the user the actual figure — don't wait for them to
ask. A call that comes in well over 100k is a signal something above (a
missed decision gate, a full-file `tasks.md` read, a coordinator pre-scan)
went wrong, not just "planner is expensive" — say which rule likely slipped.

### Pre-flight: verify stale symptoms before dispatching

If the phase's roadmap wording describes a bug/symptom (not a net-new
feature), ask the user in your own turn — before calling `Agent` at all —
whether they're still actually observing it and what exactly they've seen.
Roadmap phases can go stale between being written and being planned (an
earlier phase's fix can silently resolve a later phase's stated bug). Finding
this out via a planner Decision Gate instead costs a full extra resumed
turn (investigate the stale bug → gate → wait for the user → re-investigate
the real one), which compounds because every resume replays the whole prior
transcript. One open question upfront is free by comparison.

1. **Do not pre-scan the codebase yourself.** `planner.md`'s own Stage 1
   already spawns a `scanner` subagent (Haiku, read-only) whenever a phase
   needs bulk file reading, and reports back only function signatures/
   existing helpers/behavior — not raw dumps. Spawning a scanner in the
   *coordinator* session first duplicates that cost: the digest lands in the
   coordinator's context via the tool result, then gets pasted again into the
   planner prompt, and planner may still re-verify parts of it anyway. Let
   planner decide for itself whether the phase warrants a scan and do that
   research on its own turn, where the digest never has to cross back through
   the coordinator's context at all.
2. **Name exact files and locations, never "read the relevant code."** Point
   at specific files, and where possible specific functions/line
   ranges/CSS selectors, directly in the `planner` prompt — this is what lets
   planner's own Stage 1 skip straight to targeted Glob/Grep or a scanner
   call instead of an open-ended sweep.
3. **Reference exactly one prior phase as the format model.** Tell `planner`
   which single phase's `.claude/specs/phaseN_spec.md` + its `tasks.md`
   section to match for depth/structure — never "look at prior phases" or
   "other phase specs."
4. **Gate important decisions, auto-proceed on trivial ones.** See the note on
   decision gates below — ask `planner` to always state its own recommendation,
   but to actually pause and wait for the user's pick on anything important
   (not just note it and move on), while still deciding trivial forks itself.
5. **Tell `planner` to touch only its own phase's slice of `tasks.md`.**
   `tasks.md` accumulates every prior phase's full checklist — instruct
   `planner` explicitly to `Grep` for `^## Phase <N>` (its own heading) and
   the next `^## Phase` heading to get its exact line range, read only that
   slice, and never read or reason about any other phase's tasks (the one
   phase named as the format model in rule 3 is the sole exception). This is
   already in `planner.md`'s own instructions, but restate it in the prompt —
   a resumed `planner` call replays its whole prior transcript, so a blind
   full-file read early on is expensive to have happened at all.

### Decision gates

Default posture: **follow the roadmap's stated approach.** The user has
already made the call on what a phase should do; planner's job is to execute
that, not to re-litigate it. Gate criteria are tiered by priority, not a flat
list — higher tiers always gate, lower tiers are a preference to note, not a
reason to halt:

- **Tier 1 — always gate:** schema/data-shape changes (anything other code
  reads depending on the shape), and a new dependency or new external
  endpoint (this project's standing rule: never add a dependency without
  confirming first). These gate regardless of how confident planner is.
- **Tier 2 — gate only if the roadmap's approach genuinely can't be
  followed, or a vastly better path has surfaced:** a finding that
  contradicts what the roadmap/dispatch prompt assumed (e.g. "the spec
  assumed X could be reused, but it can't — X doesn't exist / already
  works / is structured differently"). The bar here is "the stated approach
  is not viable as written," not "there's an alternative worth mentioning" —
  a plausible-but-not-required alternative gets a one-line note in the spec,
  not a gate.
- **Tier 3 — decide yourself, note it, never gate:** which existing
  function/surface gets reused vs. a new one being built. Prefer reuse by
  default, but this is a preference, not a risk — it doesn't rise to a
  Tier-1/2 halt on its own. If a reuse-vs-build choice turns out to *require*
  a Tier-1 change (e.g. reusing X means changing X's stored shape), it gates
  under Tier 1, not because of the reuse question itself.
- Everything else (UI/behavior choices, most "anything later phases build
  on" cases that don't contradict the roadmap's own sequencing) is trivial —
  planner decides it and notes the call in the spec. Most pure UI/behavior
  choices in a phase are one CSS rule or one function away from being
  changed later.

- Tell `planner` up front: *always state your recommendation, and always
  decide Tier 3 (reuse-vs-build) yourself with a one-line note — never gate
  on it. For Tier 1 (schema/data shape, new dependency/endpoint), always
  raise a Decision Gate and HALT regardless of confidence. For Tier 2
  (roadmap's approach doesn't hold up), gate only if the approach truly
  can't be followed as written or a genuinely better path exists — not
  merely a plausible alternative — and HALT for the user's explicit pick.
  Do not just record your own call and proceed on a Tier 1 or qualifying
  Tier 2 fork.*
- When a gate (or your own pre-flight check) hinges on whether a described
  symptom is still real, phrase it as one open question ("are you still
  seeing this, and what did you observe?") rather than a closed yes/no per
  symptom. A closed question can get a technically-answered-but-wrong reply
  that only gets corrected on the user's *next* message — which costs a full
  extra resumed turn to redirect, on top of the one it should have taken.

- If `planner` does surface gates, prefer resolving them in the **same
  message** that spawned it isn't possible after the fact — so front-load
  context (constraints, prior settled scope, what's out of bounds) into the
  first prompt so `planner` has enough to default-decide the *trivial* forks
  without needing a round trip for those.
- A pause-and-resume round costs roughly 2x the pre-pause transcript in
  tokens — this is the real price of gating more: expect phases with genuine
  architectural forks to cost more than a fully zero-pause run, in exchange
  for the user actually choosing those forks instead of inheriting planner's
  pick after the fact. If a phase is likely to have 2-3 genuine forks, it's
  still cheaper to ask `planner` to list all of them at once with its
  recommendations, get one batch answer from the user, and resume once — not
  one resume per gate.
- **Never tell `planner` it may proceed past a gate without the user's
  answer**, e.g. "don't block awaiting go-ahead," "proceed after presenting,"
  or similar. `planner.md`'s Stage 2 HALT is explicitly non-negotiable and
  says a dispatch prompt can never satisfy it on the user's behalf — but
  wording like that still gets treated by planner as license to self-resolve
  every gate, defeating the whole point of gating. If minimizing round trips
  is the goal, say so via batching (list all gates in one message, one
  resume) — never via a proceed-without-me instruction.
