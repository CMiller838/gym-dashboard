# CLAUDE.md

Guidance for Claude Code in this repo.

## Project state

Gym Log — a Hevy-style frontend skin over the wger workout API (wger.de), for logging
and viewing workouts on mobile. Single-page PWA, no build step, deployed as a static
site on GitHub Pages. App code (`index.html`, `manifest.json`, icons) is imported from
`CMiller838/gym-dashboard`, where the full commit history of the app itself lives —
this repo's own `git log` only covers the Claude Code setup layered on top. See
`docs/ARCHITECTURE.md` for how the single file is organized internally (state, API
layer, render functions, PWA install flow).

## Commands

```
# No install/build. Open index.html directly, or serve statically for realistic PWA testing:
python3 -m http.server 8000
```

No lint/build/formatter — it's a single HTML file with inline JS/CSS.

## Stack

- Vanilla HTML/CSS/JS, single file (`index.html`), no framework, no bundler, no package.json.
- Backend is entirely wger's public API (`https://wger.de/api/v2`) — this repo has no
  server of its own.
- Auth: user pastes their own wger API token, stored in `localStorage` (plaintext,
  client-only — see security note below).
- PWA: `manifest.json` + icons for home-screen install (iOS/Android); no service worker.
- Deployment: GitHub Pages, served directly from this repo's root.
- **Never add a new dependency without confirming with the user first.**

## Architecture invariants

- **No backend, and none should appear casually.** All state lives in wger's API; the
  token in `localStorage` is a known, accepted trade-off (see comment above `TOKEN_KEY`
  in `index.html`) — don't "fix" it with a proxy/backend without discussing it first,
  that's a real architecture change.
- **All API-derived strings must be escaped before `innerHTML` injection** — a stored
  XSS hole here was already fixed once (`dba16df`); any new render path that injects
  wger data (exercise names, notes, etc.) must escape it the same way.
- **wger's public search endpoints are unreliable** — exercise lookup goes through
  `/exerciseinfo/` pagination (`apiAll`), not a direct search call. Don't "simplify"
  this back to a search endpoint.
- **Duplicate-session guard**: starting a routine checks for an existing unfinished
  session for that routine/day before creating a new one (wger allows concurrent
  sessions from other clients, e.g. the wger mobile app) — don't remove this check.
- Everything is one file (`index.html`) by design — this is a dashboard skin, not an
  app; don't split it into a build pipeline unless it actually grows enough to need one.

## Project lifecycle (start to v2)

Full detail, including exactly what each step reads/writes and why: `WORKFLOW.md`.
Short version: `idea-interview` (MVP outline + FUTURE.md) → `@architect` (stack →
ARCHITECTURE.md) → `@planner` roadmap mode (phases) → per phase: `@planner Phase N`
(spec + tasks.md) → build (TDD + ponytail; UI via `ui-prototyper` →
`restyle-from-prototype`) → `/code-review` or `/simplify` → commit → repeat until the
roadmap is done → `project-retro` → v2 repeats the chain, seeded from the retro.
