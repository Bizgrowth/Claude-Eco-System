#!/bin/bash
# Creates a clean, throwaway sandbox for acceptance runs.
# Usage: bash acceptance/setup-sandbox.sh ~/idea-to-preview-sandbox
#
# Why a copy: the builder uses `isolation: worktree`, which needs a git repo with at least one commit,
# and runs create files (runs/, evidence/) that should never land in the playbook repo.

set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?Usage: setup-sandbox.sh <destination-folder>}"

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "Refusing to use non-empty folder: $DEST" >&2; exit 1
fi

mkdir -p "$DEST"
cp -R "$SRC/." "$DEST/"
rm -rf "$DEST/runs"                     # fresh run history
chmod +x "$DEST"/.claude/hooks/*.sh "$DEST"/tests/*.sh "$DEST"/acceptance/*.sh

cd "$DEST"
printf 'runs/\nnode_modules/\n.env\n.env.*\n' > .gitignore
git init -q
git add -A
git -c user.name="sandbox" -c user.email="sandbox@example.invalid" commit -q -m "Sandbox baseline"

echo "Sandbox ready: $DEST"
echo "Next: cd $DEST && bash acceptance/preflight.sh"
