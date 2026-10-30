#!/bin/bash
# PreToolUse hook for Bash: blocks destructive commands deterministically.
# Exit code 2 = blocking error; the message on stderr is shown to Claude.
# (Exit code 1 would NOT block.)

COMMAND=$(jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -Eq 'rm +-[a-zA-Z]*r[a-zA-Z]*f|rm +-[a-zA-Z]*f[a-zA-Z]*r|git +push +.*--force|git +reset +--hard|DROP +(TABLE|DATABASE)|curl .*\| *(ba)?sh'; then
  echo "Blocked by project hook: destructive or unsafe command. Ask the user to run it manually if truly needed." >&2
  exit 2
fi

exit 0
