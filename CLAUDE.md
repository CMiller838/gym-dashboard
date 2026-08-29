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

## Feature lifecycle

- Plan a phase with `@planner <Phase>`: resolves open gates, writes a spec to `.claude/specs/`
  and a tracking checklist to `tasks.md`.
- Before coding, read `tasks.md` and the relevant `.claude/specs/*.md` file.
- Build with TDD (failing test first) for logic; rapid-prototype for UI.
- Mark completed items in `tasks.md` as `- [x]` once their tests pass.
- Commit (`.claude/rules/roadmap-gating.md` auto-aligns `tasks.md`/`docs/roadmap.md`).
