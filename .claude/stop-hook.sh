#!/bin/bash
# Auto-logs every Claude Code session to the claude-session-logs branch on GitHub.

input=$(cat)

stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active' 2>/dev/null)
if [[ "$stop_hook_active" = "true" ]]; then
  exit 0
fi

SESSION_ID="$(echo "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)"
CWD_INPUT="$(echo "$input"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))"        2>/dev/null || true)"
REPO_DIR="${CWD_INPUT:-$(git rev-parse --show-toplevel 2>/dev/null)}"

if [[ -z "$REPO_DIR" || ! -d "$REPO_DIR/.git" ]]; then exit 0; fi

# Find the session JSONL transcript
PROJECTS_DIR="$HOME/.claude/projects"
JSONL_FILE=""

if [[ -n "$SESSION_ID" ]]; then
  JSONL_FILE="$(find "$PROJECTS_DIR" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)"
fi

if [[ -z "$JSONL_FILE" ]]; then
  PROJECT_HASH="$(echo "$REPO_DIR" | sed 's|/|-|g')"
  PROJECT_DIR="$PROJECTS_DIR/$PROJECT_HASH"
  if [[ -d "$PROJECT_DIR" ]]; then
    JSONL_FILE="$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)"
  fi
fi

if [[ -z "$JSONL_FILE" || ! -f "$JSONL_FILE" ]]; then exit 0; fi

SESSION_DATE="$(date -u +%Y-%m-%d)"
BASENAME="$(basename "$JSONL_FILE" .jsonl)"
TMP_MD="/tmp/claude-session-${BASENAME}.md"
MD_FILENAME="${SESSION_DATE}_${BASENAME}.md"
LOG_BRANCH="claude-session-logs"

python3 "$REPO_DIR/.claude/session-to-md.py" "$JSONL_FILE" "$TMP_MD" 2>/dev/null

if [[ ! -f "$TMP_MD" ]]; then exit 0; fi

cd "$REPO_DIR"
git fetch origin "$LOG_BRANCH" 2>/dev/null || true
PARENT_SHA="$(git rev-parse "origin/$LOG_BRANCH" 2>/dev/null || true)"

if [[ -z "$PARENT_SHA" ]]; then rm -f "$TMP_MD"; exit 0; fi

BLOB_SHA="$(git hash-object -w "$TMP_MD" 2>/dev/null)"
BASE_TREE="$(git rev-parse "${PARENT_SHA}^{tree}" 2>/dev/null)"
SUBTREE_SHA="$(git rev-parse "${BASE_TREE}:claude-sessions" 2>/dev/null || true)"

if [[ -z "$BLOB_SHA" || -z "$BASE_TREE" || -z "$SUBTREE_SHA" ]]; then rm -f "$TMP_MD"; exit 0; fi

NEW_SUBTREE_SHA="$(
  { git ls-tree "$SUBTREE_SHA" | grep -v "	${MD_FILENAME}$" ;
    echo "100644 blob ${BLOB_SHA}	${MD_FILENAME}" ; } | git mktree 2>/dev/null
)"
FINAL_TREE_SHA="$(
  { git ls-tree "$BASE_TREE" | grep -v "	claude-sessions$" ;
    echo "040000 tree ${NEW_SUBTREE_SHA}	claude-sessions" ; } | git mktree 2>/dev/null
)"

if [[ -n "$FINAL_TREE_SHA" && "$FINAL_TREE_SHA" != "$BASE_TREE" ]]; then
  NEW_COMMIT="$(git commit-tree "$FINAL_TREE_SHA" -p "$PARENT_SHA" -m "docs: update session log ${SESSION_DATE} [auto]" 2>/dev/null)"
  if [[ -n "$NEW_COMMIT" ]]; then
    for WAIT in 0 2 4 8 16; do
      [[ "$WAIT" -gt 0 ]] && sleep "$WAIT"
      if git push origin "${NEW_COMMIT}:refs/heads/${LOG_BRANCH}" 2>/dev/null; then
        break
      fi
    done
  fi
fi

rm -f "$TMP_MD"
exit 0
