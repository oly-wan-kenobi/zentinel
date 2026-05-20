#!/usr/bin/env python3
"""Validate zentinel's autonomous task system.

This script intentionally uses only the Python standard library so it can run
in bootstrap environments before project dependencies exist.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QUEUE_JSON = ROOT / "tasks" / "queue.json"
STATUS_JSON = ROOT / "tasks" / "status.json"
QUEUE_MD = ROOT / "tasks" / "QUEUE.md"
STATUS_MD = ROOT / "tasks" / "STATUS.md"
SCHEMA_REGISTRY_MD = ROOT / "docs" / "SCHEMA_REGISTRY.md"
ADR_DIR = ROOT / "docs" / "adr"
GAP_REGISTRY_DIR = ROOT / "tests" / "coverage-gaps"
AGENTS_DIR = ROOT / ".agents"
CLAUDE_DIR = ROOT / ".claude"

REQUIRED_TASK_SECTIONS = [
    "## Goal",
    "## Scope",
    "## Files allowed to modify",
    "## Files forbidden to modify",
    "## Required tests",
    "## Acceptance criteria",
    "## Non-goals",
    "## Suggested implementation approach",
    "## Dogfooding implications",
    "## Follow-up tasks",
]

TASK_ID_RE = re.compile(r"^[0-9]{3}$")
TASK_FILE_RE = re.compile(r"^tasks/[0-9]{3}-.+\.md$")
TASK_REF_RE = re.compile(r"`((?:tasks/)?[0-9]{3}-[^`]+\.md)`")
NO_FOLLOW_UP_RE = re.compile(r"^None predefined\.")
ORDER_RE = re.compile(r"^[0-9]{3}(?:\.[0-9]+)*$")
QUEUE_ROW_RE = re.compile(r"^\| ([0-9]{3}(?:\.[0-9]+)*) \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|$", re.MULTILINE)
INVARIANT_RE = re.compile(r"^\*\*(I-[0-9]{3})\.", re.MULTILINE)
FAILURE_MODE_RE = re.compile(r"^\*\*(F-[0-9]{3})\.", re.MULTILINE)
ADR_INDEX_RE = re.compile(r"^\| (ADR-[0-9]{4}) \| \[[^\]]+\]\(([^)]+)\) \| ([^|]+) \| ([^|]+) \|$", re.MULTILINE)

TASK_CONTROL_FILES = {
    "tasks/QUEUE.md",
    "tasks/queue.json",
    "tasks/STATUS.md",
    "tasks/status.json",
}

PIPELINE_ARTIFACT_EXCEPTION = "artifacts/pipeline/<active-task-id>/**"
GAP_REGISTRY_EXCEPTION = "tests/coverage-gaps/<registry>.v1.json"

GOVERNANCE_FILES = [
    "docs/VISION.md",
    "docs/NON_GOALS.md",
    "docs/GLOSSARY.md",
    "docs/INVARIANTS.md",
    "docs/HARNESS.md",
    "docs/DISCIPLINE.md",
    "docs/STYLE.md",
    "docs/FAILURE_MODES.md",
    "docs/GAP_REGISTRIES.md",
    "docs/adr/README.md",
]

REQUIRED_AGENT_FILES = [
    ".agents/README.md",
    ".agents/ORCHESTRATOR.md",
    ".agents/roles/phase-planner.md",
    ".agents/roles/task-queue-manager.md",
    ".agents/roles/planner.md",
    ".agents/roles/test-author.md",
    ".agents/roles/test-reviewer.md",
    ".agents/roles/implementer.md",
    ".agents/roles/implementation-reviewer.md",
    ".agents/roles/mutation-agent.md",
    ".agents/roles/mutation-triage-agent.md",
    ".agents/roles/property-test-agent.md",
    ".agents/roles/doctest-agent.md",
    ".agents/roles/architecture-reviewer.md",
    ".agents/roles/verifier.md",
    ".agents/workflows/task-plan.md",
    ".agents/workflows/task-test.md",
    ".agents/workflows/task-implement.md",
    ".agents/workflows/task-verify.md",
    ".agents/workflows/task-done.md",
    ".agents/workflows/sync.md",
]

SCHEMA_REGISTRY_PAIRS = [
    ("zentinel.report.v1", "schemas/report.v1.schema.json"),
    ("zentinel.ai.prompt.v1", "schemas/ai.prompt.v1.schema.json"),
    ("zentinel.ai.context.v1", "schemas/ai.context.v1.schema.json"),
    ("zentinel.ai.explain.response.v1", "schemas/ai.explain.response.v1.schema.json"),
    ("zentinel.ai.suggest.response.v1", "schemas/ai.suggest.response.v1.schema.json"),
    ("zentinel.ai.review_tests.response.v1", "schemas/ai.review_tests.response.v1.schema.json"),
    ("zentinel.doctest.report.v1", "schemas/doctest.report.v1.schema.json"),
    ("zentinel.ai.doctest.context.v1", "schemas/ai.doctest.context.v1.schema.json"),
    ("zentinel.ai.doctest.suggest.response.v1", "schemas/ai.doctest.suggest.response.v1.schema.json"),
    ("zentinel.ai.doctest.snapshot_review.response.v1", "schemas/ai.doctest.snapshot_review.response.v1.schema.json"),
    ("zentinel.pipeline.handoff.v1", "schemas/pipeline.handoff.v1.schema.json"),
    ("zentinel.pipeline.active_lock.v1", "schemas/pipeline.active_lock.v1.schema.json"),
    ("zentinel.pipeline.context.v1", "schemas/pipeline.context.v1.schema.json"),
    ("zentinel.pipeline.stale_context.v1", "schemas/pipeline.stale_context.v1.schema.json"),
    ("zentinel.pipeline.verification.v1", "schemas/pipeline.verification.v1.schema.json"),
    ("zentinel.pipeline.escalation.v1", "schemas/pipeline.escalation.v1.schema.json"),
    ("zentinel.tasks.queue.v1", "tasks/schema/queue.v1.schema.json"),
    ("zentinel.tasks.status.v1", "tasks/schema/status.v1.schema.json"),
]


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def load_json(path: Path, errors: list[str]) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(errors, f"missing file: {path.relative_to(ROOT)}")
    except json.JSONDecodeError as exc:
        fail(errors, f"invalid JSON in {path.relative_to(ROOT)}: {exc}")
    return {}


def require(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        fail(errors, message)


def task_order(task: dict[str, object]) -> str:
    order = task.get("order")
    if isinstance(order, str):
        return order
    task_id = task.get("id")
    return task_id if isinstance(task_id, str) else ""


def order_key(order: str) -> tuple[int, ...]:
    return tuple(int(part) for part in order.split("."))


def validate_queue(queue: object, errors: list[str]) -> list[dict[str, object]]:
    require(isinstance(queue, dict), errors, "queue.json must contain an object")
    if not isinstance(queue, dict):
        return []

    require(queue.get("schema_version") == "zentinel.tasks.queue.v1", errors, "queue.json schema_version mismatch")
    require(queue.get("ordering") == "sequential", errors, "queue.json ordering must be sequential")

    tasks = queue.get("tasks")
    require(isinstance(tasks, list) and len(tasks) > 0, errors, "queue.json tasks must be a non-empty array")
    if not isinstance(tasks, list):
        return []

    seen_ids: set[str] = set()
    seen_orders: set[str] = set()
    previous_order: tuple[int, ...] | None = None
    normalized: list[dict[str, object]] = []

    for index, task in enumerate(tasks):
        require(isinstance(task, dict), errors, f"task at index {index} must be an object")
        if not isinstance(task, dict):
            continue

        task_id = task.get("id")
        require(isinstance(task_id, str) and TASK_ID_RE.match(task_id) is not None, errors, f"task at index {index} has invalid id")
        if not isinstance(task_id, str):
            continue

        require(task_id not in seen_ids, errors, f"duplicate task id {task_id}")
        seen_ids.add(task_id)

        explicit_order = task.get("order")
        require(explicit_order is None or (isinstance(explicit_order, str) and ORDER_RE.match(explicit_order) is not None), errors, f"task {task_id} has invalid order")
        task_order_value = task_order(task)
        require(ORDER_RE.match(task_order_value) is not None, errors, f"task {task_id} has invalid effective order")
        require(task_order_value not in seen_orders, errors, f"duplicate task order {task_order_value}")
        seen_orders.add(task_order_value)
        current_order = order_key(task_order_value)
        require(previous_order is None or current_order > previous_order, errors, f"task {task_id} order {task_order_value} is not after the previous task order")
        previous_order = current_order

        file_value = task.get("file")
        require(isinstance(file_value, str) and TASK_FILE_RE.match(file_value) is not None, errors, f"task {task_id} has invalid file path")
        if isinstance(file_value, str):
            require((ROOT / file_value).is_file(), errors, f"task {task_id} file does not exist: {file_value}")
            require(file_value.startswith(f"tasks/{task_id}-"), errors, f"task {task_id} file name does not start with id")

        state = task.get("state")
        require(state in {"queued", "active", "blocked", "implemented", "verified", "complete", "superseded"}, errors, f"task {task_id} has invalid state")

        deps = task.get("dependencies")
        require(isinstance(deps, list), errors, f"task {task_id} dependencies must be an array")
        if isinstance(deps, list):
            for dep in deps:
                require(isinstance(dep, str) and TASK_ID_RE.match(dep) is not None, errors, f"task {task_id} has invalid dependency {dep!r}")

        for key in ("allowed_files", "forbidden_files"):
            value = task.get(key)
            require(isinstance(value, list) and all(isinstance(item, str) and item for item in value), errors, f"task {task_id} {key} must be a non-empty string array")

        normalized.append(task)

    task_by_id = {task["id"]: task for task in normalized if isinstance(task.get("id"), str)}
    for task in normalized:
        task_id = task.get("id")
        deps = task.get("dependencies")
        if not isinstance(task_id, str) or not isinstance(deps, list):
            continue
        for dep in deps:
            if not isinstance(dep, str) or TASK_ID_RE.match(dep) is None:
                continue
            dep_task = task_by_id.get(dep)
            require(dep_task is not None, errors, f"task {task_id} dependency {dep} is not known")
            if dep_task is not None:
                require(order_key(task_order(dep_task)) < order_key(task_order(task)), errors, f"task {task_id} dependency {dep} must have an earlier execution order")

    previous_non_superseded: dict[str, object] | None = None
    for task in normalized:
        if task.get("state") == "superseded":
            continue

        task_id = task.get("id")
        deps = task.get("dependencies")
        previous_id = previous_non_superseded.get("id") if previous_non_superseded is not None else None
        if previous_non_superseded is not None and isinstance(task_id, str) and isinstance(deps, list):
            require(
                isinstance(previous_id, str) and previous_id in deps,
                errors,
                f"task {task_id} must directly depend on immediately previous non-superseded execution-order task {previous_id}",
            )

        previous_non_superseded = task

    release_index = next((index for index, task in enumerate(normalized) if task.get("file") == "tasks/060-release-acceptance-verification.md"), None)
    if release_index is not None:
        for later in normalized[release_index + 1:]:
            later_id = later.get("id")
            require(later.get("state") == "superseded", errors, f"release acceptance task 060 must be the final non-superseded execution-order task; task {later_id} follows it")

    return normalized


def validate_status(status: object, tasks: list[dict[str, object]], errors: list[str]) -> None:
    require(isinstance(status, dict), errors, "status.json must contain an object")
    if not isinstance(status, dict):
        return

    require(status.get("schema_version") == "zentinel.tasks.status.v1", errors, "status.json schema_version mismatch")

    task_ids = [task["id"] for task in tasks if isinstance(task.get("id"), str)]
    task_by_id = {task["id"]: task for task in tasks if isinstance(task.get("id"), str)}

    active_states = [task["id"] for task in tasks if task.get("state") == "active"]
    current_states = [task["id"] for task in tasks if task.get("state") in {"active", "implemented", "verified"}]
    require(len(active_states) <= 1, errors, "only one task may be active")
    require(len(current_states) <= 1, errors, "only one task may be active, implemented, or verified pending completion")

    active_task = status.get("active_task")
    require(active_task is None or (isinstance(active_task, str) and active_task in task_by_id), errors, "status.json active_task must be null or a known task id")
    if current_states:
        require(active_task == current_states[0], errors, "status active_task must match the current active/implemented/verified queue state")
    else:
        require(active_task is None, errors, "status active_task must be null when no task is active, implemented, or verified")

    completed = status.get("completed_tasks")
    require(isinstance(completed, list), errors, "status completed_tasks must be an array")
    if isinstance(completed, list):
        for task_id in completed:
            require(isinstance(task_id, str) and task_id in task_by_id, errors, f"completed task {task_id!r} is not known")
            if isinstance(task_id, str) and task_id in task_by_id:
                require(task_by_id[task_id].get("state") == "complete", errors, f"completed task {task_id} must have queue state complete")

    blocked = status.get("blocked_tasks")
    require(isinstance(blocked, list), errors, "status blocked_tasks must be an array")
    if isinstance(blocked, list):
        for task_id in blocked:
            require(isinstance(task_id, str) and task_id in task_by_id, errors, f"blocked task {task_id!r} is not known")
            if isinstance(task_id, str) and task_id in task_by_id:
                require(task_by_id[task_id].get("state") == "blocked", errors, f"blocked task {task_id} must have queue state blocked")

    for task in tasks:
        task_id = task.get("id")
        state = task.get("state")
        deps = task.get("dependencies")
        if not isinstance(task_id, str) or not isinstance(deps, list):
            continue
        if state not in {"active", "implemented", "verified", "complete"}:
            continue
        for dep in deps:
            if isinstance(dep, str) and dep in task_by_id:
                require(task_by_id[dep].get("state") == "complete", errors, f"task {task_id} state {state} requires dependency {dep} to be complete")

    next_task = status.get("next_task")
    completed_ids = {task["id"] for task in tasks if task.get("state") == "complete"}
    ready_ids = [
        task["id"]
        for task in tasks
        if task.get("state") == "queued"
        and isinstance(task.get("dependencies"), list)
        and all(isinstance(dep, str) and dep in completed_ids for dep in task.get("dependencies", []))
    ]
    expected_next = current_states[0] if current_states else (ready_ids[0] if ready_ids else None)
    require(next_task == expected_next, errors, f"status next_task must be current in-progress task or first dependency-ready queued task {expected_next!r}")

    require(isinstance(status.get("last_validation"), dict), errors, "status last_validation must be an object")
    require(isinstance(status.get("history"), list), errors, "status history must be an array")


def validate_task_markdown(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_files = {task.get("file") for task in tasks if isinstance(task.get("file"), str)}
    task_by_file = {task.get("file"): task for task in tasks if isinstance(task.get("file"), str)}

    for task in tasks:
        task_id = task.get("id")
        file_value = task.get("file")
        if not isinstance(task_id, str) or not isinstance(file_value, str):
            continue
        path = ROOT / file_value
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        require(text.startswith(f"# {task_id} "), errors, f"{file_value} heading must start with '# {task_id} '")
        require("Sequential guard:" in text, errors, f"{file_value} missing sequential guard")
        for section in REQUIRED_TASK_SECTIONS:
            require(section in text, errors, f"{file_value} missing section {section}")
        require("Add a failing" in text or "Add failing" in text or "First add a failing" in text, errors, f"{file_value} must explicitly require a failing test")

        allowed = task.get("allowed_files")
        forbidden = task.get("forbidden_files")
        if isinstance(allowed, list):
            require(section_bullets(text, "Files allowed to modify") == allowed, errors, f"{file_value} allowed files must match queue.json exactly")
        if isinstance(forbidden, list):
            require(section_bullets(text, "Files forbidden to modify") == forbidden, errors, f"{file_value} forbidden files must match queue.json exactly")
            for task_control_file in TASK_CONTROL_FILES:
                require(task_control_file not in forbidden, errors, f"{file_value} must not forbid task-control file {task_control_file}")

        deps = task.get("dependencies")
        sequential_guard = next((line for line in text.splitlines() if line.startswith("Sequential guard:")), "")
        if isinstance(deps, list):
            for dep in deps:
                if isinstance(dep, str):
                    require(dep in sequential_guard, errors, f"{file_value} sequential guard must reference dependency {dep}")

        for item in follow_up_items(text):
            if TASK_REF_RE.search(item) is not None:
                continue
            require(NO_FOLLOW_UP_RE.match(item) is not None, errors, f"{file_value} follow-up bullet must reference a concrete queued task or say 'None predefined.': {item}")

        for ref in follow_up_refs(text):
            normalized = ref if ref.startswith("tasks/") else f"tasks/{ref}"
            require(normalized in task_files, errors, f"{file_value} follow-up task reference does not exist in queue.json: {ref}")
            if normalized in task_files:
                ref_task = task_by_file.get(normalized)
                if isinstance(ref_task, dict):
                    require(
                        order_key(task_order(ref_task)) > order_key(task_order(task)),
                        errors,
                        f"{file_value} follow-up task {ref} must have a later execution order",
                    )


def section_bullets(text: str, heading: str) -> list[str]:
    match = re.search(rf"^## {re.escape(heading)}\n\n(?P<body>.*?)(?=\n## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        return []
    bullets: list[str] = []
    for line in match.group("body").splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        item = stripped[2:].strip()
        if item.startswith("`") and item.endswith("`"):
            item = item[1:-1]
        bullets.append(item)
    return bullets


def follow_up_refs(text: str) -> list[str]:
    match = re.search(r"^## Follow-up tasks\n\n(?P<body>.*?)(?=\n## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        return []
    return [match.group(1) for match in TASK_REF_RE.finditer(match.group("body"))]


def follow_up_items(text: str) -> list[str]:
    match = re.search(r"^## Follow-up tasks\n\n(?P<body>.*?)(?=\n## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        return []
    items: list[str] = []
    for line in match.group("body").splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            items.append(stripped[2:].strip())
    return items


def validate_markdown_queue(tasks: list[dict[str, object]], errors: list[str]) -> None:
    require(QUEUE_MD.is_file(), errors, "tasks/QUEUE.md is missing")
    require(STATUS_MD.is_file(), errors, "tasks/STATUS.md is missing")
    if not QUEUE_MD.is_file():
        return
    queue_text = QUEUE_MD.read_text(encoding="utf-8")
    rows = {match.group(2): {"order": match.group(1), "state": match.group(3).strip(), "phase": match.group(4).strip()} for match in QUEUE_ROW_RE.finditer(queue_text)}
    for task in tasks:
        task_id = task.get("id")
        file_value = task.get("file")
        if isinstance(task_id, str) and isinstance(file_value, str):
            expected_order = task_order(task)
            require(f"| {expected_order} | `{file_value}` |" in queue_text, errors, f"tasks/QUEUE.md missing task {task_id}")
            row = rows.get(file_value)
            require(row is not None, errors, f"tasks/QUEUE.md missing parseable row for task {task_id}")
            if row is not None:
                require(row["order"] == expected_order, errors, f"tasks/QUEUE.md task {task_id} order must match queue.json")
                require(row["state"] == task.get("state"), errors, f"tasks/QUEUE.md task {task_id} status must match queue.json")
                require(row["phase"] == str(task.get("phase")), errors, f"tasks/QUEUE.md task {task_id} phase must match queue.json")


def validate_markdown_status(status: object, tasks: list[dict[str, object]], errors: list[str]) -> None:
    if not isinstance(status, dict) or not STATUS_MD.is_file():
        return
    task_by_id = {task["id"]: task for task in tasks if isinstance(task.get("id"), str)}
    text = STATUS_MD.read_text(encoding="utf-8")
    match = re.search(r"^## Current State\n\n(?P<body>.*?)(?=\n## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    require(match is not None, errors, "tasks/STATUS.md missing Current State section")
    if match is None:
        return
    values: dict[str, str] = {}
    for line in match.group("body").splitlines():
        row = line.strip()
        if not row.startswith("|") or row.startswith("| ---") or row.startswith("| Field "):
            continue
        parts = [part.strip() for part in row.strip("|").split("|")]
        if len(parts) == 2:
            values[parts[0]] = parts[1]

    active_value = values.get("Active task")
    require(active_value is not None, errors, "tasks/STATUS.md Current State missing Active task row")
    active_task = status.get("active_task")
    if active_value is not None:
        if active_task is None:
            require(active_value.lower() == "none", errors, "tasks/STATUS.md Active task must be none when status.json active_task is null")
        else:
            require(isinstance(active_task, str) and active_task in active_value, errors, "tasks/STATUS.md Active task must match status.json active_task")

    next_value = values.get("Next task")
    require(next_value is not None, errors, "tasks/STATUS.md Current State missing Next task row")
    next_task = status.get("next_task")
    if next_value is not None:
        if next_task is None:
            require(next_value.lower() == "none", errors, "tasks/STATUS.md Next task must be none when status.json next_task is null")
        else:
            task = task_by_id.get(next_task)
            expected_file = task.get("file") if isinstance(task, dict) else None
            require(isinstance(next_task, str) and (next_task in next_value or (isinstance(expected_file, str) and expected_file in next_value)), errors, "tasks/STATUS.md Next task must match status.json next_task")


def validate_schema_files(errors: list[str]) -> None:
    required = [
        "schemas/report.v1.schema.json",
        "schemas/ai.context.v1.schema.json",
        "schemas/ai.explain.response.v1.schema.json",
        "schemas/ai.suggest.response.v1.schema.json",
        "schemas/ai.review_tests.response.v1.schema.json",
        "tasks/schema/queue.v1.schema.json",
        "tasks/schema/status.v1.schema.json",
    ]
    for rel in required:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing schema file {rel}")
        if path.is_file():
            load_json(path, errors)


def validate_schema_registry(errors: list[str]) -> None:
    require(SCHEMA_REGISTRY_MD.is_file(), errors, "docs/SCHEMA_REGISTRY.md is missing")
    if not SCHEMA_REGISTRY_MD.is_file():
        return
    text = SCHEMA_REGISTRY_MD.read_text(encoding="utf-8")
    for version, file_path in SCHEMA_REGISTRY_PAIRS:
        require(version in text, errors, f"schema registry missing version {version}")
        require(file_path in text, errors, f"schema registry missing file {file_path}")


def validate_governance_files(errors: list[str]) -> None:
    for rel in GOVERNANCE_FILES:
        require((ROOT / rel).is_file(), errors, f"missing governance file {rel}")


def validate_agent_layer(errors: list[str]) -> None:
    require(AGENTS_DIR.is_dir(), errors, "missing Codex agent directory .agents")
    require(not CLAUDE_DIR.exists(), errors, "Claude-specific .claude directory must not exist in zentinel")
    for rel in REQUIRED_AGENT_FILES:
        require((ROOT / rel).is_file(), errors, f"missing Codex agent file {rel}")
    orchestrator = ROOT / ".agents" / "ORCHESTRATOR.md"
    if orchestrator.is_file():
        text = orchestrator.read_text(encoding="utf-8")
        require(
            "Only one task may be `active`, `implemented`, or `verified` pending completion at a time." in text,
            errors,
            ".agents/ORCHESTRATOR.md must include active/implemented/verified single-task wording",
        )
        require(
            "More than one task is active, implemented, or verified pending completion." in text,
            errors,
            ".agents/ORCHESTRATOR.md stop conditions must include verified tasks",
        )
        require(
            "Only one task may be `active` or `implemented` at a time." not in text,
            errors,
            ".agents/ORCHESTRATOR.md contains stale active/implemented-only wording",
        )


def validate_pipeline_contracts(errors: list[str]) -> None:
    exception_files = [
        "AGENTS.md",
        "tasks/QUEUE.md",
        "docs/AGENT_GUIDE.md",
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md",
        ".agents/README.md",
    ]
    for rel in exception_files:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing pipeline exception contract file {rel}")
        if path.is_file():
            text = path.read_text(encoding="utf-8")
            require(PIPELINE_ARTIFACT_EXCEPTION in text, errors, f"{rel} must document the task-scoped pipeline artifact exception")

    gap_exception_files = [
        "AGENTS.md",
        "tasks/QUEUE.md",
        "docs/AGENT_GUIDE.md",
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md",
        ".agents/README.md",
        "docs/GAP_REGISTRIES.md",
    ]
    for rel in gap_exception_files:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing gap registry exception contract file {rel}")
        if path.is_file():
            text = path.read_text(encoding="utf-8")
            require(GAP_REGISTRY_EXCEPTION in text, errors, f"{rel} must document the row-scoped gap registry exception")

    artifacts = ROOT / "docs" / "PIPELINE_ARTIFACTS.md"
    if artifacts.is_file():
        text = artifacts.read_text(encoding="utf-8")
        require("handoffs/<step>-<role>.json" in text, errors, "docs/PIPELINE_ARTIFACTS.md must use JSON handoff naming")
        require("handoffs/<step>-<role>.md" not in text, errors, "docs/PIPELINE_ARTIFACTS.md must not make Markdown handoffs canonical")
        require("verification/report.json" in text, errors, "docs/PIPELINE_ARTIFACTS.md must list JSON verification artifacts")

    handoffs = ROOT / "docs" / "HANDOFF_CONTRACTS.md"
    if handoffs.is_file():
        text = handoffs.read_text(encoding="utf-8")
        require("JSON handoffs are canonical" in text or "JSON handoff is the canonical" in text, errors, "docs/HANDOFF_CONTRACTS.md must make JSON handoffs canonical")
        require("01-test-author.json" in text, errors, "docs/HANDOFF_CONTRACTS.md must list deterministic JSON handoff names")

    orchestration = ROOT / "docs" / "ORCHESTRATION_SPEC.md"
    if orchestration.is_file():
        text = orchestration.read_text(encoding="utf-8")
        require("handoffs/*.json" in text, errors, "docs/ORCHESTRATION_SPEC.md must persist JSON handoffs")
        require("handoffs/*.md" not in text, errors, "docs/ORCHESTRATION_SPEC.md must not require Markdown handoffs as canonical state")

    metadata_task = ROOT / "tasks" / "063-pipeline-metadata-validator.md"
    if metadata_task.is_file():
        text = metadata_task.read_text(encoding="utf-8")
        require("schema subset validator" in text, errors, "tasks/063-pipeline-metadata-validator.md must define the pipeline schema subset validator scope")
        require("full Draft 2020-12" in text or "Full Draft 2020-12" in text, errors, "tasks/063-pipeline-metadata-validator.md must explicitly avoid claiming full Draft 2020-12 validation")

    if SCHEMA_REGISTRY_MD.is_file():
        text = SCHEMA_REGISTRY_MD.read_text(encoding="utf-8")
        require("project-owned schema subset validator" in text, errors, "docs/SCHEMA_REGISTRY.md must document the pipeline schema subset validator")


def validate_task_order_contracts(errors: list[str]) -> None:
    contracts = [
        "AGENTS.md",
        "tasks/QUEUE.md",
        "docs/AGENT_GUIDE.md",
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md",
        "docs/SEQUENTIAL_EXECUTION_POLICY.md",
    ]
    for rel in contracts:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task order contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        require("execution order" in text or "execution `order`" in text, errors, f"{rel} must refer to execution order")
        require("`order`" in text, errors, f"{rel} must document explicit task order keys")
    queue_text = QUEUE_MD.read_text(encoding="utf-8") if QUEUE_MD.is_file() else ""
    require("next unused three-digit ID" in queue_text, errors, "tasks/QUEUE.md must document stable IDs for prerequisite insertion")


def validate_protocol_startup_order(errors: list[str]) -> None:
    """Guard the read-before-active startup contract for autonomous agents."""
    expected_phrases = {
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Read the selected task file and required docs from `AGENTS.md` before marking it active.",
            "Mark it `active` in `tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, and `tasks/STATUS.md`.",
        ],
        "docs/AGENT_GUIDE.md": [
            "reading the selected task file and required docs from `AGENTS.md`",
            "marking it active in `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`",
        ],
        "tasks/QUEUE.md": [
            "Read the selected task file and required docs before marking the task `active`.",
            "Mark the task `active` in `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` before editing implementation files.",
        ],
    }

    for rel, phrases in expected_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing startup-order contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain startup-order phrase '{phrase}'")
        first = text.find(phrases[0])
        second = text.find(phrases[1])
        require(first != -1 and second != -1 and first < second, errors, f"{rel} must read task docs before marking a task active")


def validate_same_file_exclusion_sequence(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    required = ["009", "010", "018", "019", "020"]
    for task_id in required:
        require(task_id in task_by_id, errors, f"task {task_id} must exist for same-file exclusion sequencing")
    if not all(task_id in task_by_id for task_id in required):
        return

    order_009 = order_key(task_order(task_by_id["009"]))
    order_010 = order_key(task_order(task_by_id["010"]))
    order_019 = order_key(task_order(task_by_id["019"]))
    require(order_009 < order_019 < order_010, errors, "task 019 same-file exclusion must execute after task 009 and before task 010")

    deps_010 = task_by_id["010"].get("dependencies")
    require(isinstance(deps_010, list) and "019" in deps_010, errors, "task 010 must depend on task 019 same-file exclusion")

    deps_020 = task_by_id["020"].get("dependencies")
    require(isinstance(deps_020, list) and "018" in deps_020 and "019" in deps_020, errors, "task 020 must depend on both task 018 report rendering and task 019 same-file exclusion")

    required_phrases = {
        "tasks/009-ast-candidate-ordering.md": "tasks/019-same-file-test-exclusion.md",
        "tasks/010-arithmetic-mutators.md": "task 019",
        "tasks/018-report-renderers.md": "tasks/020-test-selection-same-file.md",
        "tasks/019-same-file-test-exclusion.md": "task 009",
        "tasks/020-test-selection-same-file.md": "tasks 018 and 019",
    }
    for rel, phrase in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing same-file sequencing file {rel}")
        if path.is_file():
            require(phrase in path.read_text(encoding="utf-8"), errors, f"{rel} must contain same-file sequencing phrase '{phrase}'")


def validate_mutation_gate_availability_policy(errors: list[str]) -> None:
    required_phrases = {
        "docs/MUTATION_GATE_POLICY.md": [
            "Task `043` is the mutation-gate availability cutover.",
            "Before task `043` is complete, mutation-gate skip reasons must use `pre-gate unavailable`",
            "After task `043` is complete, mutation gate is mandatory for mutation-testable tasks",
            "only when the active scope is mutation-testable",
        ],
        "tasks/043-mutation-gate.md": [
            "Task `043` establishes the mutation-gate availability cutover",
            "`pre-gate unavailable` skip reason is no longer allowed for mutation-testable tasks after this task is complete",
        ],
    }

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing mutation-gate availability file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain mutation-gate availability phrase '{phrase}'")


def validate_agent_execution_contracts(errors: list[str]) -> None:
    required_phrases = {
        ".agents/workflows/task-plan.md": ["first dependency-ready queued task by execution order"],
        ".agents/workflows/sync.md": ["first dependency-ready queued task by execution order", "active, implemented, or verified"],
        ".agents/roles/task-queue-manager.md": ["first dependency-ready queued task by execution order"],
        "docs/AGENT_ROLE_SPEC.md": ["active, implemented, or verified pending completion"],
    }
    stale_phrases = [
        "first queued task",
        "active or implemented pending verification",
    ]

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing agent execution contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain '{phrase}'")
        for phrase in stale_phrases:
            require(phrase not in text, errors, f"{rel} contains stale phrase '{phrase}'")


def validate_cli_contracts(errors: list[str]) -> None:
    cli_path = ROOT / "docs" / "CLI_SPEC.md"
    doctest_mutation_path = ROOT / "docs" / "DOCTEST_MUTATION_STRATEGY.md"
    ai_ux_path = ROOT / "docs" / "AI_ASSISTED_UX.md"
    task054_path = ROOT / "tasks" / "054-ai-advisory-commands.md"
    task055_path = ROOT / "tasks" / "055-ai-doctest-assistance.md"
    task067_path = ROOT / "tasks" / "067-ai-doctest-survivor-assistance.md"

    for path in [cli_path, doctest_mutation_path, ai_ux_path, task054_path, task055_path, task067_path]:
        require(path.is_file(), errors, f"missing CLI contract file {path.relative_to(ROOT)}")
    if not cli_path.is_file() or not doctest_mutation_path.is_file():
        return

    cli_text = cli_path.read_text(encoding="utf-8")
    doctest_mutation_text = doctest_mutation_path.read_text(encoding="utf-8")
    require("zentinel doctest explain <case-ref>" in cli_text, errors, "docs/CLI_SPEC.md must expose doctest explain as a user-facing command")
    require("zentinel doctest suggest <doc-path>" in cli_text, errors, "docs/CLI_SPEC.md must expose doctest suggest as a user-facing command")
    require("zentinel doctest review-snapshot <case-ref>" in cli_text, errors, "docs/CLI_SPEC.md must expose doctest review-snapshot as a user-facing command")
    require("zentinel doctest suggest-missing [--file <doc-path>]" in cli_text, errors, "docs/CLI_SPEC.md must expose doctest suggest-missing as a user-facing command")
    require("zentinel doctest explain-survivor <survivor-ref>" in cli_text, errors, "docs/CLI_SPEC.md must expose doctest explain-survivor as a user-facing command")
    require("<case-ref>" in cli_text, errors, "docs/CLI_SPEC.md must define doctest case references as <case-ref>")
    require("<mutant-ref>" in cli_text, errors, "docs/CLI_SPEC.md must define AI mutant references as <mutant-ref>")
    require("--ai-provider <disabled|stub|local|remote>" in cli_text, errors, "docs/CLI_SPEC.md must define AI provider option values")
    require("--report <path>" in cli_text, errors, "docs/CLI_SPEC.md must define AI report path option")
    require("zig-out/zentinel/report.json" in cli_text, errors, "docs/CLI_SPEC.md must define the default mutation AI report path")
    require("zig-out/zentinel/doctest/report.json" in cli_text, errors, "docs/CLI_SPEC.md must define the default doctest AI report path")
    require("Display IDs are scoped to the report" in cli_text, errors, "docs/CLI_SPEC.md must scope display IDs to the selected report")
    require("case anchor line" in cli_text, errors, "docs/CLI_SPEC.md must define doctest source refs as anchor-line selectors")
    require("--format <text|json|jsonl>" in doctest_mutation_text, errors, "docs/DOCTEST_MUTATION_STRATEGY.md must use --format for output selection")
    require("--report <text|json|jsonl>" not in doctest_mutation_text, errors, "docs/DOCTEST_MUTATION_STRATEGY.md must not use --report for doctest output format")

    if ai_ux_path.is_file():
        ai_ux_text = ai_ux_path.read_text(encoding="utf-8")
        require("zentinel doctest explain <case-ref>" in ai_ux_text, errors, "docs/AI_ASSISTED_UX.md must list doctest explain")
        require("zentinel doctest suggest <doc-path>" in ai_ux_text, errors, "docs/AI_ASSISTED_UX.md must list doctest suggest")
        require("zentinel doctest review-snapshot <case-ref>" in ai_ux_text, errors, "docs/AI_ASSISTED_UX.md must list doctest review-snapshot")
        require("zentinel doctest suggest-missing [--file <doc-path>]" in ai_ux_text, errors, "docs/AI_ASSISTED_UX.md must list doctest suggest-missing")
        require("zentinel doctest explain-survivor <survivor-ref>" in ai_ux_text, errors, "docs/AI_ASSISTED_UX.md must list doctest explain-survivor")

    if task054_path.is_file():
        task054_text = task054_path.read_text(encoding="utf-8")
        require("display IDs scoped to the selected report" in task054_text, errors, "tasks/054-ai-advisory-commands.md must require display-ID resolution tests")
        require("--ai-provider <disabled|stub|local|remote>" in task054_text, errors, "tasks/054-ai-advisory-commands.md must require AI provider option tests")

    if task055_path.is_file():
        task055_text = task055_path.read_text(encoding="utf-8")
        for required in ["src/cli.zig", "src/main.zig", "docs/CLI_SPEC.md", "schemas/ai.prompt.v1.schema.json", "test/ai_doctest_cli_test.zig"]:
            require(required in task055_text, errors, f"tasks/055-ai-doctest-assistance.md must allow {required}")
        require("zentinel doctest explain <case-ref>" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest explain CLI tests")
        require("zentinel doctest suggest <doc-path>" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest suggest CLI tests")
        require("zentinel doctest review-snapshot <case-ref>" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest review-snapshot CLI tests")
        require("zentinel doctest suggest-missing [--file <doc-path>]" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest suggest-missing CLI tests")

    if task067_path.is_file():
        task067_text = task067_path.read_text(encoding="utf-8")
        require("zentinel doctest explain-survivor <survivor-ref>" in task067_text, errors, "tasks/067-ai-doctest-survivor-assistance.md must require doctest explain-survivor CLI tests")
        require("ZNTL_DOCTEST_SURVIVOR_NOT_FOUND" in task067_text, errors, "tasks/067-ai-doctest-survivor-assistance.md must require unresolved survivor diagnostics")


def validate_doctest_identity_contracts(errors: list[str]) -> None:
    required_phrases = [
        ("docs/DOCTEST_SPEC.md", [
            "Duplicate unlabeled cases in the same file are invalid",
            "canonical anchor line",
            "block_refs",
            "occurrence indexes",
            "Doctest Case Kind Enum",
            "`docs_target` is an AI-only kind",
            "case.result.snapshot",
            "json_unordered",
        ]),
        ("docs/DOCTEST_ARCHITECTURE.md", [
            "`source_ref` is a case-level anchor",
            "block_refs",
            "Duplicate unlabeled cases in one file",
        ]),
        ("docs/GLOSSARY.md", [
            "Duplicate unlabeled identical cases",
            "Doctest mutation case ID",
            "case anchor line",
        ]),
        ("tasks/032-doctest-extraction.md", [
            "duplicate unlabeled identical cases",
            "anchor `source_ref`",
            "secondary `block_refs`",
        ]),
        ("tasks/035-cli-doctests.md", [
            "source-ref selectors resolve only the case anchor line",
            "secondary expectation blocks",
            "structured `command`, bounded `result`, `diagnostics`, and `advisory.ai` fields",
            "exact `case.kind` enum",
            "exact `case.result.snapshot` evidence",
        ]),
        ("tasks/061-doctest-mutate-stabilization.md", [
            "docs/DOCTEST_SPEC.md",
            "summary.mutation",
            "case.mutation",
            "dm_...",
            "ds_...",
            "survivor_ref",
        ]),
        ("tasks/067-ai-doctest-survivor-assistance.md", [
            "schema-extension test",
            "case.mutation.runner_evidence",
            "dm_...",
            "does not resolve killed, skipped, invalid, compile-error, compiler-crash, or timeout",
        ]),
        ("docs/DOCTEST_SPEC.md", [
            "`zentinel.doctest.report.v1` is the exact schema target",
            "case.advisory.ai",
            "Failure report rules",
            "Doctest Mutation Entry IDs",
            "Doctest Survivor Refs",
            "case.mutation",
            "summary.mutation",
            "dm_...",
            "canonical_mutation_case_bytes",
            "canonical_survivor_bytes",
            "Mutation-aware case entries must not reuse the ordinary `dt_...` value in `case.id`",
        ]),
        ("docs/DOCTEST_AI_INTEGRATION.md", [
            "case_failure",
            "docs_target",
            "snapshot_diff",
            "missing_doctests",
            "doctest_survivor",
            "Task `055` owns the first four variants",
            "Task `067` owns the deferred `doctest_survivor` variant",
            "docs_metadata",
            "runner_evidence",
            "zentinel doctest suggest-missing [--file <doc-path>]",
            "zentinel doctest explain-survivor <survivor-ref>",
            "case.result.snapshot",
        ]),
        ("docs/DOCTEST_POLICY.md", [
            "docs/DOCTEST_AI_INTEGRATION.md",
        ]),
        ("tasks/066-public-docs-doctest-coverage.md", [
            "docs/DOCTEST_AI_INTEGRATION.md",
            "one doctest AI JSON example",
        ]),
    ]
    for rel, phrases in required_phrases:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing doctest identity contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain doctest identity phrase '{phrase}'")


def validate_ai_contracts(errors: list[str]) -> None:
    explain_schema = ROOT / "schemas" / "ai.explain.response.v1.schema.json"
    data = load_json(explain_schema, errors) if explain_schema.is_file() else {}
    if isinstance(data, dict):
        defs = data.get("$defs")
        classification_values: list[object] = []
        if isinstance(defs, dict):
            classification = defs.get("classification")
            if isinstance(classification, dict):
                enum = classification.get("enum")
                if isinstance(enum, list):
                    classification_values = enum
        for label in [
            "doctest_output_mismatch",
            "doctest_invalid_example",
            "doctest_snapshot_wording_change",
            "doctest_assertion_missing",
            "doctest_survivor_missing_assertion",
        ]:
            require(label in classification_values, errors, f"AI explain response schema must allow doctest classification {label}")

    required_phrases = {
        "docs/AI_PROMPT_CONTRACTS.md": [
            "Doctest explain classifications",
            "doctest_output_mismatch",
            "registered AI context schema",
            "zentinel.ai.doctest.context.v1",
            "Task `055` must reject `explain_doctest_survivor`",
            "only task `067` may add that flow",
        ],
        "docs/AI_ASSISTED_UX.md": [
            "doctest_output_mismatch",
            "default redaction patterns are exactly",
            "do not persist suggestions or snapshot reviews by default",
        ],
        "docs/DOCTEST_AI_INTEGRATION.md": [
            "doctest-specific classification labels",
            "zentinel doctest review-snapshot <case-ref>",
            "zentinel doctest suggest-missing [--file <doc-path>]",
            "zentinel doctest explain-survivor <survivor-ref>",
            "Response schema target",
            "additionalProperties: false",
        ],
        "docs/CONFIG_SPEC.md": [
            '`redact_patterns` | list(string) | `["(?i)api[_-]?key", "(?i)token"]`',
            '`ai.provider = "remote"` unless `ai.remote_allowed = true`',
            "ZNTL_AI_PROVIDER_NOT_ALLOWED",
        ],
        "docs/FAILURE_MODES.md": [
            "ZNTL_AI_PROVIDER_NOT_ALLOWED",
            "ZNTL_AI_REPORT_NOT_FOUND",
            "ZNTL_AI_TARGET_NOT_FOUND",
            "ZNTL_DOCTEST_CASE_NOT_FOUND",
            "ZNTL_DOCTEST_DOC_NOT_FOUND",
            "ZNTL_DOCTEST_SURVIVOR_NOT_FOUND",
        ],
        "tasks/053-ai-provider-and-context.md": [
            'omitted `ai.redact_patterns` expands to `["(?i)api[_-]?key", "(?i)token"]`',
            '`ai.provider = "remote"` unless `ai.remote_allowed = true`',
        ],
        "tasks/054-ai-advisory-commands.md": [
            "doctest-specific classification values",
            "ai.remote_allowed = false",
            "reject unknown context schema versions",
        ],
        "tasks/055-ai-doctest-assistance.md": [
            "doctest-specific classification labels",
            "zentinel doctest review-snapshot <case-ref>",
            "context.schema_version = \"zentinel.ai.doctest.context.v1\"",
            "suggest_missing_doctests",
            "rejects `flow = \"explain_doctest_survivor\"`",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing AI contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain AI contract phrase '{phrase}'")


def enum_values(schema: object, path: list[str]) -> list[object]:
    current = schema
    for key in path:
        if not isinstance(current, dict):
            return []
        current = current.get(key)
    return current if isinstance(current, list) else []


def validate_runtime_safety_contracts(errors: list[str]) -> None:
    report_schema = load_json(ROOT / "schemas" / "report.v1.schema.json", errors)
    if isinstance(report_schema, dict):
        summary = report_schema.get("properties", {}).get("summary", {}) if isinstance(report_schema.get("properties"), dict) else {}
        required = summary.get("required") if isinstance(summary, dict) else None
        require(isinstance(required, list) and "compiler_crash" in required, errors, "report schema summary must require compiler_crash")
        result_status = enum_values(report_schema, ["$defs", "result", "properties", "status", "enum"])
        require("compiler_crash" in result_status, errors, "report schema result.status must include compiler_crash")

    ai_context_schema = load_json(ROOT / "schemas" / "ai.context.v1.schema.json", errors)
    if isinstance(ai_context_schema, dict):
        result_status = enum_values(ai_context_schema, ["$defs", "result", "properties", "status", "enum"])
        require("compiler_crash" in result_status, errors, "AI context result.status must include compiler_crash")

    failure_modes_gap = load_json(ROOT / "tests" / "coverage-gaps" / "failure_modes.v1.json", errors)
    if isinstance(failure_modes_gap, dict):
        entries = failure_modes_gap.get("entries")
        if isinstance(entries, list):
            f033 = next((entry for entry in entries if isinstance(entry, dict) and entry.get("number") == "F-033"), None)
            require(isinstance(f033, dict), errors, "failure mode gap registry must include F-033")
            if isinstance(f033, dict):
                deferred_to = f033.get("deferred_to")
                require(deferred_to != "tasks/025-autonomous-backlog-audit.md", errors, "F-033 must not be deferred to the administrative backlog audit task")
                require(
                    deferred_to == "preview backlog after minimum complete product" or (isinstance(deferred_to, str) and deferred_to.startswith("tasks/")),
                    errors,
                    "F-033 must defer either to explicit preview backlog or a concrete future task",
                )

    required_phrases = {
        "docs/REPORT_FORMAT.md": [
            "compiler_crash",
            "zentinel.compiler_crash",
            "distinct from `compile_error` and `invalid`",
        ],
        "docs/FAILURE_MODES.md": [
            "F-032. Mutant compiler crash",
            "F-033. Allocator mutator escapes target allocator boundary",
            "ZNTL_RUNNER_COMPILER_CRASH",
        ],
        "docs/ERROR_CODES.md": [
            "ZNTL_RUNNER_COMPILER_CRASH",
            "ZNTL_DOCTEST_SURVIVOR_NOT_FOUND",
        ],
        "docs/SANDBOX_SECURITY.md": [
            "Allocator Mutation Boundary",
            "injected allocator wrapper",
            "No two workers may write the same local cache",
        ],
        "docs/MUTATOR_SPEC.md": [
            "runner allocator paths",
            "harness allocator paths",
            "compiler_crash",
        ],
        "docs/PERFORMANCE_STRATEGY.md": [
            "Compilation cost is the primary performance constraint",
            "cold versus warm Zig build-cache behavior",
            "Concurrent workers must not write",
        ],
        "tasks/021-cache-key-design.md": [
            "Zig cache namespace metadata",
        ],
        "tasks/050-parallel-worker-pool.md": [
            "dedicated writable workspace",
            "zig-out",
        ],
        "tasks/052-performance-benchmarks.md": [
            "cold-versus-warm Zig build-cache",
            "cache isolation",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing runtime safety contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain runtime safety phrase '{phrase}'")


def validate_agent_readiness_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}

    def task_allows(task_id: str, required_files: list[str]) -> None:
        task = task_by_id.get(task_id)
        require(task is not None, errors, f"task {task_id} must exist for agent-readiness validation")
        if task is None:
            return
        allowed = task.get("allowed_files")
        for file_path in required_files:
            require(isinstance(allowed, list) and file_path in allowed, errors, f"task {task_id} must allow {file_path}")

    required_phrases = {
        "docs/CLI_SPEC.md": [
            "## Run Option Ownership",
            "`--operator <name>` | `tasks/016-minimal-run-command.md`",
            "`--mutant <id>` | `tasks/016-minimal-run-command.md`",
            "`--fail-on-survivors` | `tasks/016-minimal-run-command.md`",
            "`--output <path>` | `tasks/016-minimal-run-command.md`",
            "`--no-cache` | `tasks/021-cache-key-design.md`",
            "`--jobs <n>` | `tasks/050-parallel-worker-pool.md`",
            "`--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` | `tasks/058-safety-mode-matrix.md`",
        ],
        "docs/CONFIG_SPEC.md": [
            "## Run Section",
            "`jobs` | integer | `1`",
            "worker count",
            "non-positive worker counts",
        ],
        "tasks/002-config-parser.md": [
            "`phase1`, `phase2`, and `all_stable`",
            "negative timeouts",
            "`baseline_required = false`",
            "undefined mutator names",
            "output directory outside project root",
            "`run.jobs`",
        ],
        "tasks/014-baseline-runner.md": [
            "baseline timeout maps to `run.status = baseline_failed`",
        ],
        "tasks/016-minimal-run-command.md": [
            "`--operator <name>`",
            "`--mutant <id>`",
            "`--fail-on-survivors`",
            "`--output <path>`",
        ],
        "tasks/021-cache-key-design.md": [
            "`--no-cache`",
        ],
        "tasks/034-doctest-snapshots.md": [
            "regex text",
            "JSON unordered",
        ],
        "tasks/050-parallel-worker-pool.md": [
            "`--jobs <n>`",
            "`run.jobs`",
        ],
        "tasks/058-safety-mode-matrix.md": [
            "`--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>`",
        ],
        "tasks/063-pipeline-metadata-validator.md": [
            "immediately after task 041",
        ],
        "docs/REPORT_FORMAT.md": [
            "Baseline command timeout is a baseline failure",
        ],
        "docs/DOCTEST_ARCHITECTURE.md": [
            "regex",
            "json_subset",
            "json_unordered",
        ],
        ".agents/roles/mutation-agent.md": [
            "compiler_crash",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing agent-readiness contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain agent-readiness phrase '{phrase}'")

    task_allows("018", ["src/run_command.zig", "test/run_command_test.zig"])
    task_allows("021", ["src/cli.zig", "src/run_command.zig", "test/run_command_test.zig"])
    task_allows("050", ["src/cli.zig", "src/run_command.zig", "test/run_command_test.zig"])
    task_allows("058", ["src/cli.zig", "src/run_command.zig", "test/run_command_test.zig"])

    task063 = task_by_id.get("063")
    require(task063 is not None and task_order(task063) == "041.1", errors, "task 063 must execute immediately after task 041")
    if task063 is not None:
        require(task063.get("dependencies") == ["041"], errors, "task 063 must depend only on task 041")
    task042 = task_by_id.get("042")
    if task042 is not None:
        require("063" in task042.get("dependencies", []), errors, "task 042 must depend on task 063 so post-041 artifacts are validator-backed")


def validate_preimplementation_blocker_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}

    task000 = task_by_id.get("000")
    require(task000 is not None, errors, "task 000 must exist for bootstrap contract validation")
    if isinstance(task000, dict):
        allowed = task000.get("allowed_files")
        require(
            isinstance(allowed, list) and "test/bootstrap_discovery_test.zig" in allowed,
            errors,
            "task 000 must allow a bootstrap discovery test so future top-level tests are included by zig build test",
        )

    required_phrases = {
        "tasks/000-project-bootstrap.md": [
            "top-level `test/*_test.zig`",
            "`test/bootstrap_discovery_test.zig`",
            "without per-task `build.zig` edits",
        ],
        "tasks/003-test-harness.md": [
            "extends the bootstrap top-level discovery",
        ],
        "docs/PIPELINE_ARTIFACTS.md": [
            "locks/",
            "locks/active-task-lock.json",
            "`schema_version`",
            "`zentinel.pipeline.active_lock.v1`",
        ],
        "docs/SCHEMA_REGISTRY.md": [
            "zentinel.pipeline.active_lock.v1",
            "schemas/pipeline.active_lock.v1.schema.json",
        ],
        "tests/coverage-gaps/schemas.v1.json": [
            "zentinel.pipeline.active_lock.v1",
            "schemas/pipeline.active_lock.v1.schema.json",
        ],
        "docs/SEQUENTIAL_EXECUTION_POLICY.md": [
            "locks/active-task-lock.json",
        ],
        "tasks/041-handoff-artifacts.md": [
            "active lock artifact",
            "locks/active-task-lock.json",
        ],
        "tasks/063-pipeline-metadata-validator.md": [
            "active lock artifact",
            "locks/active-task-lock.json",
        ],
        ".agents/README.md": [
            "locks/",
        ],
        "docs/AGENT_ROLE_SPEC.md": [
            "locks/active-task-lock.json",
        ],
        "docs/VERIFICATION_PIPELINE.md": [
            "active lock",
        ],
        "docs/DOCTEST_SPEC.md": [
            "Expectation-only blocks do not produce standalone `case.kind` values",
        ],
        "docs/DOCTEST_AI_INTEGRATION.md": [
            "Expectation-only blocks do not appear as doctest `kind` values",
        ],
        "README.md": [
            "AGENTS.md",
            "docs/AGENT_GUIDE.md",
            "tasks/STATUS.md",
        ],
        "tasks/STATUS.md": [
            "tasks `061` through `070`",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing preimplementation contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain preimplementation contract phrase '{phrase}'")

    forbidden_phrases = {
        "docs/DOCTEST_SPEC.md": [
            "json_expected",
            "text_output",
        ],
        "docs/DOCTEST_AI_INTEGRATION.md": [
            "json_expected",
            "text_output",
        ],
        "tasks/STATUS.md": [
            "through task 060",
            "tasks 061-066",
            "passed with 61 tasks",
            "passed with 67 tasks",
            "passed with 68 tasks",
            "passed with 69 tasks",
            "passed with 70 tasks",
        ],
        "tasks/status.json": [
            "task count is 70",
            "through release acceptance task 060",
            "concrete queued tasks 061-066",
        ],
    }
    for rel, phrases in forbidden_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing preimplementation stale-contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase not in text, errors, f"{rel} contains stale or ambiguous phrase '{phrase}'")


def validate_agent_contract_finalization_contracts(status: object, errors: list[str]) -> None:
    orchestrator_path = ROOT / ".agents" / "ORCHESTRATOR.md"
    escalation_path = ROOT / "docs" / "PIPELINE_ESCALATION_POLICY.md"
    for path in [orchestrator_path, escalation_path]:
        require(path.is_file(), errors, f"missing agent contract finalization file {path.relative_to(ROOT)}")

    if orchestrator_path.is_file():
        text = orchestrator_path.read_text(encoding="utf-8")
        required_rows = [
            "| Low-risk | Test Author, Implementer, Verifier |",
            "| Normal | Test Author, Test Reviewer, Implementer, Implementation Reviewer, Verifier |",
            "| High-risk | Normal roles plus Property Test Agent or Mutation Agent as applicable |",
            "| Compiler-internal | High-risk roles plus Architecture Reviewer |",
            "| Architecture | Phase Planner, Architecture Reviewer, Test Reviewer for executable contracts, Verifier |",
        ]
        require("mirrors `docs/PIPELINE_ESCALATION_POLICY.md`" in text, errors, ".agents/ORCHESTRATOR.md must state complexity routing mirrors the escalation policy")
        for row in required_rows:
            require(row in text, errors, f".agents/ORCHESTRATOR.md must contain escalation-policy routing row {row!r}")
        for stale in ["Low-risk docs-only", "Low-risk test-only", "| Architecture or governance |"]:
            require(stale not in text, errors, f".agents/ORCHESTRATOR.md contains stale routing class {stale!r}")

    pipeline_schema_contracts = {
        "tasks/063-pipeline-metadata-validator.md": [
            "baseline pipeline schema files",
            "tasks `042`, `046`, and `049` refine",
        ],
        "tasks/042-context-packet-system.md": [
            "refine the baseline context and stale-context schemas created by task `063`",
        ],
        "tasks/046-verification-pipeline.md": [
            "refine the baseline verification schema created by task `063`",
        ],
        "tasks/049-pipeline-escalation.md": [
            "refine the baseline escalation schema created by task `063`",
        ],
        "docs/SCHEMA_REGISTRY.md": [
            "Task `tasks/063-pipeline-metadata-validator.md` creates baseline pipeline schema files",
            "tasks `042`, `046`, and `049` refine role-specific fields",
        ],
    }
    for rel, phrases in pipeline_schema_contracts.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing pipeline schema ownership file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must clarify pipeline schema ownership phrase '{phrase}'")

    schema_gap_path = GAP_REGISTRY_DIR / "schemas.v1.json"
    if schema_gap_path.is_file():
        data = load_json(schema_gap_path, errors)
        entries = data.get("entries") if isinstance(data, dict) else None
        if isinstance(entries, list):
            expected_later_tasks = {
                "zentinel.pipeline.context.v1": "tasks/042-context-packet-system.md",
                "zentinel.pipeline.stale_context.v1": "tasks/042-context-packet-system.md",
                "zentinel.pipeline.verification.v1": "tasks/046-verification-pipeline.md",
                "zentinel.pipeline.escalation.v1": "tasks/049-pipeline-escalation.md",
            }
            by_version = {entry.get("version"): entry for entry in entries if isinstance(entry, dict)}
            for version, later_task in expected_later_tasks.items():
                entry = by_version.get(version)
                require(isinstance(entry, dict), errors, f"schemas.v1.json missing pipeline schema row {version}")
                if not isinstance(entry, dict):
                    continue
                require(entry.get("deferred_to") == "tasks/063-pipeline-metadata-validator.md", errors, f"schemas.v1.json {version} must defer baseline schema validation to task 063")
                notes = entry.get("notes")
                require(isinstance(notes, str) and "baseline schema" in notes and later_task in notes, errors, f"schemas.v1.json {version} notes must name baseline schema ownership and later refinement task {later_task}")

    gitignore_path = ROOT / ".gitignore"
    require(gitignore_path.is_file(), errors, ".gitignore must exist before Zig bootstrap creates build artifacts")
    if gitignore_path.is_file():
        text = gitignore_path.read_text(encoding="utf-8")
        for pattern in [".zig-cache/", "zig-out/"]:
            require(pattern in text, errors, f".gitignore must ignore {pattern}")

    if isinstance(status, dict):
        status_text = json.dumps(status)
        for stale in ["untracked git content", "baseline commit"]:
            require(stale not in status_text, errors, f"tasks/status.json contains stale baseline wording {stale!r}")


def validate_task_lifecycle_contracts(errors: list[str]) -> None:
    path = ROOT / "docs" / "TASK_LIFECYCLE.md"
    require(path.is_file(), errors, "docs/TASK_LIFECYCLE.md is missing")
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    require("## Queue States" in text, errors, "docs/TASK_LIFECYCLE.md must separate queue states")
    require("## Pipeline Artifact Stages" in text, errors, "docs/TASK_LIFECYCLE.md must separate pipeline artifact stages")
    require("artifact stages only" in text, errors, "docs/TASK_LIFECYCLE.md must state fine-grained stages are artifact-only")
    for state in ["`tests_authored`", "`tests_reviewed`", "`reviewed`", "`mutation_checked`"]:
        require(state in text, errors, f"docs/TASK_LIFECYCLE.md must classify {state} as an artifact stage")


def unescaped_pipe_count(line: str) -> int:
    count = 0
    escaped = False
    for char in line:
        if escaped:
            escaped = False
            continue
        if char == "\\":
            escaped = True
            continue
        if char == "|":
            count += 1
    return count


def validate_markdown_table_shapes(errors: list[str]) -> None:
    files = [
        "docs/MUTATOR_SPEC.md",
    ]
    for rel in files:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing markdown table contract file {rel}")
        if not path.is_file():
            continue
        expected_pipes: int | None = None
        table_start = 0
        in_fence = False
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                expected_pipes = None
                continue
            if in_fence or not line.startswith("|"):
                expected_pipes = None
                continue
            pipe_count = unescaped_pipe_count(line)
            if expected_pipes is None:
                expected_pipes = pipe_count
                table_start = line_no
                continue
            require(
                pipe_count == expected_pipes,
                errors,
                f"{rel}:{line_no} has {pipe_count} unescaped table pipes; expected {expected_pipes} from table starting at line {table_start}",
            )


def validate_adr_system(errors: list[str]) -> None:
    readme = ADR_DIR / "README.md"
    require(readme.is_file(), errors, "docs/adr/README.md is missing")
    if not readme.is_file():
        return

    index_text = readme.read_text(encoding="utf-8")
    indexed_files: set[str] = set()
    for match in ADR_INDEX_RE.finditer(index_text):
        adr_id, rel_file, status, date = match.groups()
        indexed_files.add(rel_file)
        path = ADR_DIR / rel_file
        require(path.is_file(), errors, f"{adr_id} index entry points to missing file {rel_file}")
        require(status.strip() in {"Proposed", "Accepted", "Deprecated"} or status.strip().startswith("Superseded by ADR-"), errors, f"{adr_id} has invalid status {status.strip()!r}")
        require(bool(re.match(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", date.strip())), errors, f"{adr_id} has invalid date {date.strip()!r}")
        if path.is_file():
            text = path.read_text(encoding="utf-8")
            require(text.startswith(f"# {adr_id}: "), errors, f"{rel_file} heading must start with '# {adr_id}: '")
            for section in ("## Context", "## Decision", "## Alternatives Considered", "## Consequences"):
                require(section in text, errors, f"{rel_file} missing section {section}")

    require(len(indexed_files) > 0, errors, "docs/adr/README.md must index at least one ADR")
    actual_files = {path.name for path in ADR_DIR.glob("[0-9][0-9][0-9][0-9]-*.md")}
    for rel_file in sorted(actual_files - indexed_files):
        fail(errors, f"ADR file missing from docs/adr/README.md index: {rel_file}")


def validate_gap_registries(errors: list[str]) -> None:
    expected = [
        ("invariants.v1.json", "zentinel.coverage_gaps.invariants.v1", "number", invariant_numbers(errors)),
        ("failure_modes.v1.json", "zentinel.coverage_gaps.failure_modes.v1", "number", failure_mode_numbers(errors)),
        ("mutators.v1.json", "zentinel.coverage_gaps.mutators.v1", "operator", mutator_operators(errors)),
        ("schemas.v1.json", "zentinel.coverage_gaps.schemas.v1", "version", [version for version, _ in SCHEMA_REGISTRY_PAIRS]),
    ]

    for filename, schema_version, key, required_values in expected:
        path = GAP_REGISTRY_DIR / filename
        require(path.is_file(), errors, f"missing gap registry tests/coverage-gaps/{filename}")
        if not path.is_file():
            continue
        data = load_json(path, errors)
        if not isinstance(data, dict):
            fail(errors, f"tests/coverage-gaps/{filename} must contain an object")
            continue
        require(data.get("schema_version") == schema_version, errors, f"tests/coverage-gaps/{filename} schema_version mismatch")
        require(data.get("mode") == "regression_only", errors, f"tests/coverage-gaps/{filename} mode must be regression_only")
        entries = data.get("entries")
        require(isinstance(entries, list), errors, f"tests/coverage-gaps/{filename} entries must be an array")
        if not isinstance(entries, list):
            continue

        seen: set[str] = set()
        for index, entry in enumerate(entries):
            require(isinstance(entry, dict), errors, f"tests/coverage-gaps/{filename} entry {index} must be an object")
            if not isinstance(entry, dict):
                continue
            value = entry.get(key)
            require(isinstance(value, str) and bool(value), errors, f"tests/coverage-gaps/{filename} entry {index} missing {key}")
            if isinstance(value, str):
                require(value not in seen, errors, f"tests/coverage-gaps/{filename} duplicate {key} {value}")
                seen.add(value)
            covered = entry.get("covered")
            tests = entry.get("tests")
            deferred_to = entry.get("deferred_to")
            require(isinstance(covered, bool), errors, f"tests/coverage-gaps/{filename} {value!r} covered must be boolean")
            require(isinstance(tests, list) and all(isinstance(item, str) for item in tests), errors, f"tests/coverage-gaps/{filename} {value!r} tests must be a string array")
            if covered is True:
                require(isinstance(tests, list) and len(tests) > 0, errors, f"tests/coverage-gaps/{filename} {value!r} covered rows must list tests")
            if covered is False:
                require(isinstance(deferred_to, str) and bool(deferred_to), errors, f"tests/coverage-gaps/{filename} {value!r} uncovered rows must name deferred_to")
            if isinstance(deferred_to, str) and deferred_to.startswith("tasks/"):
                require((ROOT / deferred_to).is_file(), errors, f"tests/coverage-gaps/{filename} {value!r} deferred_to missing task file {deferred_to}")

        missing = set(required_values) - seen
        extra = seen - set(required_values)
        for value in sorted(missing):
            fail(errors, f"tests/coverage-gaps/{filename} missing {key} {value}")
        for value in sorted(extra):
            fail(errors, f"tests/coverage-gaps/{filename} has unknown {key} {value}")


def validate_schema_gap_ownership(tasks: list[dict[str, object]], errors: list[str]) -> None:
    path = GAP_REGISTRY_DIR / "schemas.v1.json"
    if not path.is_file():
        return
    data = load_json(path, errors)
    if not isinstance(data, dict):
        return
    entries = data.get("entries")
    if not isinstance(entries, list):
        return

    task_by_file = {task.get("file"): task for task in tasks if isinstance(task.get("file"), str)}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            continue
        if entry.get("covered") is True:
            continue
        schema_file = entry.get("file")
        deferred_to = entry.get("deferred_to")
        if not isinstance(schema_file, str) or not isinstance(deferred_to, str):
            continue
        task = task_by_file.get(deferred_to)
        require(task is not None, errors, f"schemas.v1.json entry {index} deferred_to task not found in queue: {deferred_to}")
        if task is None:
            continue
        allowed = task.get("allowed_files")
        require(isinstance(allowed, list) and schema_file in allowed, errors, f"schemas.v1.json entry {index} defers {schema_file} to {deferred_to}, but that task does not allow the schema file")


def invariant_numbers(errors: list[str]) -> list[str]:
    path = ROOT / "docs" / "INVARIANTS.md"
    if not path.is_file():
        fail(errors, "docs/INVARIANTS.md is missing")
        return []
    return INVARIANT_RE.findall(path.read_text(encoding="utf-8"))


def failure_mode_numbers(errors: list[str]) -> list[str]:
    path = ROOT / "docs" / "FAILURE_MODES.md"
    if not path.is_file():
        fail(errors, "docs/FAILURE_MODES.md is missing")
        return []
    return FAILURE_MODE_RE.findall(path.read_text(encoding="utf-8"))


def mutator_operators(errors: list[str]) -> list[str]:
    path = ROOT / "docs" / "MUTATOR_SPEC.md"
    if not path.is_file():
        fail(errors, "docs/MUTATOR_SPEC.md is missing")
        return []
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^## Operator Catalog\n\n(?P<body>.*?)(?=\n## )", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        fail(errors, "docs/MUTATOR_SPEC.md missing Operator Catalog section")
        return []
    operators: list[str] = []
    for line in match.group("body").splitlines():
        row = re.match(r"^\| `([a-z0-9_]+)` \|", line)
        if row:
            operators.append(row.group(1))
    return operators


def main() -> int:
    errors: list[str] = []

    queue = load_json(QUEUE_JSON, errors)
    status = load_json(STATUS_JSON, errors)
    tasks = validate_queue(queue, errors)
    validate_status(status, tasks, errors)
    validate_task_markdown(tasks, errors)
    validate_markdown_queue(tasks, errors)
    validate_markdown_status(status, tasks, errors)
    validate_schema_files(errors)
    validate_schema_registry(errors)
    validate_governance_files(errors)
    validate_agent_layer(errors)
    validate_pipeline_contracts(errors)
    validate_task_order_contracts(errors)
    validate_protocol_startup_order(errors)
    validate_same_file_exclusion_sequence(tasks, errors)
    validate_mutation_gate_availability_policy(errors)
    validate_agent_execution_contracts(errors)
    validate_cli_contracts(errors)
    validate_doctest_identity_contracts(errors)
    validate_ai_contracts(errors)
    validate_runtime_safety_contracts(errors)
    validate_agent_readiness_contracts(tasks, errors)
    validate_preimplementation_blocker_contracts(tasks, errors)
    validate_agent_contract_finalization_contracts(status, errors)
    validate_task_lifecycle_contracts(errors)
    validate_markdown_table_shapes(errors)
    validate_adr_system(errors)
    validate_gap_registries(errors)
    validate_schema_gap_ownership(tasks, errors)

    if errors:
        print("task system validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"task system validation passed: {len(tasks)} tasks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
