#!/bin/bash
# PreToolUse hook for the designer subagent (matcher: Write|Edit).
# The designer may only write design documents and mockups, never application code.
# Allowed: design-brief.md, research-notes, anything under a design/ folder, and .md/.svg/.html mockups inside design/.
# Exit 2 = block, message goes to the agent.

FILE=$(jq -r '.tool_input.file_path // ""')

# Reject path-traversal tricks such as design/../src/app.ts
case "$FILE" in
  *..*) echo "Blocked: '..' is not allowed in file paths." >&2; exit 2 ;;
esac

case "$FILE" in
  */design-brief.md|*/design/*.md|*/design/*.svg|*/design/*.html|*/design/*.json)
    exit 0 ;;
esac

echo "Blocked: the designer may only write design-brief.md or files under design/ (md, svg, html, json). Hand code work to the builder." >&2
exit 2
