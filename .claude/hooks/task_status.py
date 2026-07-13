#!/usr/bin/env python3
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

PHASE = sys.argv[1] if len(sys.argv) > 1 else "unknown"
ROOT = Path(__file__).resolve().parents[2]
STATUS_FILE = Path(
    sys.argv[2]
    if len(sys.argv) > 2
    else os.environ.get("TASK_STATUS_FILE", ROOT / "docs" / "superpowers" / "execution-status.md")
)
DEV_PLAN_FILE = Path(
    sys.argv[3]
    if len(sys.argv) > 3
    else os.environ.get("TASK_DEV_PLAN_FILE", ROOT / "docs" / "tcg-card" / "05-plan" / "dev-plan.md")
)
STATE_MARKER_START = "<!-- task-status-state"
DEFAULT_SUMMARY = "未从 hook 输入中提取到可读任务摘要；请在任务完成前手动补充。"
DEFAULT_NOTE = (
    "`docs/tcg-card/05-plan/dev-plan.md` 是只读计划真源；本文件展示当前执行态与计划状态覆盖层。"
    "带 `[Mx-y]` / `[TBD Mx-A]` 前缀的任务会更新计划状态，无前缀任务只记录执行日志。"
)
TASK_BOARD_DEFAULT = [
    "已完成：审阅现有 hook 与计划文档",
    "已完成：实现 dev-plan 状态覆盖层",
    "已完成：调整完成验证与 hook 配置",
    "已完成：更新规则文档与执行状态",
    "已完成：展示全量 dev-plan 子任务状态",
    "已完成：清理 execution-status 历史脏摘要",
    "已完成：归一 execution-status 隐藏状态块",
]
PLAN_TASK_BOOTSTRAP = {
    **{f"M0-{index}": "completed" for index in range(1, 9)},
    **{f"M1-{index}": "completed" for index in range(1, 13)},
}
PLAN_TBD_BOOTSTRAP = {
    "TBD M1-A": "open",
    "TBD M1-B": "open",
}
BOOTSTRAP_UPDATED_AT = "历史回填（基于当前仓库状态）"
LEGACY_NOTES = {
    "本文件由 hook 自动记录“任务开始 / 本轮结束”检查点；复杂多阶段任务请在交付前手动补充验证结论。",
    "本文件由 hook 自动记录“任务开始 / 本轮结束”检查点；当前已手动补充本轮完成结论与验证结果。",
}
SUMMARY_LIMIT = 140
PLAN_REF_RE = re.compile(r"\[(TBD\s+M\d+-[A-Z]|M\d+-\d+)\]")
TBD_REF_RE = re.compile(r"\bTBD\s+M\d+-[A-Z]\b")
TASK_REF_RE = re.compile(r"\bM\d+-\d+\b")
MILESTONE_HEADER_RE = re.compile(r"^##\s+\d+\.\s+(M\d)\s+")
STATE_BLOCK_RE = re.compile(r"<!-- task-status-state\n(.*?)\n-->", re.DOTALL)
LOG_LINE_RE = re.compile(r"^-\s+(?P<time>[^|]+)\|\s*(?P<phase>[^|]+)\|\s*(?P<summary>.*)$")


def read_payload() -> dict:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def now_string() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def collapse_text(value: str) -> str:
    return " ".join(value.strip().split())


def looks_like_invalid_summary(value: str) -> bool:
    if not value:
        return True
    if ".claude/projects/" in value:
        return True
    if value.startswith("/") or value.startswith("~/"):
        return True
    if value.endswith(".jsonl"):
        return True
    if re.fullmatch(r"(?:\.?\.?/)?[^\s]+\.(?:jsonl|json|md|ts|tsx|js|jsx|py|sh|yaml|yml)", value):
        return True
    return False


def sanitize_summary(value: str | None) -> str | None:
    if not isinstance(value, str):
        return None
    collapsed = collapse_text(value)
    if not collapsed or looks_like_invalid_summary(collapsed):
        return None
    return collapsed[:SUMMARY_LIMIT]


def is_meaningful_summary(summary: str | None) -> bool:
    return isinstance(summary, str) and bool(summary) and summary != DEFAULT_SUMMARY


def normalize_plan_ref(value: str | None) -> str | None:
    if not isinstance(value, str):
        return None
    collapsed = collapse_text(value).upper()
    if collapsed.startswith("TBD "):
        return re.sub(r"\s+", " ", collapsed)
    return collapsed


def strip_plan_prefix(summary: str, plan_ref: str | None) -> str:
    if not plan_ref:
        return summary

    stripped = re.sub(r"^\[(TBD\s+M\d+-[A-Z]|M\d+-\d+)\]\s*", "", summary, count=1)
    if stripped != summary:
        return stripped.strip() or summary

    if summary.startswith(f"{plan_ref} "):
        return summary[len(plan_ref) :].strip() or summary

    return summary


def collect_candidates(payload: dict) -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()

    def push(value: object) -> None:
        if not isinstance(value, str):
            return
        if value in seen:
            return
        seen.add(value)
        candidates.append(value)

    ordered_keys = [
        "subject",
        "title",
        "summary",
        "description",
        "prompt",
        "message",
        "userPrompt",
        "raw",
        "transcript_path",
    ]

    def visit_mapping(mapping: dict) -> None:
        for key in ordered_keys:
            push(mapping.get(key))

    visit_mapping(payload)

    for nested_key in ["task", "tool_input", "input", "data"]:
        nested = payload.get(nested_key)
        if isinstance(nested, dict):
            visit_mapping(nested)
            for extra_key in ["command", "file_path", "path"]:
                push(nested.get(extra_key))

    return candidates


def extract_plan_ref(payload: dict) -> str | None:
    for candidate in collect_candidates(payload):
        match = PLAN_REF_RE.search(candidate)
        if match:
            return normalize_plan_ref(match.group(1))

    for candidate in collect_candidates(payload):
        match = TBD_REF_RE.search(candidate)
        if match:
            return normalize_plan_ref(match.group(0))

    for candidate in collect_candidates(payload):
        match = TASK_REF_RE.search(candidate)
        if match:
            return normalize_plan_ref(match.group(0))

    return None


def parse_dev_plan() -> dict:
    if not DEV_PLAN_FILE.exists():
        return {"tasks_by_id": {}, "tbds_by_id": {}, "milestones": {}, "milestone_titles": {}}

    text = DEV_PLAN_FILE.read_text(encoding="utf-8")
    tasks_by_id: dict[str, dict] = {}
    tbds_by_id: dict[str, dict] = {}
    milestones: dict[str, list[str]] = {}
    milestone_titles: dict[str, str] = {}
    current_milestone: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        milestone_match = MILESTONE_HEADER_RE.match(line)
        if milestone_match:
            current_milestone = milestone_match.group(1)
            milestone_title = line.split(current_milestone, 1)[1].strip()
            milestone_titles[current_milestone] = milestone_title
            milestones.setdefault(current_milestone, [])
            continue

        if not line.startswith("|"):
            continue

        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) < 2 or cells[0] in {"#", "任务", "里程碑", "TBD 编号"}:
            continue

        task_id = normalize_plan_ref(cells[0])
        title = cells[1]
        if not task_id or not title or title == "---":
            continue

        if task_id.startswith("M") and "-" in task_id and not task_id.startswith("TBD "):
            if current_milestone is None:
                continue
            tasks_by_id[task_id] = {
                "id": task_id,
                "title": title,
                "milestone": current_milestone,
            }
            milestones.setdefault(current_milestone, [])
            if task_id not in milestones[current_milestone]:
                milestones[current_milestone].append(task_id)
            continue

        if task_id.startswith("TBD ") and len(cells) >= 4:
            affects = [part.strip() for part in re.split(r"[、,，\s]+", cells[2]) if part.strip()]
            tbds_by_id[task_id] = {
                "id": task_id,
                "title": title,
                "affects_milestones": affects,
            }

    return {
        "tasks_by_id": tasks_by_id,
        "tbds_by_id": tbds_by_id,
        "milestones": milestones,
        "milestone_titles": milestone_titles,
    }


def extract_human_summary(payload: dict, plan_ref: str | None, plan_index: dict) -> str:
    for candidate in collect_candidates(payload):
        summary = sanitize_summary(candidate)
        if not summary:
            continue
        summary = strip_plan_prefix(summary, plan_ref)
        if summary:
            return summary[:SUMMARY_LIMIT]

    if plan_ref and plan_ref in plan_index["tasks_by_id"]:
        return plan_index["tasks_by_id"][plan_ref]["title"]
    if plan_ref and plan_ref in plan_index["tbds_by_id"]:
        return plan_index["tbds_by_id"][plan_ref]["title"]

    return DEFAULT_SUMMARY


def default_state() -> dict:
    return {
        "current": {
            "status": "未开始",
            "started_at": None,
            "finished_at": None,
            "plan_ref": None,
            "summary": None,
            "last_verification": "未记录",
            "note": DEFAULT_NOTE,
        },
        "logs": [],
        "plan": {"tasks": {}, "tbds": {}},
        "meta": {"hook_errors": [], "task_board": []},
    }


def parse_legacy(text: str) -> dict:
    state = default_state()
    current = state["current"]
    in_logs = False

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if line.startswith("- 状态："):
            current["status"] = line.removeprefix("- 状态：").strip() or current["status"]
        elif line.startswith("- 最近开始："):
            value = line.removeprefix("- 最近开始：").strip()
            current["started_at"] = None if value == "未记录" else value
        elif line.startswith("- 最近完成："):
            value = line.removeprefix("- 最近完成：").strip()
            current["finished_at"] = None if value == "未记录" else value
        elif line.startswith("- 最近任务摘要："):
            current["summary"] = sanitize_summary(line.removeprefix("- 最近任务摘要：").strip())
        elif line.startswith("- 备注："):
            note = line.removeprefix("- 备注：").strip()
            current["note"] = DEFAULT_NOTE if not note or note in LEGACY_NOTES else note
        elif line.strip() == "## 执行日志":
            in_logs = True
        elif in_logs and line.startswith("- "):
            match = LOG_LINE_RE.match(line)
            if not match:
                continue
            plan_ref = normalize_plan_ref(extract_ref_from_text(match.group("summary")))
            summary = sanitize_summary(match.group("summary"))
            if summary:
                summary = strip_plan_prefix(summary, plan_ref)
            elif not plan_ref:
                continue
            state["logs"].append(
                {
                    "time": match.group("time").strip(),
                    "phase": match.group("phase").strip(),
                    "summary": summary or "",
                    "plan_ref": plan_ref,
                }
            )

    current_plan_ref = normalize_plan_ref(extract_ref_from_text(current.get("summary") or ""))
    if current_plan_ref:
        current["plan_ref"] = current_plan_ref
        current["summary"] = strip_plan_prefix(current["summary"], current_plan_ref)

    if current["status"] == "本轮完成":
        current["last_verification"] = "通过"
    elif current["status"] == "进行中":
        current["last_verification"] = "未记录"

    return state


def parse_existing() -> dict:
    if not STATUS_FILE.exists():
        return default_state()

    text = STATUS_FILE.read_text(encoding="utf-8")
    state_match = STATE_BLOCK_RE.search(text)
    if state_match:
        try:
            state = json.loads(state_match.group(1))
        except json.JSONDecodeError:
            state = default_state()
    else:
        state = parse_legacy(text)

    state.setdefault("current", {})
    state.setdefault("logs", [])
    state.setdefault("plan", {})
    state.setdefault("meta", {})
    state["plan"].setdefault("tasks", {})
    state["plan"].setdefault("tbds", {})
    state["meta"].setdefault("hook_errors", [])
    state["meta"].setdefault("task_board", list(TASK_BOARD_DEFAULT))

    current = state["current"]
    current.setdefault("status", "未开始")
    current.setdefault("started_at", None)
    current.setdefault("finished_at", None)
    current.setdefault("plan_ref", None)
    current.setdefault("summary", None)
    current.setdefault("last_verification", "未记录")
    current.setdefault("note", DEFAULT_NOTE)

    if not current.get("summary") or current.get("summary") == DEFAULT_SUMMARY:
        current["summary"] = None

    return state


def extract_ref_from_text(value: str) -> str | None:
    bracket_match = PLAN_REF_RE.search(value)
    if bracket_match:
        return bracket_match.group(1)

    tbd_match = TBD_REF_RE.search(value)
    if tbd_match:
        return tbd_match.group(0)

    task_match = TASK_REF_RE.search(value)
    if task_match:
        return task_match.group(0)

    return None


def phase_label(phase: str) -> str:
    return {
        "start": "开始",
        "stop": "完成（验证通过）",
        "fail": "完成验证失败",
    }.get(phase, "未知阶段")


def is_tbd_ref(plan_ref: str | None) -> bool:
    return isinstance(plan_ref, str) and plan_ref.startswith("TBD ")


def update_plan_overlay(state: dict, plan_index: dict, plan_ref: str | None, status: str, summary: str, timestamp: str) -> None:
    if not plan_ref:
        return

    if plan_ref in plan_index["tasks_by_id"]:
        plan_task = plan_index["tasks_by_id"][plan_ref]
        state["plan"]["tasks"][plan_ref] = {
            "status": status,
            "updated_at": timestamp,
            "summary": summary,
            "title": plan_task["title"],
            "milestone": plan_task["milestone"],
        }
        return

    if plan_ref in plan_index["tbds_by_id"]:
        plan_tbd = plan_index["tbds_by_id"][plan_ref]
        state["plan"]["tbds"][plan_ref] = {
            "status": status,
            "updated_at": timestamp,
            "summary": summary,
            "title": plan_tbd["title"],
            "affects_milestones": plan_tbd["affects_milestones"],
        }


def append_log(state: dict, timestamp: str, phase: str, plan_ref: str | None, summary: str) -> None:
    if not is_meaningful_summary(summary) and not plan_ref:
        return

    candidate = {
        "time": timestamp,
        "phase": phase_label(phase),
        "summary": summary if is_meaningful_summary(summary) else "",
        "plan_ref": plan_ref,
    }

    logs = state["logs"]
    if logs:
        last = logs[-1]
        if (
            last.get("phase") == candidate["phase"]
            and last.get("summary") == candidate["summary"]
            and last.get("plan_ref") == candidate["plan_ref"]
        ):
            return

    logs.append(candidate)


def apply_phase(state: dict, payload: dict, plan_index: dict, timestamp: str) -> None:
    current = state["current"]
    extracted_plan_ref = extract_plan_ref(payload)
    current_plan_ref = normalize_plan_ref(current.get("plan_ref"))
    plan_ref = extracted_plan_ref or current_plan_ref
    summary = extract_human_summary(payload, plan_ref, plan_index)
    if summary == DEFAULT_SUMMARY and current.get("summary"):
        summary = current["summary"]

    if plan_ref and plan_ref not in plan_index["tasks_by_id"] and plan_ref not in plan_index["tbds_by_id"]:
        plan_ref = None

    if PHASE == "start":
        current["status"] = "进行中"
        current["started_at"] = timestamp
        current["plan_ref"] = plan_ref
        if is_meaningful_summary(summary):
            current["summary"] = summary
        current["last_verification"] = "未记录"
        update_plan_overlay(
            state,
            plan_index,
            plan_ref,
            "open" if plan_ref and plan_ref.startswith("TBD ") else "in_progress",
            summary,
            timestamp,
        )
        append_log(state, timestamp, PHASE, plan_ref, summary)
        return

    if PHASE == "stop":
        current["status"] = "本轮完成（验证通过）"
        current["finished_at"] = timestamp
        current["plan_ref"] = plan_ref or current_plan_ref
        if plan_ref and plan_ref != current_plan_ref and is_meaningful_summary(summary):
            current["summary"] = summary
        elif not current.get("summary") and is_meaningful_summary(summary):
            current["summary"] = summary
        current["last_verification"] = "通过"
        update_plan_overlay(
            state,
            plan_index,
            current.get("plan_ref"),
            "resolved" if is_tbd_ref(current.get("plan_ref")) else "completed",
            current.get("summary") or summary,
            timestamp,
        )
        append_log(state, timestamp, PHASE, current.get("plan_ref"), current.get("summary") or summary)
        return

    if PHASE == "fail":
        current["status"] = "验证失败（任务仍进行中）"
        current["finished_at"] = timestamp
        current["plan_ref"] = plan_ref or current_plan_ref
        if plan_ref and plan_ref != current_plan_ref and is_meaningful_summary(summary):
            current["summary"] = summary
        elif not current.get("summary") and is_meaningful_summary(summary):
            current["summary"] = summary
        current["last_verification"] = "失败"
        update_plan_overlay(
            state,
            plan_index,
            current.get("plan_ref"),
            "open" if is_tbd_ref(current.get("plan_ref")) else "in_progress",
            current.get("summary") or summary,
            timestamp,
        )
        append_log(state, timestamp, PHASE, current.get("plan_ref"), current.get("summary") or summary)
        return

    append_log(state, timestamp, PHASE, plan_ref, summary)


def sort_task_ref(plan_ref: str) -> tuple[int, int, str]:
    match = re.fullmatch(r"M(\d+)-(\d+)", plan_ref)
    if not match:
        return (999, 999, plan_ref)
    return (int(match.group(1)), int(match.group(2)), plan_ref)


def sort_tbd_ref(plan_ref: str) -> tuple[int, str, str]:
    match = re.fullmatch(r"TBD M(\d+)-([A-Z])", plan_ref)
    if not match:
        return (999, "Z", plan_ref)
    return (int(match.group(1)), match.group(2), plan_ref)


def record_hook_error(state: dict, message: str) -> None:
    errors = state.setdefault("meta", {}).setdefault("hook_errors", [])
    if message not in errors:
        errors.append(message)


def bootstrap_plan_overlay(state: dict, plan_index: dict) -> None:
    task_overlay = state["plan"].setdefault("tasks", {})
    for task_id, status in PLAN_TASK_BOOTSTRAP.items():
        task_info = plan_index["tasks_by_id"].get(task_id)
        if not task_info:
            continue
        task_overlay.setdefault(
            task_id,
            {
                "status": status,
                "updated_at": BOOTSTRAP_UPDATED_AT,
                "summary": task_info["title"],
                "title": task_info["title"],
                "milestone": task_info["milestone"],
            },
        )

    tbd_overlay = state["plan"].setdefault("tbds", {})
    for tbd_id, status in PLAN_TBD_BOOTSTRAP.items():
        tbd_info = plan_index["tbds_by_id"].get(tbd_id)
        if not tbd_info:
            continue
        tbd_overlay.setdefault(
            tbd_id,
            {
                "status": status,
                "updated_at": BOOTSTRAP_UPDATED_AT,
                "summary": tbd_info["title"],
                "title": tbd_info["title"],
                "affects_milestones": tbd_info["affects_milestones"],
            },
        )


def summarize_milestone(plan_index: dict, state: dict, milestone: str) -> dict:
    task_ids = plan_index["milestones"].get(milestone, [])
    total = len(task_ids)
    counts = {"completed": 0, "in_progress": 0, "blocked": 0}

    for task_id in task_ids:
        status = state["plan"]["tasks"].get(task_id, {}).get("status", "todo")
        if status in counts:
            counts[status] += 1

    if total > 0 and counts["completed"] == total:
        aggregate = "completed"
    elif counts["in_progress"] > 0:
        aggregate = "in_progress"
    elif counts["blocked"] > 0 and counts["completed"] == 0:
        aggregate = "blocked"
    elif counts["completed"] > 0 or counts["blocked"] > 0:
        aggregate = "in_progress"
    else:
        aggregate = "not_started"

    return {
        "status": aggregate,
        "completed": counts["completed"],
        "in_progress": counts["in_progress"],
        "blocked": counts["blocked"],
        "total": total,
    }


def format_log_entry(entry: dict) -> str:
    plan_ref = entry.get("plan_ref")
    summary = entry.get("summary") or ""
    if plan_ref and summary:
        display = f"[{plan_ref}] {summary}"
    elif plan_ref:
        display = f"[{plan_ref}]"
    else:
        display = summary
    return f"- {entry.get('time', '未记录')} | {entry.get('phase', '未知阶段')} | {display}"


def render(state: dict, plan_index: dict) -> str:
    current = state["current"]
    note = current.get("note") or DEFAULT_NOTE
    current_plan_ref = current.get("plan_ref") or "无"
    current_summary = current.get("summary") or "未记录"

    lines = [
        "# 执行状态文档",
        "",
        "## 当前任务",
        f"- 状态：{current.get('status', '未开始')}",
        f"- 计划编号：{current_plan_ref}",
        f"- 最近开始：{current.get('started_at') or '未记录'}",
        f"- 最近完成：{current.get('finished_at') or '未记录'}",
        f"- 最近验证：{current.get('last_verification', '未记录')}",
        f"- 最近任务摘要：{current_summary}",
        f"- 备注：{note}",
        "",
        "## dev-plan 子任务状态",
    ]

    for milestone in sorted(plan_index["milestones"], key=lambda item: int(item[1:])):
        milestone_title = plan_index["milestone_titles"].get(milestone, "")
        title_suffix = f" {milestone_title}" if milestone_title else ""
        lines.append(f"### {milestone}{title_suffix}")
        for task_id in sorted(plan_index["milestones"].get(milestone, []), key=sort_task_ref):
            task_info = plan_index["tasks_by_id"].get(task_id, {})
            overlay = state["plan"]["tasks"].get(task_id, {})
            status = overlay.get("status", "todo")
            updated_at = overlay.get("updated_at", "未开始")
            title = task_info.get("title", "未知任务")
            lines.append(f"- [{task_id}] {title} — status: `{status}` · updated: {updated_at}")
        lines.append("")

    if lines[-1] == "":
        lines.pop()

    lines.extend(["", "## 里程碑汇总"])
    for milestone in sorted(plan_index["milestones"], key=lambda item: int(item[1:])):
        summary = summarize_milestone(plan_index, state, milestone)
        milestone_title = plan_index["milestone_titles"].get(milestone, "")
        title_suffix = f" {milestone_title}" if milestone_title else ""
        lines.append(
            f"- {milestone}{title_suffix} — status: `{summary['status']}` · completed {summary['completed']} / total {summary['total']} · blocked {summary['blocked']} · in_progress {summary['in_progress']}"
        )

    lines.extend(["", "## TBD 状态"])
    tbd_entries = state["plan"]["tbds"]
    if tbd_entries:
        for tbd_id in sorted(tbd_entries, key=sort_tbd_ref):
            entry = tbd_entries[tbd_id]
            title = entry.get("title") or plan_index["tbds_by_id"].get(tbd_id, {}).get("title", "未知 TBD")
            affects = entry.get("affects_milestones") or plan_index["tbds_by_id"].get(tbd_id, {}).get("affects_milestones", [])
            affects_text = "、".join(affects) if affects else "未记录"
            lines.append(
                f"- [{tbd_id}] {title} — status: `{entry.get('status', 'open')}` · affects: {affects_text} · updated: {entry.get('updated_at', '未记录')}"
            )
    else:
        lines.append("- 暂无 TBD 状态变更")

    hook_errors = state.get("meta", {}).get("hook_errors", [])
    if hook_errors:
        lines.extend(["", "## Hook 异常"])
        lines.extend(f"- {message}" for message in hook_errors)

    task_board = state.get("meta", {}).get("task_board", TASK_BOARD_DEFAULT)
    lines.extend(["", "## 当前任务清单"])
    lines.extend(f"- {item}" for item in task_board)

    lines.extend(["", "## 执行日志"])
    if state["logs"]:
        lines.extend(format_log_entry(entry) for entry in state["logs"])
    else:
        lines.append("- 暂无记录")

    serialized_state = json.dumps(state, ensure_ascii=False, indent=2)
    lines.extend(["", STATE_MARKER_START, serialized_state, "-->"])
    return "\n".join(lines) + "\n"


def main() -> int:
    payload = read_payload()
    state = parse_existing()

    if not DEV_PLAN_FILE.exists():
        record_hook_error(state, f"未找到 dev-plan 真源：{DEV_PLAN_FILE}")

    plan_index = parse_dev_plan()
    bootstrap_plan_overlay(state, plan_index)
    apply_phase(state, payload, plan_index, now_string())
    STATUS_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATUS_FILE.write_text(render(state, plan_index), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
