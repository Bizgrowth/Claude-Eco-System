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
# so a bad check can never trap the session forever. (deploy-gate.sh refuses deploys for UNVERIFIED runs.)

INPUT=$(cat)
# shellcheck source=lib-done-check.sh
source "$(dirname "$0")/lib-done-check.sh"

resolve_run "$INPUT" || exit 0
[ -f "$RUN/blocker-report.md" ] && exit 0
grep -q '^STATUS: READY_FOR_APPROVAL' "$RUN/run-report.md" 2>/dev/null || exit 0

collect_done_failures

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
