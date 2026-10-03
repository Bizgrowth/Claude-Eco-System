# Building AI Agents with Claude Code — Operator's Playbook

*Researched 3 Oct 2026 against Anthropic's live documentation (Claude Code v2.1.28x era) plus practitioner sources. Written for an operations consultant who builds with AI tools rather than hand-coding.*

---

## 1. The bottom line

1. **An agent is a loop, not a prompt.** Gather context → take action → verify → repeat. Anthropic's own guidance frames every design decision around this loop.
2. **Your leverage is the harness, not the model.** The harness is everything around the model: instructions, tools, permissions, guardrails, checks, memory. Claude Code *is* a ready-made harness, and the Agent SDK lets you reuse it inside your own product.
3. **Verification is the single biggest quality lever.** Anthropic's best-practices page opens with it: give the agent a check it can run (tests, a build, a screenshot, a script that diffs output). An agent with no check makes *you* the check.
4. **Context is the scarce resource.** Performance degrades as the context window fills. Nearly every best practice (short CLAUDE.md, skills that load on demand, subagents for research, `/clear`) exists to protect it.
5. **Rules the agent must never break belong in hooks and permissions, not in instructions.** Instructions are advice; hooks are enforced by the program, not the model.

---

## 2. Choose your build path (decide this first)

| Path | Who runs the agent | Use when | Trade-off |
|---|---|---|---|
| **Claude Code, interactive** | You, at a keyboard | Prototyping, internal tools, building the agent itself | Human in the loop; not a product |
| **Claude Code, headless** (`claude -p`, GitHub Actions, Routines/scheduled tasks) | Claude Code on your machine, CI, or Anthropic's cloud | Recurring jobs: reports, triage, reviews, migrations | Best effort-to-value for SMB automations |
| **Agent SDK** (Python / TypeScript) | Your own app or server | You need a custom UI, multi-tenant use, or to embed an agent in a client's product | You operate hosting, secrets, monitoring |
| **Managed Agents** (Claude API, **beta**) | Anthropic hosts the harness and sandbox | Long-running, asynchronous tasks without building infrastructure | Beta; stateful, so **not eligible for Zero Data Retention or HIPAA BAA** today |
| **Messages API + tool runner** | Your code | You want total control of the loop | You rebuild what the harness gives you |

**Recommended default for SMB clients:** prototype in interactive Claude Code → harden into headless/scheduled runs → move to the Agent SDK only when a client needs it embedded in their own software. Consider Managed Agents when you don't want to operate sandboxes and the data-retention limits are acceptable.

Auth note: for SDK-built products, use API-key (or Bedrock/Vertex/Foundry) authentication. Anthropic does not allow third-party products to offer claude.ai login or its rate limits unless previously approved.

---

## 3. Reference architecture

```
┌──────────────────────────────────────────────────────────────┐
│ 1. TRIGGER      you / schedule (Routines, cron) / webhook /  │
│                 GitHub event / Slack                          │
├──────────────────────────────────────────────────────────────┤
│ 2. CONTEXT      CLAUDE.md (always-on, <200 lines)             │
│                 Skills (on-demand playbooks)                  │
│                 Rules by file path · Memory · Spec/PLAN files │
├──────────────────────────────────────────────────────────────┤
│ 3. REASONING    Main agent  →  Subagents (isolated context)   │
│                 →  Workflows / Agent teams (scale, optional)  │
├──────────────────────────────────────────────────────────────┤
│ 4. TOOLS        Built-in (files, shell, web) · CLI tools ·    │
│                 MCP servers (Notion, Slack, HubSpot, Make…)   │
├──────────────────────────────────────────────────────────────┤
│ 5. GUARDRAILS   Permissions · Sandbox · Hooks (deterministic) │
│                 Auto-mode classifier · Least-privilege tools  │
├──────────────────────────────────────────────────────────────┤
│ 6. VERIFY       Tests/scripts · Stop hook · /goal ·           │
│                 independent reviewer subagent · human gate    │
├──────────────────────────────────────────────────────────────┤
│ 7. OBSERVE      Transcripts · logs · cost · eval set          │
└──────────────────────────────────────────────────────────────┘
```

Layers 5–7 are what separate a demo from something you can sell and support.

---

## 4. The harness: what Claude Code gives you vs. what you add

**Built in (use, don't rebuild):** the agent loop, file/shell/web tools, context compaction, checkpoints and `/rewind`, permission modes (including *auto mode*, where a separate classifier model reviews actions), sandboxing, sessions, worktrees for parallel work, prompt caching.

**You add:**

| Primitive | Job | Loads into context | Guarantee level |
|---|---|---|---|
| **CLAUDE.md** | Always-on project rules, commands, gotchas | Every session | Advisory |
| **`.claude/rules/`** | Rules scoped to file paths | When matching files open | Advisory |
| **Skills** | On-demand playbooks and reusable workflows | Description always; body when used | Advisory |
| **Subagents** | Isolated worker, returns a summary | Own separate context | Tool limits are enforced |
| **MCP servers** | Connections to outside systems | Names only; schemas on demand | Per-tool permissions |
| **Hooks** | Scripts that fire at lifecycle events | Zero unless they return output | **Deterministic** |
| **Plugins** | Package all of the above for reuse across repos/clients | Per component | n/a |
| **Dynamic workflows** | A script that runs dozens–hundreds of subagents and returns one answer | Only the final result | Script-controlled |

**Decision rule (from Anthropic's "Extend Claude Code" guide):**
- Must happen every time → **hook or permission**
- Knowledge needed sometimes → **skill**
- Needs its own context or tool limits → **subagent**
- True on every task → **CLAUDE.md** (and prune ruthlessly)
- Same setup for a second client → **plugin**

Build the setup over time, triggered by pain, not up front: a repeated mistake becomes a CLAUDE.md line; a prompt you paste three times becomes a skill; a rule that must not be broken becomes a hook.

---

## 5. Build design: the delivery method

Use this sequence for every agent. It matches Anthropic's recommended explore → plan → implement → commit flow and adds the pieces an SMB engagement needs.

**Step 1 — Spec (use plan mode and let Claude interview you).** Prompt: *"I want to build [agent]. Interview me using the AskUserQuestion tool about inputs, edge cases, failure modes, and what 'done' looks like. Write the result to SPEC.md."* A good spec names the files and systems involved, what is **out of scope**, and ends with an end-to-end check that proves it works. The `agent-spec` skill in the starter kit automates this interview.

**Step 2 — Define "done" as a check the agent can run.** Examples: a test file of 10 sample inputs with expected outputs; a script that diffs output against a fixture; a screenshot comparison; a dry-run that must write zero records. No check, no autonomy.

**Step 3 — Start a fresh session to build.** Clean context, spec in hand. Build the smallest vertical slice first (one input → one verified output).

**Step 4 — Add tools one at a time.** Prefer CLI tools (`gh`, `gcloud`, etc.) for context efficiency, MCP for systems with no good CLI. Give each subagent only the tools it needs.

**Step 5 — Independent review.** A reviewer subagent in a fresh context sees only the diff and your criteria. Tell it to flag only correctness or stated-requirement gaps, otherwise it will invent nitpicks and you'll over-engineer.

**Step 6 — Harden.** Add hooks for the hard rules, deny rules for secrets, a Stop-hook or `/goal` check for unattended runs, an eval set, and a human approval gate before any irreversible action (send, publish, pay, delete).

**Step 7 — Package and hand over.** Commit `.claude/` to the client repo (or ship as a plugin), write a one-page runbook, and set up monitoring and a monthly review.

**Session hygiene rules:** `/clear` between unrelated tasks; after two failed corrections, restart with a better prompt; name sessions like branches; use subagents for any investigation that reads many files.

---

## 6. Skills: how to write ones that actually trigger

A skill is a folder with a `SKILL.md`. Official guidance distilled:

- **Description is the trigger.** Write *what it does and when to use it*, with the words a user would actually say. Vague or overlapping descriptions cause missed or wrong activations.
- **Keep `SKILL.md` under ~500 lines**; move detail into sibling files (`reference.md`, `examples.md`, `scripts/`). They only load when needed.
- **Put the most important instructions first.** After compaction only the start of each skill is retained.
- **Side-effect skills get `disable-model-invocation: true`** (deploy, send, publish) so only a human can trigger them.
- **Background-knowledge skills get `user-invocable: false`.**
- **Use `context: fork`** to run a skill in an isolated subagent when it generates lots of output.
- **Use `allowed-tools`** to pre-approve only what the skill needs.
- **Use `!`command`` injection** to feed live data (git status, API output) into the prompt.
- **Test the trigger:** run it with and without naming it. If it only works when named, fix the description. Run `/skill-doctor` to find unused skills that waste context.
- **If Claude stops following a skill mid-session**, the rule probably belongs in a hook.

Two skills are included in the starter kit: `agent-spec` (requirements interview) and `ship-check` (pre-release gate).

---

## 7. Scaling up: subagents, workflows, agent teams

| Need | Use | Notes |
|---|---|---|
| Research that would flood the main context | **Subagent** (`Explore` is built in) | Returns a summary; one expertise per subagent |
| A second opinion on finished work | **Reviewer subagent** | Fresh context avoids author bias |
| Same task across 5–30 items (migration, audit) | **`/batch`** | Each in its own git worktree |
| Dozens–hundreds of agents with cross-checking | **Dynamic workflow** (`ultracode`, `/workflows`) | Script holds the plan; Claude's context holds only the answer. Cost grows fast; pilot on a small slice first |
| Peers that must debate and share findings | **Agent teams** | **Experimental, off by default**; known limits on resume and shutdown; start with research/review, 3–5 teammates, separate files per teammate |

Practical rules: cap `maxTurns` on research agents; pick cheaper models (`haiku`, `sonnet`) for simple stages; subagents don't see your conversation, so restate constraints in the delegation; never let two agents edit the same file.

---

## 8. Safety and governance (non-negotiable for client work)

- **Treat everything the agent reads as untrusted.** Web pages, emails, tickets and files can carry hidden instructions (prompt injection). Anything that reads untrusted content should not also hold broad write or send permissions.
- **Least privilege:** allowlist tools per agent and per task; deny reads of `.env`, keys and credential paths; sandbox shell access.
- **Enforce in code, not in prose.** Anthropic's docs state hooks are deterministic and CLAUDE.md is advisory. Recent academic work on the same question exists (e.g., *"When 'Do Not' Is Not Deny: Security Rules in CLAUDE.md vs Built-In Controls"*, arXiv 2608.23550) but I only saw the title and summary, so verify before citing it to a client.
- **Human gate before irreversible actions** (send email, publish, pay, delete, change CRM data in bulk).
- **Trust prompts matter:** project hooks and project-defined agents/MCP servers run only after the folder is trusted. Review third-party plugins before installing; they run with your privileges.
- **Org controls:** managed settings can allowlist plugins/marketplaces and force hooks (`allowManagedHooksOnly`).
- **Data handling:** decide per client where data may go (Anthropic API, Bedrock, Vertex, Foundry); note Managed Agents' retention limits.

---

## 9. Evals, observability, cost

- **Eval set from day one:** 20–50 real examples with expected outcomes. Re-run after every change to skills, prompts, or model upgrades. Anthropic's SDK guidance lists three verification styles: rules-based checks (best), visual checks, and LLM-as-judge (slowest and fuzzier).
- **Online checks:** log every run (inputs, tool calls, outputs, cost) and sample for review. Use hooks (`PostToolUse`, `Stop`) or SDK hooks to write the log.
- **Cost controls:** model per task, `maxTurns`, effort level, workflow size guideline (`small` by default on Pro), prompt-cache TTL settings, and a spend alert in the API console. Agent teams and workflows multiply token usage.
- **Track business KPIs, not just technical ones:** hours saved, error rate vs. manual process, approval/override rate, cost per run.

---

## 10. A 30-day plan for your first client agent

| Week | Outcome |
|---|---|
| 1 | Pick one workflow (high volume, rule-based, low blast radius). Run the `agent-spec` interview. Define the eval set and the "done" check. |
| 2 | Build the smallest vertical slice in interactive Claude Code. Add CLAUDE.md (under 50 lines), one skill, one tool connection. |
| 3 | Add reviewer subagent, hooks, deny rules, human approval gate. Run the eval set; fix failures at the root. |
| 4 | Switch to scheduled/headless runs. Add logging and a cost alert. Hand over runbook; schedule a 30-day review. |

**Good first agents for SMBs:** inbound lead triage and CRM enrichment, weekly KPI report drafting, invoice/PO data entry with exception queue, support-ticket first-draft replies (human approves), meeting-notes → tasks, competitor/market digests.

---

## 11. Starter kit in this repo

`agent-playbook/starter-kit/` contains copy-paste templates:

| File | Purpose |
|---|---|
| `CLAUDE.md` | Lean always-on instructions template |
| `.claude/settings.json` | Deny rules for secrets + a hook that blocks destructive commands |
| `.claude/hooks/block-dangerous.sh` | The enforcing script (tested) |
| `.claude/agents/reviewer.md` | Independent, read-only review subagent |
| `.claude/agents/researcher.md` | Cheap, read-only research subagent |
| `.claude/skills/agent-spec/SKILL.md` | Requirements interview → `SPEC.md` |
| `.claude/skills/ship-check/SKILL.md` | Human-triggered pre-release checklist |
| `sdk-agent/agent.py` | Minimal Agent SDK agent with scoped tools and a log hook |

To use: copy the contents into a client project (or `~/.claude/` for personal use), then ask Claude Code, *"Read CLAUDE.md and adapt it to this project."*

---

## 12. Sources and confidence

**Primary (Anthropic, fetched 3 Oct 2026; highest confidence):**
[Claude Code best practices](https://code.claude.com/docs/en/best-practices) ·
[Extend Claude Code](https://code.claude.com/docs/en/features-overview) ·
[Subagents](https://code.claude.com/docs/en/sub-agents) ·
[Skills](https://code.claude.com/docs/en/skills) ·
[Hooks](https://code.claude.com/docs/en/hooks) ·
[Dynamic workflows](https://code.claude.com/docs/en/workflows) ·
[Agent teams](https://code.claude.com/docs/en/agent-teams) ·
[Plugins](https://code.claude.com/docs/en/plugins/overview) ·
[Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview) ·
[Agent SDK quickstart](https://code.claude.com/docs/en/agent-sdk/quickstart) ·
[Managed Agents](https://platform.claude.com/docs/en/managed-agents/overview) ·
[Building agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)

**Secondary (practitioners; medium confidence, used for corroboration):**
[Claude Code Explained (alexop.dev)](https://alexop.dev/posts/understanding-claude-code-full-stack/) ·
[Harness guide (Capital & Compute)](https://capitalandcompute.net/blog/claude-code-harness-guide/) ·
[Agent harness (LogRocket)](https://blog.logrocket.com/building-an-agent-harness-with-claude-code/) ·
[claude-code-best-practice (GitHub)](https://github.com/shanraisshan/claude-code-best-practice) ·
[Boris Cherny tips (MadAppGang)](https://madappgang.com/blog/claude-code-tips-from-its-creator-boris-cherny/) ·
[Boris Cherny workflow on X, via Kol Tregaskes](https://x.com/koltregaskes/status/2007498194960441387) ·
[Agent security guide (Atlan)](https://atlan.com/know/ai-agent-risks-guardrails/)

**Limits of this research (be upfront with clients):**
- I could not watch YouTube videos or browse X directly. I only saw search-result titles and snippets. Treat the X/YouTube material as pointers. The Boris Cherny "parallel sessions plus verification" advice is corroborated by Anthropic's own docs, but the "2–3x quality" figure is a secondhand claim from a blog summary.
- The Claude Code docs change quickly (settings, version gates, experimental flags). Re-check the primary pages before each client engagement.
- One redirect (a `claude.dev` copy of Anthropic's "A harness for every task" blog post) was not followed because I could not verify the domain; I used Anthropic's own workflows documentation instead.
- Agent teams, Managed Agents and `/goal`-style features are labelled experimental or beta in the docs. Don't promise clients they'll stay unchanged.
