#!/bin/bash
# Shared done-check used by verify-done.sh (Stop) and deploy-gate.sh (PreToolUse).
# Source this file; do not execute it.
#
# Usage:  RUN=/path/to/runs/<slug>; collect_done_failures
# Result: the FAIL array lists every missing or failing piece of evidence (empty = passed).

resolve_run() {   # sets ROOT, SLUG, RUN; returns 1 if there is no usable active run
  local input="$1"
  ROOT="${CLAUDE_PROJECT_DIR:-$(echo "$input" | jq -r '.cwd // "."')}"
  [ -f "$ROOT/runs/.active" ] || return 1
  SLUG=$(tr -d '[:space:]' < "$ROOT/runs/.active")
  case "$SLUG" in ""|*/*|*..*) return 1 ;; esac
  RUN="$ROOT/runs/$SLUG"
  [ -d "$RUN" ] || return 1
  return 0
}

check_exit_code() {   # file under evidence/ must end with "EXIT_CODE: 0"
  local f="$RUN/evidence/$1"
  if [ ! -s "$f" ]; then FAIL+=("evidence/$1 is missing or empty"); return; fi
  local last
  last=$(grep -v '^[[:space:]]*$' "$f" | tail -n1)
  [ "$last" = "EXIT_CODE: 0" ] || FAIL+=("evidence/$1 must end with 'EXIT_CODE: 0' (last line is: ${last:0:80})")
}

collect_done_failures() {
  FAIL=()
  check_exit_code "tests.txt"
  check_exit_code "build.txt"

  if [ -f "$RUN/design-brief.md" ]; then
    local screens s
    screens=$(grep -oE 'screen-[a-z0-9-]+' "$RUN/design-brief.md" | sort -u)
    if [ -z "$screens" ]; then
      FAIL+=("design-brief.md names no screens (expected names like screen-booking-form)")
    else
      for s in $screens; do
        [ -s "$RUN/evidence/screens/$s.png" ] || FAIL+=("missing screenshot evidence/screens/$s.png")
      done
    fi
  else
    FAIL+=("design-brief.md is missing")
  fi

  [ -s "$RUN/evidence/screens/comparison.md" ] || FAIL+=("evidence/screens/comparison.md is missing or empty")
  grep -q 'No blocking gaps' "$RUN/evidence/review.md" 2>/dev/null || FAIL+=("evidence/review.md must contain the reviewer verdict 'No blocking gaps'")
}
