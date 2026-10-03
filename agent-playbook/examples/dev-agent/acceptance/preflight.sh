#!/bin/bash
# Preflight checks before any acceptance run. Run from inside the sandbox:  bash acceptance/preflight.sh
# Exit code 1 = a hard requirement is missing. Warnings (WARN) do not fail the run but need your attention.

cd "$(dirname "$0")/.." || exit 1
HARD=0
ok()   { echo "OK    $1"; }
warn() { echo "WARN  $1"; }
bad()  { echo "FAIL  $1"; HARD=1; }

# Tools the hooks and the builder need
for t in jq git python3 node npm; do
  command -v "$t" >/dev/null && ok "$t installed" || bad "$t is missing"
done
command -v claude >/dev/null && ok "claude CLI installed ($(claude --version 2>/dev/null | head -1))" || warn "claude CLI not found on PATH (fine if you use the desktop app)"

# Git repo with a commit (needed for the builder's isolated worktree)
if git rev-parse --verify HEAD >/dev/null 2>&1; then ok "git repo with a baseline commit"; else bad "not a git repo with a commit; use setup-sandbox.sh"; fi
git diff --quiet 2>/dev/null && ok "working tree clean" || warn "uncommitted changes in the sandbox"

# Files present
for f in .claude/settings.json CLAUDE.md SPEC.md \
         .claude/agents/researcher.md .claude/agents/designer.md .claude/agents/builder.md .claude/agents/reviewer.md \
         .claude/skills/idea-intake/SKILL.md .claude/skills/idea-intake/brief-template.md \
         .claude/hooks/block-dangerous.sh .claude/hooks/block-deploy.sh .claude/hooks/restrict-designer-writes.sh \
         .claude/hooks/lib-done-check.sh .claude/hooks/verify-done.sh .claude/hooks/deploy-gate.sh \
         acceptance/fixtures/competitor-notes.html; do
  [ -f "$f" ] && ok "$f" || bad "missing $f"
done

# Hooks executable and settings valid
for h in .claude/hooks/*.sh; do [ -x "$h" ] || bad "$h is not executable (chmod +x)"; done
python3 -c "import json;json.load(open('.claude/settings.json'))" 2>/dev/null && ok "settings.json is valid JSON" || bad "settings.json is invalid JSON"

# Hook logic tests
bash tests/test-verify-done.sh  >/tmp/pf_vd 2>&1 && ok "verify-done tests pass ($(grep Passed /tmp/pf_vd))" || bad "verify-done tests FAIL (see /tmp/pf_vd)"
bash tests/test-deploy-gate.sh  >/tmp/pf_dg 2>&1 && ok "deploy-gate tests pass ($(grep Passed /tmp/pf_dg))" || bad "deploy-gate tests FAIL (see /tmp/pf_dg)"

# Clean state
[ -e runs/.active ] && warn "runs/.active exists from a previous run; delete it before starting a new brief" || ok "no active run"

# Things that matter for the builder's done-check
if command -v npx >/dev/null && npx --no-install playwright --version >/dev/null 2>&1; then ok "Playwright available (screenshots)"; \
else warn "Playwright not found. The builder needs a headless browser for screenshots. Try: npm i -g playwright && npx playwright install chromium"; fi

# Secrets that could leak into a run
[ -f .env ] && warn ".env present in sandbox; remove it. The sandbox must contain no real credentials"
[ -n "$VERCEL_TOKEN" ] && warn "VERCEL_TOKEN is set in this shell. The builder must not inherit deploy credentials (unset it before the run)"
[ -n "$NETLIFY_AUTH_TOKEN" ] && warn "NETLIFY_AUTH_TOKEN is set in this shell (unset it before the run)"

echo
echo "Manual checks inside Claude Code (cannot be scripted):"
echo "  [ ] Folder trusted (hooks and agent-defined hooks only run after trust)"
echo "  [ ] /hooks lists PreToolUse (block-dangerous, deploy-gate) and Stop (verify-done)"
echo "  [ ] /agents lists researcher, designer, builder, reviewer"
echo "  [ ] /idea-intake appears in the / menu"
echo "  [ ] Sandboxing on (/sandbox) and a spend alert set in the API console or plan"

[ "$HARD" -eq 0 ] && echo "PREFLIGHT PASSED" || echo "PREFLIGHT FAILED"
exit $HARD
