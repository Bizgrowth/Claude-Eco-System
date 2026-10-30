#!/bin/bash
# PreToolUse hook for the builder subagent (matcher: Bash).
# The builder builds and tests only. Deploying and publishing need human approval
# and are done by the lead after the done-check passes.
# Exit 2 = block, message goes to the agent.

COMMAND=$(jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -Eq '(^|[ ;&|])(vercel|netlify|surge|firebase +deploy|wrangler +(deploy|publish)|npm +publish|yarn +publish|pnpm +publish|git +push|gh +(pr|release|repo) )'; then
  echo "Blocked: deploying, publishing and pushing are not allowed for the builder. Finish the done-check and report; the lead deploys after human approval." >&2
  exit 2
fi

exit 0
