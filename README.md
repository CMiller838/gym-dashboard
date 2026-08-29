# generic-claude-setup

A portable starting point for a Claude Code project setup, extracted from the
Ai_Chess_assist project's `.claude/` + `CLAUDE.md`, with the chess-specific parts
stripped out or replaced with `<!-- TEMPLATE -->` placeholders.

## Use it

```
cp -r generic-claude-setup/.claude generic-claude-setup/CLAUDE.md /path/to/new-project/
chmod +x /path/to/new-project/.claude/hooks/*.sh
```

Then fill in every `<!-- TEMPLATE -->` / `TEMPLATE:` marker in `CLAUDE.md`,
`.claude/agents/architect.md`, `.claude/agents/ui-prototyper.md`, and
`.claude/hooks/auto-lint.sh`.

## What's in here and why

- `CLAUDE.md` — skeleton with the sections worth having on day one: project state,
  commands, stack, architecture invariants (the highest-value section — the things a
  well-meaning refactor would break), feature lifecycle.
- `.claude/agents/` — `architect` (opus; design review, and — new — the one that
  picks the stack and writes `docs/ARCHITECTURE.md` at project start, reading the
  outline from `idea-interview` as primary input), `code-reviewer` (sonnet,
  confidence-gated so it doesn't manufacture nitpicks), `scanner` (haiku, cheap
  rote lookups — route boilerplate search here instead of burning opus/sonnet
  tokens), `planner` (opus, decision-gated spec writer — see workflow below),
  `ui-prototyper` (sonnet; generates and iterates standalone UI mockups with
  fake data in a prototypes directory — never edits the real app. During a
  manual test pass it can view the actually-running app via a browser MCP —
  see Browser MCP setup below — and turn what it sees into a new prototype
  variant, still without touching the files you're testing).
- `.claude/rules/` — `agent-resume.md` (never spawn a fresh agent to continue work
  an existing one started; `SendMessage` it instead) and `roadmap-gating.md` (a
  commit that finishes a roadmap phase must update the roadmap/checklist in the
  *same* commit — keeps docs from drifting out of sync with what's actually done).
- `.claude/hooks/` — `block-dangerous.sh` (denies `git push --force` to
  main/master), `auto-lint.sh` (template: syntax-check + run the paired test
  right after an edit — fill in the language check and the file→test mapping).
- `.claude/settings.json` / `settings.local.json` — sandbox allowlist stub, a
  starter permissions allow/deny/ask list, and the hook wiring above.
- `.claude/skills/` — copied verbatim, already project-agnostic:
  `search-first` (research existing tools/patterns before writing custom code),
  `strategic-compact` (suggests manual compaction at phase boundaries instead of
  arbitrary auto-compact), `task-observer` (watches for reusable-skill-worthy
  patterns during a session), `verification-loop` (verify work before claiming
  done), `audit-claude-md` (keeps CLAUDE.md terse — run it periodically),
  `excalidraw-diagram`.
- `.claude/skills/idea-interview/` — run this *before* `planner`, at the very
  start of a project when there's no feature list yet. Multi-round interview
  (problem, users, must-haves vs. nice-to-haves, constraints, non-goals) that
  writes a project outline (into README.md or a standalone file, whichever
  fits) and parks deferred ideas into `docs/FUTURE.md` with a revisit trigger.
  Actively resists scope creep — see its Step 2a: it challenges every proposed
  must-have ("does this block a usable v1?") rather than recording whatever
  list you're excited about, since most people over-scope an MVP. Re-invoke it
  later to fold in one new idea without repeating the full interview. Feeds
  `planner`'s roadmap mode once it's done.
- `.claude/skills/project-retro/` — run once every phase in a roadmap is done.
  Compares what shipped against the original outline, interviews you on what
  to change/add/remove, files findings into `docs/FUTURE.md` (tagged by which
  retro they came from, so the next `idea-interview` pass has a ready-made
  starting point), and asks a stack-health question — if real friction comes
  up, it tells you to run `@architect` yourself rather than triggering it.
- `.claude/skills/restyle-from-prototype/` — the other half of `ui-prototyper`.
  Once you've picked a mockup from the prototypes directory, this applies its
  design language (palette, spacing, layout patterns) to the real app's
  templates/components and stylesheet, carrying every real data binding and
  event/selector dependency across so the restyle doesn't silently break
  interactivity. `disable-model-invocation: true` — invoke it explicitly by
  name, since "restyle this" is ambiguous without a chosen prototype in hand.

## Browser MCP setup (optional, for ui-prototyper's manual-testing mode)

To let `ui-prototyper` actually see the running app during a manual test pass
instead of working from your description alone, add a browser automation MCP
server once per machine or per project:

```
claude mcp add playwright -- npx -y @playwright/mcp@latest
```

Then `/mcp` to confirm it's connected. `ui-prototyper`'s instructions already
check for tools prefixed `mcp__playwright__` (or similar) and use them when
present, and degrade gracefully — working from your verbal description — when
they're not. Nothing else in this template requires this; it's purely for
grounding prototype ideas in the real, running UI.

## Not included (write these fresh per project)

- **`tdd-workflow` skill** — the original's trigger description hardcodes this
  project's file names (`blunders.py`, `engine.py`, ...). Copy its *shape*
  (require a failing test before touching core logic files, name the actual
  files/patterns that count as "core logic" here) rather than its content.
- **`restart-server` / `run-server` / `stop-server` skills** — trivial once you
  know your dev server's actual start command; not worth templating.
- **`.claude/specs/`, `docs/roadmap.md`, `tasks.md`** — these are *outputs* of
  the `planner` agent's workflow, not something to seed ahead of time.
- **The prototypes directory itself** (e.g. `design-prototypes/ui-concepts/`)
  — `ui-prototyper` creates it on first use; nothing to seed ahead of time.

## Full project lifecycle

```
idea-interview                    (MVP outline + docs/FUTURE.md)
      ↓
@architect                        (stack choice → docs/ARCHITECTURE.md)
      ↓
@planner  (roadmap mode)          (must-haves → docs/roadmap.md phases)
      ↓
┌──> @planner  (phase mode)       (spec + tasks.md for one phase)
│         ↓
│    build: TDD (logic) + ponytail (lazy diffs)
│    UI: ui-prototyper (generate mockups) → you pick one → restyle-from-prototype
│         ↓
│    /code-review or /simplify on the diff, then commit
│         ↓
└──  repeat until docs/roadmap.md is fully done
      ↓
project-retro                     (review shipped vs. outline → docs/FUTURE.md)
      ↓
v2: idea-interview (seeded from retro) → @architect (only if flagged) → repeat
```

Skip `idea-interview` at the very start if you already walk in with a clear,
already-scoped feature list — it exists to force scoping when you don't.

## The planner workflow (worth understanding, not just copying)

`@planner <Phase>` runs a 3-stage lifecycle: silent codebase discovery (delegates
bulk file-reading to `scanner` to save opus tokens), an options-first interview
that HALTs until you answer any open architectural decision gate, then writes a
spec to `.claude/specs/` and a checklist to `tasks.md`. It has a separate
"roadmap mode" for naming/sequencing phases without designing them yet. Read
`.claude/agents/planner.md` before your first `@planner` call — it's opinionated
about not skipping the halt even if you tell it to.
