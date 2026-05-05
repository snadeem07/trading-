#!/usr/bin/env python3
"""Convert a Claude Code session JSONL transcript to a formatted Markdown file."""

import json
import sys
import os
from datetime import datetime, timezone


def format_timestamp(ts_str):
    try:
        dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        return ts_str


def extract_text_from_content(content_blocks):
    parts = []
    for block in content_blocks:
        btype = block.get("type", "")
        if btype == "text":
            text = block.get("text", "").strip()
            if text:
                parts.append(text)
        elif btype == "tool_use":
            name = block.get("name", "unknown")
            inp = block.get("input", {})
            inp_str = json.dumps(inp, indent=2) if inp else ""
            parts.append(f"**Tool call: `{name}`**\n```json\n{inp_str}\n```")
        elif btype == "tool_result":
            content = block.get("content", "")
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        result_text = c.get("text", "").strip()
                        if result_text:
                            parts.append(f"**Tool result:**\n```\n{result_text[:2000]}\n```")
            elif isinstance(content, str) and content.strip():
                parts.append(f"**Tool result:**\n```\n{content.strip()[:2000]}\n```")
    return "\n\n".join(parts)


def jsonl_to_markdown(jsonl_path):
    messages = []
    session_id = None
    session_title = None
    git_branch = None

    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            etype = entry.get("type", "")

            if etype == "ai-title" and not session_title:
                session_title = entry.get("aiTitle", "")
                session_id = entry.get("sessionId", "")

            elif etype == "user":
                msg = entry.get("message", {})
                content = msg.get("content", "")
                ts = entry.get("timestamp", "")
                git_branch = entry.get("gitBranch", git_branch)
                cwd = entry.get("cwd", "")

                if isinstance(content, str):
                    text = content.strip()
                elif isinstance(content, list):
                    text = extract_text_from_content(content)
                else:
                    text = ""

                if text:
                    messages.append({
                        "role": "user",
                        "text": text,
                        "timestamp": ts,
                        "cwd": cwd,
                    })

            elif etype == "assistant":
                msg = entry.get("message", {})
                content_blocks = msg.get("content", [])
                ts = entry.get("timestamp", "")
                git_branch = entry.get("gitBranch", git_branch)

                text = extract_text_from_content(content_blocks)
                if text:
                    messages.append({
                        "role": "assistant",
                        "text": text,
                        "timestamp": ts,
                    })

    # Build markdown
    lines = []

    title = session_title or "Claude Code Session"
    lines.append(f"# {title}\n")

    meta = []
    if session_id:
        meta.append(f"**Session ID:** `{session_id}`")
    if git_branch:
        meta.append(f"**Branch:** `{git_branch}`")
    if messages:
        first_ts = messages[0].get("timestamp", "")
        if first_ts:
            meta.append(f"**Started:** {format_timestamp(first_ts)}")
        cwd = messages[0].get("cwd", "")
        if cwd:
            meta.append(f"**Working directory:** `{cwd}`")

    if meta:
        lines.append("\n".join(meta))
        lines.append("")

    lines.append("---\n")

    for msg in messages:
        role = msg["role"]
        ts = format_timestamp(msg.get("timestamp", ""))
        text = msg["text"]

        if role == "user":
            lines.append(f"## User")
            lines.append(f"*{ts}*\n")
            lines.append(text)
        else:
            lines.append(f"## Claude")
            lines.append(f"*{ts}*\n")
            lines.append(text)

        lines.append("\n---\n")

    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: session-to-md.py <session.jsonl> [output.md]", file=sys.stderr)
        sys.exit(1)

    jsonl_path = sys.argv[1]
    if not os.path.exists(jsonl_path):
        print(f"File not found: {jsonl_path}", file=sys.stderr)
        sys.exit(1)

    md = jsonl_to_markdown(jsonl_path)

    if len(sys.argv) >= 3:
        out_path = sys.argv[2]
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"Written: {out_path}")
    else:
        print(md)


if __name__ == "__main__":
    main()
