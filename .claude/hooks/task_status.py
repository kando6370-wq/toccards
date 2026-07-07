#!/usr/bin/env python3
import json
import sys
from datetime import datetime
from pathlib import Path

PHASE = sys.argv[1] if len(sys.argv) > 1 else "unknown"
ROOT = Path(__file__).resolve().parents[2]
STATUS_FILE = ROOT / "docs" / "superpowers" / "execution-status.md"


def read_payload() -> dict:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def extract_summary(payload: dict) -> str:
    candidates = [
        payload.get("prompt"),
        payload.get("message"),
        payload.get("userPrompt"),
        payload.get("transcript_path"),
    ]

    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict):
        candidates.extend(
            [
                tool_input.get("prompt"),
                tool_input.get("message"),
                tool_input.get("command"),
                tool_input.get("file_path"),
            ]
        )

    for item in candidates:
        if isinstance(item, str):
            summary = " ".join(item.strip().split())
            if summary:
                return summary[:140]

    return "未从 hook 输入中提取到任务摘要；请在任务完成前手动补充。"


def parse_existing() -> tuple[dict, list[str]]:
    if not STATUS_FILE.exists():
        return {}, []

    text = STATUS_FILE.read_text(encoding="utf-8")
    current = {}
    logs: list[str] = []
    in_logs = False

    for line in text.splitlines():
        if line.startswith("- 状态："):
            current["status"] = line.removeprefix("- 状态：").strip()
        elif line.startswith("- 最近开始："):
            current["started_at"] = line.removeprefix("- 最近开始：").strip()
        elif line.startswith("- 最近完成："):
            current["finished_at"] = line.removeprefix("- 最近完成：").strip()
        elif line.startswith("- 最近任务摘要："):
            current["summary"] = line.removeprefix("- 最近任务摘要：").strip()
        elif line.startswith("- 备注："):
            current["note"] = line.removeprefix("- 备注：").strip()
        elif line.strip() == "## 执行日志":
            in_logs = True
        elif in_logs and line.startswith("- "):
            logs.append(line)

    return current, logs


def render(current: dict, logs: list[str]) -> str:
    note = current.get(
        "note",
        "本文件由 hook 自动记录“任务开始 / 本轮结束”检查点；复杂多阶段任务请在交付前手动补充验证结论。",
    )

    lines = [
        "# 执行状态文档",
        "",
        "## 当前任务",
        f"- 状态：{current.get('status', '未开始')}",
        f"- 最近开始：{current.get('started_at', '未记录')}",
        f"- 最近完成：{current.get('finished_at', '未记录')}",
        f"- 最近任务摘要：{current.get('summary', '未记录')}",
        f"- 备注：{note}",
        "",
        "## 执行日志",
    ]

    if logs:
        lines.extend(logs)
    else:
        lines.append("- 暂无记录")

    return "\n".join(lines) + "\n"


def main() -> int:
    payload = read_payload()
    current, logs = parse_existing()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    summary = extract_summary(payload)

    if PHASE == "start":
        current["status"] = "进行中"
        current["started_at"] = now
        current["summary"] = summary
        logs.append(f"- {now} | 开始 | {summary}")
    elif PHASE == "stop":
        current["status"] = "本轮完成"
        current["finished_at"] = now
        current.setdefault("summary", summary)
        logs.append(f"- {now} | 完成 | {current.get('summary', summary)}")
    else:
        logs.append(f"- {now} | 未知阶段 | {summary}")

    STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATUS_FILE.write_text(render(current, logs), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
