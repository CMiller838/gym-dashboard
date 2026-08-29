# CLAUDE.md

Guidance for Claude Code in this repo.

## Project state

<!-- One paragraph: what's built, what phase you're in, where the history lives
(git log, a docs/ file) so this file doesn't need to repeat it. -->

- `docs/roadmap.md` is the single active roadmap file — superseded versions live in
  `.claude/archive/`. Never create a new versioned roadmap file — always overwrite
  `docs/roadmap.md` in place; archive its prior content first if fully superseded.
- **Before every commit, mark the roadmap.** Any commit that finishes a roadmap phase
  must, in that same commit, append `— done` to the phase heading and record what was
  verified. Enforcement: `.claude/rules/roadmap-gating.md`.

## Commands

```
<!-- fill in: run dev server, run tests, install deps -->
```

No lint/build/formatter beyond what's listed — don't invent one unless asked.

## Stack

<!-- Language, framework, DB, key native/vendored dependencies, deployment shape.
Note anything that can't be reconstructed from the repo (vendored binaries, one-time
data imports) and where to re-fetch it from. -->

- **Never add a new dependency without confirming with the user first.**

## Architecture invariants

<!-- The 3-8 things that would silently break if someone "cleaned up" the code
without knowing why: a store-raw-not-derived rule, a boundary a component must never
cross, a special case a well-meaning refactor would delete. This is the highest-value
section — keep it short, keep it non-obvious. -->

## Project lifecycle (start to v2)

1. **`idea-interview` skill** — before any feature list exists. Interviews to a
   project outline (in README or a standalone outline doc), actively pushes back
   on scope creep to keep must-haves to an actual MVP, parks everything else into
   `docs/FUTURE.md` with a revisit trigger.
2. **`@architect`** — reads the outline (primary) and `docs/FUTURE.md` (secondary,
   don't architect for parked ideas), picks a stack, writes `docs/ARCHITECTURE.md`.
3. **`@planner` roadmap mode** — reads the outline's must-have list, groups it into
   phases (as few as the dependency ordering allows), writes `docs/roadmap.md`.
4. **Per phase, repeat until the roadmap is done:**
   - **`@planner Phase N`** — decision-gated interview, then writes
     `.claude/specs/phaseN_spec.md` and the phase's tasks in `tasks.md`. Planner
     also does the "is there an existing library for this" check at plan time —
     the build step below shouldn't need to re-research it.
   - **Build** — TDD (failing test first) for logic files, rapid-prototype for UI
     (`ui-prototyper` in build mode for assigned UI tasks; in manual-testing
     ideation mode, ideas only — it must not edit files you're mid-test against).
     Keep it ponytail-lazy: the smallest working diff, no speculative abstraction.
   - **`/code-review` or `/simplify`** on the phase's diff before committing —
     TDD proves the tests you wrote pass, not that you didn't over-build around
     them; this catches both correctness bugs and creep.
   - Mark `tasks.md` items `- [x]` once their tests pass, commit
     (`.claude/rules/roadmap-gating.md` auto-aligns `tasks.md`/`docs/roadmap.md`
     in the same commit).
5. **`project-retro` skill** — once every phase is done. Reviews shipped state
   against the outline, interviews for changes/additions, files them into
   `docs/FUTURE.md`, flags (but doesn't itself trigger) a stack revisit via
   `@architect` if real friction came up.
6. **v2** — manually re-run the chain: `idea-interview` (seeded from the retro's
   `docs/FUTURE.md` entries) → `@architect` (only if the retro flagged a stack
   concern) → `@planner` roadmap mode → step 4's per-phase loop again.
