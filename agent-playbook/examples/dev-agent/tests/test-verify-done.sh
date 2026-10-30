#!/bin/bash
# Tests for .claude/hooks/verify-done.sh. Run: bash tests/test-verify-done.sh
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/verify-done.sh"
PASS=0; FAILN=0

new_project() {   # builds a fully passing run in a temp dir; echoes the dir
  local d; d=$(mktemp -d)
  mkdir -p "$d/runs/demo/evidence/screens"
  echo demo > "$d/runs/.active"
  printf 'STATUS: READY_FOR_APPROVAL\n' > "$d/runs/demo/run-report.md"
  printf 'Screens: screen-home and screen-booking-form\n' > "$d/runs/demo/design-brief.md"
  printf '12 passed\nEXIT_CODE: 0\n' > "$d/runs/demo/evidence/tests.txt"
  printf 'built ok\nEXIT_CODE: 0\n' > "$d/runs/demo/evidence/build.txt"
  echo png > "$d/runs/demo/evidence/screens/screen-home.png"
  echo png > "$d/runs/demo/evidence/screens/screen-booking-form.png"
  echo "all match" > "$d/runs/demo/evidence/screens/comparison.md"
  echo "No blocking gaps. Checked tests and screens." > "$d/runs/demo/evidence/review.md"
  echo "$d"
}

run_hook() { echo '{"cwd":"."}' | CLAUDE_PROJECT_DIR="$1" "$HOOK" >/tmp/vd_out 2>/tmp/vd_err; echo $?; }

expect() {  # name expected_exit actual_exit
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS  $1"; else FAILN=$((FAILN+1)); echo "FAIL  $1 (expected exit $2, got $3)"; fi
}

D=$(new_project);                                                  expect "all evidence present -> allow" 0 "$(run_hook "$D")"
D=$(new_project); rm "$D/runs/.active";                            expect "no active run -> allow" 0 "$(run_hook "$D")"
D=$(new_project); echo "STATUS: INTAKE_COMPLETE" > "$D/runs/demo/run-report.md"; expect "not claimed ready -> allow (can ask user)" 0 "$(run_hook "$D")"
D=$(new_project); echo "stuck" > "$D/runs/demo/blocker-report.md"; rm "$D/runs/demo/evidence/tests.txt"; expect "blocker report -> allow" 0 "$(run_hook "$D")"
D=$(new_project); rm "$D/runs/demo/evidence/tests.txt";            expect "missing tests.txt -> block" 2 "$(run_hook "$D")"
D=$(new_project); printf '3 failed\nEXIT_CODE: 1\n' > "$D/runs/demo/evidence/tests.txt"; expect "tests exit code 1 -> block" 2 "$(run_hook "$D")"
D=$(new_project); printf 'built\n' > "$D/runs/demo/evidence/build.txt"; expect "build.txt without EXIT_CODE -> block" 2 "$(run_hook "$D")"
D=$(new_project); rm "$D/runs/demo/evidence/screens/screen-booking-form.png"; expect "missing screenshot -> block" 2 "$(run_hook "$D")"
D=$(new_project); echo "Gaps: login missing" > "$D/runs/demo/evidence/review.md"; expect "reviewer not approving -> block" 2 "$(run_hook "$D")"
D=$(new_project); echo "no screens here" > "$D/runs/demo/design-brief.md"; expect "design names no screens -> block" 2 "$(run_hook "$D")"
D=$(new_project); echo "../../etc" > "$D/runs/.active";            expect "malformed slug -> allow (ignored)" 0 "$(run_hook "$D")"

# Reason text lists the specific failure
D=$(new_project); rm "$D/runs/demo/evidence/tests.txt"; run_hook "$D" >/dev/null
if grep -q "evidence/tests.txt is missing" /tmp/vd_err; then PASS=$((PASS+1)); echo "PASS  block message names the failure"; else FAILN=$((FAILN+1)); echo "FAIL  block message names the failure"; fi

# Loop guard: 3 blocks, then fail open with UNVERIFIED.txt
D=$(new_project); rm "$D/runs/demo/evidence/tests.txt"
r1=$(run_hook "$D"); r2=$(run_hook "$D"); r3=$(run_hook "$D"); r4=$(run_hook "$D")
expect "loop guard: block 1" 2 "$r1"; expect "loop guard: block 2" 2 "$r2"; expect "loop guard: block 3" 2 "$r3"; expect "loop guard: 4th fails open" 0 "$r4"
[ -f "$D/runs/demo/UNVERIFIED.txt" ] && { PASS=$((PASS+1)); echo "PASS  UNVERIFIED.txt written"; } || { FAILN=$((FAILN+1)); echo "FAIL  UNVERIFIED.txt written"; }

# Recovery: fixing the evidence clears the counter
D=$(new_project); rm "$D/runs/demo/evidence/tests.txt"; run_hook "$D" >/dev/null
printf '12 passed\nEXIT_CODE: 0\n' > "$D/runs/demo/evidence/tests.txt"
expect "fixed evidence -> allow" 0 "$(run_hook "$D")"
[ ! -f "$D/runs/demo/.stop-blocks" ] && { PASS=$((PASS+1)); echo "PASS  counter reset after pass"; } || { FAILN=$((FAILN+1)); echo "FAIL  counter reset after pass"; }

echo; echo "Passed: $PASS  Failed: $FAILN"
[ "$FAILN" -eq 0 ]
