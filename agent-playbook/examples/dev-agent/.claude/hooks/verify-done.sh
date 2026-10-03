#!/bin/bash
# Stop hook: enforces the done-check before the lead may say a run is ready for approval.
#
# How it decides:
#   - No active run (runs/.active missing)            -> allow stop
#   - blocker-report.md exists (valid "stuck" outcome) -> allow stop
#   - run-report.md lacks "STATUS: READY_FOR_APPROVAL" -> allow stop (lead may be mid-run or asking you a question)
#   - otherwise verify the evidence; if anything is missing, BLOCK the stop (exit 2) and list what to fix.
#
# Loop guard: after 3 consecutive blocks the hook fails open, writes UNVERIFIED.txt and warns the user,
# so a bad check can never trap the session forever.

INPUT=$(cat)
ROOT="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // "."')}"
ACTIVE="$ROOT/runs/.active"

[ -f "$ACTIVE" ] || exit 0
SLUG=$(tr -d '[:space:]' < "$ACTIVE")
case "$SLUG" in ""|*/*|*..*) exit 0 ;; esac   # ignore malformed markers
RUN="$ROOT/runs/$SLUG"
[ -d "$RUN" ] || exit 0

[ -f "$RUN/blocker-report.md" ] && exit 0
grep -q '^STATUS: READY_FOR_APPROVAL' "$RUN/run-report.md" 2>/dev/null || exit 0

FAIL=()

check_exit_code() {   # file under evidence/ must end with "EXIT_CODE: 0"
  local f="$RUN/evidence/$1"
  if [ ! -s "$f" ]; then FAIL+=("evidence/$1 is missing or empty"); return; fi
  local last
  last=$(grep -v '^[[:space:]]*$' "$f" | tail -n1)
  [ "$last" = "EXIT_CODE: 0" ] || FAIL+=("evidence/$1 must end with 'EXIT_CODE: 0' (last line is: ${last:0:80})")
}

check_exit_code "tests.txt"
check_exit_code "build.txt"

# Every screen named in the design brief needs a screenshot.
if [ -f "$RUN/design-brief.md" ]; then
  SCREENS=$(grep -oE 'screen-[a-z0-9-]+' "$RUN/design-brief.md" | sort -u)
  if [ -z "$SCREENS" ]; then
    FAIL+=("design-brief.md names no screens (expected names like screen-booking-form)")
  else
    for s in $SCREENS; do
      [ -s "$RUN/evidence/screens/$s.png" ] || FAIL+=("missing screenshot evidence/screens/$s.png")
    done
  fi
else
  FAIL+=("design-brief.md is missing")
fi

[ -s "$RUN/evidence/screens/comparison.md" ] || FAIL+=("evidence/screens/comparison.md is missing or empty")
grep -q 'No blocking gaps' "$RUN/evidence/review.md" 2>/dev/null || FAIL+=("evidence/review.md must contain the reviewer verdict 'No blocking gaps'")

COUNTER="$RUN/.stop-blocks"
if [ ${#FAIL[@]} -eq 0 ]; then
  rm -f "$COUNTER" "$RUN/UNVERIFIED.txt"
  exit 0
fi

N=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
if [ "$N" -gt 3 ]; then
  { echo "Done-check still failing after 3 blocked stops. Run is UNVERIFIED."; printf -- '- %s\n' "${FAIL[@]}"; } > "$RUN/UNVERIFIED.txt"
  jq -n '{systemMessage: "verify-done: done-check still failing after 3 attempts. Stop allowed, run marked UNVERIFIED (see UNVERIFIED.txt). Do not deploy."}'
  exit 0
fi
echo "$N" > "$COUNTER"

{
  echo "Not done yet. The done-check failed (block $N of 3):"
  printf -- '- %s\n' "${FAIL[@]}"
  echo "Fix these, or if you are genuinely stuck write blocker-report.md and stop. Do not claim READY_FOR_APPROVAL without evidence."
} >&2
exit 2
