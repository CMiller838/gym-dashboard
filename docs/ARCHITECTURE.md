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
  (ADR 001 below proposes a narrowly-scoped exception to this.)

## Security note (accepted trade-off)

The API token lives in plaintext in `localStorage`, readable by any script running on
this origin. That's acceptable *only* because the app has no other scripts or
third-party CDNs on the page — see the comment above `TOKEN_KEY` in `index.html`. If
the app ever needs third-party JS or dynamic HTML from a source other than wger, this
storage choice must be revisited first (e.g. a small backend proxying wger with
short-lived session cookies) — that's a real architecture change, not a tweak, and
needs sign-off before it happens.

## ADR 001 — Background/locked-phone rest-timer alerts (v4 must-have 2)

**Status:** Accepted. User confirmed 2026-09-12: accept the iOS ceiling (foreground-only alerts) rather than reopen the no-backend invariant.

### Context

The rest timer is a `restEndMs` timestamp on each active-workout entry, polled by a
1s `setInterval` (`tickRestTimers`) that runs *in the page*. When it hits zero it calls
`beep()` + `vibrate()`. That only works while the page is alive and visible; when the
app is backgrounded or the phone is locked, the page is throttled or suspended and
nothing fires. v4 wants an OS notification (and vibration) in that case,
local-device-only, no backend.

Three platform facts drive the whole decision:

1. **The `new Notification()` constructor is not usable on mobile.** Android Chrome
   throws on it outright; iOS Safari doesn't implement it. Mobile notifications can only
   be raised via `serviceWorkerRegistration.showNotification()`. **A service worker is
   therefore mandatory for any version of this feature** — there is no no-SW path.
2. **There is no local scheduled-notification API on the web.** The Notification
   Triggers API (`TimestampTrigger`) never shipped past origin trial and is gone. A
   `setTimeout` *inside* a service worker is worthless — SWs are killed after ~30s idle
   and are only woken by an external event (push, sync), never by their own pending
   timer. So the timer has to stay in the page, and the page has to still be running
   when it fires.
3. **`navigator.vibrate` does not exist on iOS Safari, at all.** The existing
   `vibrate()` calls are already silent no-ops on iPhone. On iOS the *only* way to get
   a haptic/sound alert is a delivered notification (the OS vibrates it). On Android,
   `vibrate` also won't run from a backgrounded page — but a notification's `vibrate`
   option in `showNotification()` does fire.

### Options considered

| Option | Needs | Android Chrome (installed PWA) | iOS Safari (home-screen PWA) |
|---|---|---|---|
| **A. Page `setTimeout` → SW `showNotification()`** | SW (notification only) | Works. A single long timeout in a hidden page fires near-on-time; Chrome's intensive throttling/freezing starts ~5 min after backgrounding, and rest timers are 30–300s | **Does not work.** WebKit suspends the web process on background/lock; the timeout fires only when you reopen the app |
| **B. Web Push** | SW **+ a push server** | Works, incl. locked | Works (iOS 16.4+, installed PWA only), incl. locked |
| **C. Notification Triggers** (`showTrigger`) | SW | Not available — never shipped | Not available |
| **D. Keep the page alive with looping silent audio** | SW still needed to notify | Prevents freezing | Keeps the process alive, but seizes the audio session |
| **E. Screen Wake Lock only** (already in the app) | nothing new | Prevents auto-lock while foregrounded; does nothing once the user switches apps or presses lock | same |

**B is excluded by the fixed constraints** — it's the only thing that fully solves iOS,
and it requires a backend (push service, VAPID keys, stored subscriptions, something
sending the message). That is the honest trade: *iOS background notifications are not
achievable without a server.* No amount of SW cleverness changes that.

**D is rejected on its own merits**, not just laziness: it pauses/ducks the user's
music, which directly contradicts v4 must-have 1 ("audible over music"), and burns
battery for a whole session, with a permanent playing-audio indicator in the OS. Worse
product than the problem it fixes.

### Decision

**Adopt Option A.** Add a minimal service worker whose only job is to exist so
`registration.showNotification()` can be called. The timer stays where it is, in the
page. On `visibilitychange → hidden` with a live `restEndMs`, arm a `setTimeout` for
the remaining time that calls `showNotification()` (with a `vibrate` pattern and a
stable `tag` so repeats replace rather than stack); on `visibilitychange → visible`,
clear it and let the existing foreground `beep`/`vibrate` path alert as it does today.
Guard against a late fire: if the timeout runs after the page was resumed, or
`Date.now()` is already well past `restEndMs`, drop it — a notification for a rest that
ended ten minutes ago is noise.

Permission is requested lazily from a real user gesture (an "Enable background alerts"
tap, not on page load), because iOS *only* grants it from a gesture inside an installed
PWA, and an unprompted permission dialog on first open is bad manners on both platforms.

### Consequences

- **Android Chrome: the feature works** as asked — locked screen, backgrounded app,
  notification with vibration, for rest periods under ~5 minutes. Beyond ~5 minutes
  hidden, Chrome's freezing makes it best-effort. Acceptable; rest timers are short.
- **iOS: the feature does not work while locked/backgrounded, and cannot be made to
  without a backend.** The implementation degrades safely (notification suppressed
  rather than fired late), and iOS keeps what it already has: foreground alert plus
  Screen Wake Lock holding the screen on during a workout. **This is the open question
  for the user** — if the daily driver is an iPhone, most of must-have 2's value is
  unreachable under the no-backend constraint, and the choice is to accept the
  limitation or to reopen the no-backend invariant (a separate decision, not this one).
- Vibration on iOS remains impossible regardless of this decision; don't spend effort
  there.
- No new dependency, no build step, no backend. The SW is one small static file served
  from the repo root.

### Scope containment (the part that matters)

Adding a service worker is *additive only* under this decision, and only stays additive
if these hold. Treat them as standing invariants alongside the ones in `CLAUDE.md`:

- **No `fetch` event handler in the service worker.** This is the important one. The
  moment the SW intercepts `fetch` it becomes a cache, and a cached `index.html` on
  GitHub Pages pins users to a stale build with no obvious way out — an offline story
  this app has never had and doesn't need against a live remote API.
- **No `push` handler, no `pushManager.subscribe()`.** That's the server-push door; it
  stays shut per the no-backend invariant.
- **No Background Sync / Periodic Background Sync.** Both imply a server relationship
  the app doesn't have; periodic sync is Chrome-only anyway.
- The SW file is, essentially, install/activate skip-waiting plus a `notificationclick`
  handler that focuses the app. Growth past that is an architecture change and needs
  sign-off, same as adding a dependency.

### Alternatives if the iOS ceiling is unacceptable

Only one exists: a small push backend (Option B). That reopens the "no backend"
invariant *and* the `localStorage` token trade-off recorded above, since a server in the
picture changes what the safest token story looks like. Not recommended unless the iOS
gap is genuinely blocking daily use.

## Source of truth for the app's own history

This repo's `git log` only covers the Claude Code setup (`.claude/`, `CLAUDE.md`,
`WORKFLOW.md`) layered on top. The app files (`index.html`, `manifest.json`, icons)
are imported from `CMiller838/gym-dashboard` — that repo has the actual commit history
of the app (feature work, the XSS fix referenced above, etc.).
