#!/bin/bash
# Tests for .claude/hooks/deploy-gate.sh. Run: bash tests/test-deploy-gate.sh
HOOK="$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/deploy-gate.sh"
PASS=0; FAILN=0

new_project() {   # a fully verified, ready run
  local d; d=$(mktemp -d)
  mkdir -p "$d/runs/demo/evidence/screens"
  echo demo > "$d/runs/.active"
  printf 'STATUS: READY_FOR_APPROVAL\n' > "$d/runs/demo/run-report.md"
  printf 'Screens: screen-home\n' > "$d/runs/demo/design-brief.md"
  printf '12 passed\nEXIT_CODE: 0\n' > "$d/runs/demo/evidence/tests.txt"
  printf 'built\nEXIT_CODE: 0\n' > "$d/runs/demo/evidence/build.txt"
  echo png > "$d/runs/demo/evidence/screens/screen-home.png"
  echo ok > "$d/runs/demo/evidence/screens/comparison.md"
  echo "No blocking gaps." > "$d/runs/demo/evidence/review.md"
  echo "$d"
}

# decision <project> <tool_name> <tool_input_json>  -> prints deny|ask|allow(no output)
decision() {
  local out
  out=$(jq -n --arg t "$2" --argjson i "$3" '{tool_name:$t,tool_input:$i}' | CLAUDE_PROJECT_DIR="$1" "$HOOK" 2>/dev/null)
  if [ -z "$out" ]; then echo "allow"; else echo "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
bash_cmd() { decision "$1" Bash "$(jq -n --arg c "$2" '{command:$c}')"; }

expect() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS  $1"; else FAILN=$((FAILN+1)); echo "FAIL  $1 (expected $2, got $3)"; fi; }

D=$(new_project)
echo "--- ordinary commands pass through"
expect "npm test"               allow "$(bash_cmd "$D" 'npm test')"
expect "npm run build"          allow "$(bash_cmd "$D" 'npm run build')"
expect "git status"             allow "$(bash_cmd "$D" 'git status')"
expect "mcp read tool"          allow "$(decision "$D" mcp__Vercel__list_projects '{}')"

echo "--- hard denials, even for a perfect run"
expect "vercel --prod"          deny "$(bash_cmd "$D" 'vercel --prod')"
expect "vercel deploy --prod"   deny "$(bash_cmd "$D" 'vercel deploy --prod --yes')"
expect "netlify deploy --prod"  deny "$(bash_cmd "$D" 'netlify deploy --prod')"
expect "vercel promote"         deny "$(bash_cmd "$D" 'vercel promote abc')"
expect "vercel domains"         deny "$(bash_cmd "$D" 'vercel domains add x.com')"
expect "npm publish"            deny "$(bash_cmd "$D" 'npm publish')"
expect "gh release create"      deny "$(bash_cmd "$D" 'gh release create v1')"
expect "MCP buy_domain"         deny "$(decision "$D" mcp__Vercel__buy_domain '{}')"
expect "MCP request_promote"    deny "$(decision "$D" mcp__Vercel__request_promote '{}')"
expect "MCP add_project_domain" deny "$(decision "$D" mcp__Vercel__add_project_domain '{}')"
expect "MCP deploy w/ production target" deny "$(decision "$D" mcp__Vercel__create_deployment '{"target":"production"}')"

echo "--- preview deploy on a verified run needs a human (ask)"
expect "vercel (preview)"       ask "$(bash_cmd "$D" 'vercel')"
expect "vercel deploy"          ask "$(bash_cmd "$D" 'cd app && vercel deploy --yes')"
expect "MCP create_deployment"  ask "$(decision "$D" mcp__Vercel__create_deployment '{"name":"app"}')"
expect "MCP Lovable deploy"     ask "$(decision "$D" mcp__Lovable__deploy_project '{"project_id":"p"}')"
expect "git push always asks"   ask "$(bash_cmd "$D" 'git push origin feature')"

echo "--- preview deploy refused when the run is not ready"
D2=$(new_project); rm "$D2/runs/.active"
expect "no active run"          deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); echo "STATUS: INTAKE_COMPLETE" > "$D2/runs/demo/run-report.md"
expect "status not ready"       deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); rm "$D2/runs/demo/evidence/tests.txt"
expect "evidence missing"       deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); printf 'x\nEXIT_CODE: 2\n' > "$D2/runs/demo/evidence/build.txt"
expect "build failed"           deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); echo "Gaps found" > "$D2/runs/demo/evidence/review.md"
expect "reviewer not approving" deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); echo "unverified" > "$D2/runs/demo/UNVERIFIED.txt"
expect "UNVERIFIED run"         deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); echo "stuck" > "$D2/runs/demo/blocker-report.md"
expect "blocker report present" deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); echo "../../tmp" > "$D2/runs/.active"
expect "malformed slug"         deny "$(bash_cmd "$D2" 'vercel')"
D2=$(new_project); expect "MCP deploy, run not ready" deny "$(decision "$(rm "$D2/runs/demo/evidence/review.md"; echo "$D2")" mcp__Vercel__create_deployment '{}')"


echo "--- evasion attempts are caught (wrappers, quotes, direct API calls)"
D3=$(new_project)
expect "bash -c quoted --prod"   deny "$(bash_cmd "$D3" "bash -c 'vercel --prod'")"
expect "npx vercel --prod"       deny "$(bash_cmd "$D3" 'npx vercel --prod')"
expect "env var prefix + vercel" ask  "$(bash_cmd "$D3" 'VERCEL_ORG_ID=x vercel')"
expect "npm run deploy"          ask  "$(bash_cmd "$D3" 'npm run deploy')"
expect "pnpm run release:preview" ask "$(bash_cmd "$D3" 'pnpm run release:preview')"
expect "make deploy"             ask  "$(bash_cmd "$D3" 'make deploy')"
expect "./scripts/deploy.sh"     ask  "$(bash_cmd "$D3" './scripts/deploy.sh')"
expect "curl vercel API"         ask  "$(bash_cmd "$D3" 'curl -X POST https://api.vercel.com/v13/deployments')"
expect "curl netlify hook"       ask  "$(bash_cmd "$D3" 'curl https://api.netlify.com/hooks/x')"
D4=$(new_project); rm "$D4/runs/demo/evidence/build.txt"
expect "npm run deploy, no evidence" deny "$(bash_cmd "$D4" 'npm run deploy')"
expect "npm run test still passes through" allow "$(bash_cmd "$D3" 'npm run test')"
expect "npm run build still passes through" allow "$(bash_cmd "$D3" 'npm run build')"

echo "--- deny message is readable"
MSG=$(jq -n '{tool_name:"Bash",tool_input:{command:"vercel --prod"}}' | CLAUDE_PROJECT_DIR="$D" "$HOOK" | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$MSG" in *"never automated"*) PASS=$((PASS+1)); echo "PASS  reason text present";; *) FAILN=$((FAILN+1)); echo "FAIL  reason text: $MSG";; esac

echo; echo "Passed: $PASS  Failed: $FAILN"
[ "$FAILN" -eq 0 ]
