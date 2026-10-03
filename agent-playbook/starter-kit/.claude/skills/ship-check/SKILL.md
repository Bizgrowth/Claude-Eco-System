---
name: ship-check
description: Pre-release gate for an agent before it goes live or is handed to a client. Run manually only.
disable-model-invocation: true
---
Run this gate against the current project and report PASS / FAIL per item with evidence (command output or file path). Do not fix anything unless I ask.

Current changes:
!`git status --short`

Checklist:
1. The done-check from SPEC.md runs and passes. Show output.
2. Eval set (if present) passes at the agreed threshold. Show the score.
3. A dry run writes zero records to production systems.
4. `.claude/settings.json` denies secret paths and the dangerous-command hook is present.
5. Every irreversible action has a human approval step.
6. No secrets in the repo (check `git grep -nE "(api[_-]?key|secret|token)\s*[:=]"` and review hits).
7. Each subagent has only the tools it needs.
8. Logging is on and a cost/usage alert exists.
9. CLAUDE.md is under 200 lines and contains no stale instructions.
10. A runbook exists: how to run, how to stop, who to call.

End with a one-line verdict: SHIP / SHIP WITH FIXES / DO NOT SHIP.
