"""Minimal Claude Agent SDK agent: scoped tools, subagent, and a run log.

Setup:
    uv init && uv add claude-agent-sdk      (or: pip install claude-agent-sdk)
    export ANTHROPIC_API_KEY=...             (the SDK does not read .env files itself)
Run:
    python agent.py "Summarize the open TODOs in this folder"

Verify option names against the current SDK reference before production use:
https://code.claude.com/docs/en/agent-sdk/python
"""
import asyncio
import json
import sys
import time

from claude_agent_sdk import (
    AgentDefinition,
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    query,
)

LOG_FILE = "agent_runs.jsonl"


def log(event: dict) -> None:
    event["ts"] = time.time()
    with open(LOG_FILE, "a") as f:
        f.write(json.dumps(event) + "\n")


async def main(task: str) -> None:
    options = ClaudeAgentOptions(
        # Least privilege: read-only tools plus the ability to delegate.
        allowed_tools=["Read", "Grep", "Glob", "Agent"],
        permission_mode="default",
        max_turns=30,
        system_prompt="You are an operations assistant. Cite file paths for every claim.",
        agents={
            "researcher": AgentDefinition(
                description="Read-only investigator for questions that need many files.",
                prompt="Investigate and return a summary under 300 words with evidence.",
                tools=["Read", "Grep", "Glob"],
                model="haiku",
            )
        },
    )

    log({"type": "start", "task": task})
    async for message in query(prompt=task, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text)
                elif hasattr(block, "name"):
                    log({"type": "tool_call", "tool": block.name})
        elif isinstance(message, ResultMessage):
            log({"type": "result", "subtype": message.subtype})
            print(f"\nDone: {message.subtype}")


if __name__ == "__main__":
    asyncio.run(main(" ".join(sys.argv[1:]) or "Summarize this folder."))
