#!/bin/bash
# SessionStart hook: installs the stop-hook globally so every response
# in this session is logged to the session-logs branch on GitHub.

set -euo pipefail

# Only run in remote (Claude Code web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

REPO_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"

if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
  exit 0
fi

# Install the stop hook script into the global ~/.claude/ directory
mkdir -p "$HOME/.claude"
cp "$REPO_DIR/.claude/stop-hook.sh"     "$HOME/.claude/stop-hook.sh"
cp "$REPO_DIR/.claude/session-to-md.py" "$HOME/.claude/session-to-md.py"
chmod +x "$HOME/.claude/stop-hook.sh" "$HOME/.claude/session-to-md.py"

# Merge the Stop hook into the global ~/.claude/settings.json
python3 - <<'EOF'
import json, os, sys

settings_path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

settings.setdefault("hooks", {})
settings["hooks"]["Stop"] = [
    {
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": "~/.claude/stop-hook.sh"
            }
        ]
    }
]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=4)

print("Stop hook installed in ~/.claude/settings.json")
EOF
