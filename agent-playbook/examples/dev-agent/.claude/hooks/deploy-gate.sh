#!/bin/bash
# PreToolUse hook: gates anything that deploys, publishes, or spends money.
# Applies to Bash commands and to MCP tools whose names suggest deploy/publish/domain/purchase actions.
#
# Three outcomes, emitted as JSON (exit 0):
#   deny  - always: production, promotion, aliases/domains, purchases, rollbacks, package publishing
#   ask   - preview deploys/publishes ONLY when the run is READY_FOR_APPROVAL, not UNVERIFIED, and the
#           full done-check passes. "ask" forces a real human approval prompt; there is no approval file
#           the agent could forge. With no human present (e.g. claude -p) an ask cannot be approved.
#   (no output) - everything else passes through to normal permission handling
#
# git push is always an "ask": pushing can trigger auto-deploys on connected hosts.

INPUT=$(cat)
# shellcheck source=lib-done-check.sh
source "$(dirname "$0")/lib-done-check.sh"

emit() {  # $1 = deny|ask   $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
CLASS=""   # deny | gated | push

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
  # SEP also matches quotes, backticks and $( so wrappers like  bash -c 'vercel --prod'  are caught.
  SEP="(^|[ ;&|('\"\`])"
  W='[A-Za-z0-9:_./-]*'   # script/target names such as deploy:prod or ./scripts/deploy.sh
  if echo "$CMD" | grep -Eq -- "--prod(uction)?([ =;&|)'\"\`]|$)|${SEP}(vercel|netlify) +(promote|alias|domains|rollback)|--env +production|${SEP}(npm|yarn|pnpm|bun) +publish|${SEP}gh +release +create"; then
    CLASS="deny"
  elif echo "$CMD" | grep -Eq -- "${SEP}(vercel|netlify|surge|firebase +deploy|wrangler +(deploy|publish))|${SEP}(npm|yarn|pnpm|bun) +run +${W}(deploy|release|publish)|${SEP}make +${W}(deploy|release|publish)|${SEP}${W}(deploy|release|publish)${W}\.(sh|py|js|mjs|ts)|curl .*(api\.vercel\.com|api\.netlify\.com|deploy-hooks|hooks\.(vercel|netlify))"; then
    CLASS="gated"
  elif echo "$CMD" | grep -Eq -- "${SEP}git +push"; then
    CLASS="push"
  fi
else
  # MCP tool: classify by name (case-insensitive)
  LOWER=$(echo "$TOOL" | tr '[:upper:]' '[:lower:]')
  if echo "$LOWER" | grep -Eq 'buy_|purchase|promote|rollback|alias|domain|delete_project|firewall'; then
    CLASS="deny"
  elif echo "$LOWER" | grep -Eq 'deploy|publish'; then
    CLASS="gated"
    # A production target in the arguments is never allowed.
    if echo "$INPUT" | jq -c '.tool_input // {}' | grep -Eqi 'production|"prod"'; then CLASS="deny"; fi
  fi
fi

[ -z "$CLASS" ] && exit 0

if [ "$CLASS" = "deny" ]; then
  emit deny "Blocked by deploy-gate: production, promotion, domains, purchases, rollbacks and package publishing are never automated in this pipeline. A human must do this manually."
fi

if [ "$CLASS" = "push" ]; then
  emit ask "git push may trigger an automatic deploy on a connected host. Approve only if you want this pushed."
fi

# CLASS = gated: preview deploys need a finished, verified run.
if ! resolve_run "$INPUT"; then
  emit deny "Blocked by deploy-gate: no active run (runs/.active). Deploys are only allowed from a finished /idea-intake run."
fi
[ -f "$RUN/UNVERIFIED.txt" ] && emit deny "Blocked by deploy-gate: run '$SLUG' is UNVERIFIED (see UNVERIFIED.txt). Fix the evidence first."
[ -f "$RUN/blocker-report.md" ] && emit deny "Blocked by deploy-gate: run '$SLUG' has a blocker report. Resolve it first."
grep -q '^STATUS: READY_FOR_APPROVAL' "$RUN/run-report.md" 2>/dev/null || \
  emit deny "Blocked by deploy-gate: run '$SLUG' is not READY_FOR_APPROVAL. Finish the pipeline and the done-check first."

collect_done_failures
if [ ${#FAIL[@]} -gt 0 ]; then
  emit deny "Blocked by deploy-gate: done-check failing for run '$SLUG': $(printf '%s; ' "${FAIL[@]}")"
fi

emit ask "Approve a PREVIEW deploy for run '$SLUG'? Done-check passed: tests and build exit 0, screenshots for every screen, reviewer 'No blocking gaps'. Production is not permitted."
