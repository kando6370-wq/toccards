#!/usr/bin/env python3
import json
import re
import sys

DB_PATTERNS = [
    re.compile(r"pnpm\s+--filter\s+@kando/workers-api\s+db:generate"),
    re.compile(r"pnpm\s+--filter\s+@kando/workers-api\s+db:migrate:local"),
    re.compile(r"wrangler\s+d1\s+migrations\s+apply"),
    re.compile(r"drizzle-kit\s+generate"),
]

MESSAGE = (
    "数据库原则上应优先复用已有结构；如果要新增或修改数据库/schema/migration，必须先通知用户并获得确认。"
)


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command", "") if isinstance(tool_input, dict) else ""

    if isinstance(command, str) and any(pattern.search(command) for pattern in DB_PATTERNS):
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": MESSAGE,
            },
            "systemMessage": MESSAGE,
        }
        sys.stdout.write(json.dumps(output, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
