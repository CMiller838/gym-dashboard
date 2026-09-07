#!/usr/bin/env bash
# Enforces .claude/rules/agent-resume.md: before spawning a fresh Agent, a
# ListAgents check must have happened recently. A command hook can't read the
# transcript, so this approximates it with a timestamp marker file touched by
# the ListAgents matcher below and checked by the Agent matcher.
set -euo pipefail

MARKER="${CLAUDE_PROJECT_DIR}/.claude/.cc-writes/last-list-agents-ts"
mkdir -p "$(dirname "$MARKER")"

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
NOW="$(date +%s)"

if [ "$TOOL_NAME" = "ListAgents" ]; then
  echo "$NOW" > "$MARKER"
  echo '{}'
  exit 0
fi

if [ "$TOOL_NAME" = "Agent" ]; then
  THRESHOLD=180
  if [ -f "$MARKER" ]; then
    LAST="$(cat "$MARKER")"
    AGE=$(( NOW - LAST ))
  else
    AGE=999999
  fi

  if [ "$AGE" -gt "$THRESHOLD" ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Per .claude/rules/agent-resume.md: call ListAgents first to check for a live or completed agent already doing this work, then SendMessage to resume it instead of spawning fresh. If ListAgents confirms no relevant agent exists, retry this Agent call immediately after (the check is valid for 180s)."
  }
}
EOF
    exit 0
  fi
  echo '{}'
  exit 0
fi

echo '{}'
