# Project: [AGENT / CLIENT NAME]

## Purpose
[One sentence: what this agent does and for whom.]

## Commands
- Run checks: `[command that returns pass/fail]`
- Dry run (no writes): `[command]`
- Run for real: `[command]`

## Rules
- Never send, publish, delete, or bulk-update anything without explicit human approval.
- Work from SPEC.md. If the spec and the request conflict, ask.
- Prove completion with evidence: show the check's output, not a claim.
- IMPORTANT: Never read or print secrets (.env, keys, tokens).

## Gotchas
- [Non-obvious thing Claude would get wrong, e.g. "Sandbox CRM is read-only; production IDs start with prod_"]

## When compacting
Always preserve: the list of modified files, the check command, and open TODOs.

<!-- Keep under 200 lines. Move reference material into .claude/skills/. Every line should pass: "Would removing this cause a mistake?" -->
