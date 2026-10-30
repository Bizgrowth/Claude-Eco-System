---
name: agent-spec
description: Interview the user to produce a SPEC.md for a new AI agent or automation. Use when starting a new agent, scoping a workflow to automate, or when the user says "spec", "scope", or "requirements" for an agent.
---
Interview me about the agent described in: $ARGUMENTS

Use the AskUserQuestion tool. Skip obvious questions; dig into hard parts. Cover:

1. **Trigger and inputs**: what starts a run, what data arrives, in what format and volume.
2. **Outputs**: where results go, who reads them, what "good" looks like.
3. **Systems and permissions**: which tools/APIs, read vs write, credentials, sandbox vs production.
4. **Failure modes**: bad input, missing data, tool outages, ambiguous cases. What should the agent do for each?
5. **Human gates**: which actions require approval (send, publish, pay, delete, bulk change).
6. **Out of scope**: what the agent must not do.
7. **Done check**: a command or sample set that returns pass/fail without a human.
8. **Business metrics**: baseline hours/cost today, target, error tolerance.
9. **Data and compliance**: sensitive data, retention, where data may be processed.

Keep interviewing until covered, then write SPEC.md with sections: Goal, Inputs, Outputs, Tools & Permissions, Failure Handling, Human Gates, Out of Scope, Done Check, Metrics, Open Questions. Name specific files and interfaces. End with an end-to-end verification step.
