# Architecture

Gym Log is a single-file, backend-less PWA that skins wger's public workout API
(`https://wger.de/api/v2`) for mobile logging/viewing. This doc describes what's
actually in `index.html` — see `CLAUDE.md` for the standing rules that follow from it.

## Stack and why

- **Vanilla HTML/CSS/JS, one file, no build step.** The whole app is a dashboard over
  someone else's API — a bundler/framework would add tooling for no real benefit at
  this size. Deploys as a static site straight to GitHub Pages.
- **No backend.** wger already exposes everything the app needs (routines, sessions,
  logs, exercise info) over a token-authenticated REST API. Adding a server would only
  exist to hold the token more safely — see the trade-off below — and that's not worth
  a real architecture change unless the trade-off actually bites.
- **No dependencies.** Fetch, DOM APIs, and localStorage cover everything used.

## Data flow

```
localStorage (wger_api_token)
        │
        ▼
apiRaw/apiAll  ──Authorization: Token──►  wger API (wger.de/api/v2)
        │                                        │
        ▼                                        ▼
render() reads live API data            routine/session/log/exerciseinfo
        │                                  JSON responses
        ▼
content.innerHTML = ...  (all API strings passed through esc() first)
```

There is no local database and no derived state store: every render pulls what it
needs from wger (with a couple of narrow caches noted below), then throws the DOM
markup away and rebuilds it on the next render. `renderGeneration` is bumped on every
`render()` call so a slow, stale fetch can't overwrite a newer render's output.

## Storage (all `localStorage`, all client-only)

| Key | Holds | Why |
|---|---|---|
| `wger_api_token` | the user's wger API token, plaintext | only place to keep it in a backend-less app — see security note |
| `active_workout` | in-progress workout session state | survives a page reload mid-workout |
| `exercise_name_cache` | id → name lookups | avoids re-resolving names already seen this session |
| `exercise_index_v1` | full exercise list + timestamp | wger's exercise list is slow/paginated; cached for `EXINDEX_TTL_MS` (1 week) so the exercise picker doesn't repaginate every time it opens |

## Key internal boundaries

- **API layer** (`apiRaw`/`api`/`apiPost`/`apiPatch`/`apiDelete`/`apiAll`) — the only
  code that touches `fetch`. `apiRaw` attaches the auth header and timeout
  (`fetchWithTimeout`, `REQUEST_TIMEOUT_MS`) and normalizes 401/403 into an `"auth"`
  error the UI can catch and bounce to the token screen. `apiAll` walks wger's
  pagination (`next` links) since some endpoints (exercise info in particular) only
  work reliably via full pagination, not a search param — see invariant in `CLAUDE.md`.
- **Render layer** (`render`, `renderHistory`, `renderPRs`, `renderRoutines`,
  `renderActiveWorkout`, ...) — each owns one tab/screen, fetches what it needs (or
  reads `allLogsCache`), builds an HTML string, and assigns it to
  `content.innerHTML`. Every API-derived value going into these strings is passed
  through `esc()` first — this is the fix for the stored-XSS issue in `dba16df`, and
  the boundary any new render path must respect.
- **Active-workout state machine** (`getActive`/`setActive`/`clearActive`, backed by
  `active_workout`) — a workout in progress is plain JSON in localStorage, not wger
  state, so the UI can resume it after a reload before anything is POSTed to wger.
  Starting a routine first checks wger for an existing unfinished session for that
  routine/day (duplicate-session guard, see `CLAUDE.md`) since wger allows concurrent
  clients (e.g. the official mobile app) to create sessions of their own.
- **PWA shell** (`manifest.json` + icons) — install-to-homescreen metadata only; no
  service worker, so there's no offline cache or background sync to reason about.

## Security note (accepted trade-off)

The API token lives in plaintext in `localStorage`, readable by any script running on
this origin. That's acceptable *only* because the app has no other scripts or
third-party CDNs on the page — see the comment above `TOKEN_KEY` in `index.html`. If
the app ever needs third-party JS or dynamic HTML from a source other than wger, this
storage choice must be revisited first (e.g. a small backend proxying wger with
short-lived session cookies) — that's a real architecture change, not a tweak, and
needs sign-off before it happens.

## Source of truth for the app's own history

This repo's `git log` only covers the Claude Code setup (`.claude/`, `CLAUDE.md`,
`WORKFLOW.md`) layered on top. The app files (`index.html`, `manifest.json`, icons)
are imported from `CMiller838/gym-dashboard` — that repo has the actual commit history
of the app (feature work, the XSS fix referenced above, etc.).
