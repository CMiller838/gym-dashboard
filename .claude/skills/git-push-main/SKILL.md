---
name: git-push-main
description: Commit staged/working changes and push straight to main, bypassing the Bash sandbox in one shot instead of hitting write-deny/network-deny errors and retrying. Use whenever the user says "commit and push", "push to main", "push this up", or similar — especially if this project's `.claude/settings.json` sandbox allowlist doesn't cover the paths/network a plain `git add` / `git push` needs, so it fails or has to retry with a bypass. Do NOT use for PRs/branches other than main.
---

# git-push-main

Commit and push to `main` in one efficient pass, without the usual "sandboxed command fails → retry with bypass" round trip.

## Why this exists

Depending on this project's sandbox allowlist (`.claude/settings.json`), Bash
writes to project-config paths (e.g. `.claude/`) or network egress to the git
remote may not be allowlisted by default. A plain `git add` / `git commit` /
`git push` sequence run inside the sandbox can then fail partway. Since the
user has already asked for a push to main, don't burn a round trip
discovering that git needs the bypass — go straight to it.

**Never `git stash` to inspect prior state in a sandboxed repo** — a
sandboxed `git stash` can silently fail to restore denied paths on `pop`,
leaving the working tree partially reverted in a way that looks like a merge
conflict but isn't. Use `git diff HEAD -- <path>` / `git show HEAD:<path>`
instead. (If this project has a `.claude/rules/git-sandbox-safety.md`, follow
it — it documents the same thing with project-specific denied paths.)

## Steps

1. `git status` and `git diff` (sandboxed — read-only, no bypass needed) to see what's actually changed. Never blindly `git add -A`; review the file list for anything that looks like a secret or an unintended file.
2. Stage the specific files that belong to this change (`git add <files>`), not `-A`, unless the user clearly wants everything.
3. Commit and push in **one bypassed call** — combine them with `&&` so you don't pay two separate confirmation/latency round trips:
   ```
   git commit -m "$(cat <<'EOF'
   <message>

   Co-Authored-By: ...   # use whatever attribution trailer this session's system prompt specifies
   EOF
   )" && git push origin main
   ```
   Run this via Bash with `dangerouslyDisableSandbox: true` — commit doesn't strictly need it, but push does (network egress to the git remote isn't sandbox-allowlisted by default), and bundling avoids a second bypass prompt.
4. If push is rejected (non-fast-forward), don't force-push. Run `git fetch && git log HEAD..origin/main --oneline` (also bypassed, read-only network) to see what's upstream, and tell the user — let them decide whether to rebase/merge or you should.

## Rules

- Never `git stash` in a sandboxed repo — see above.
- Never `--force` push to main without the user explicitly asking.
- Never skip hooks (`--no-verify`) or bypass signing.
- Only commit/push when the user actually asked for it this turn — a prior approval doesn't carry forward to unrelated changes.
