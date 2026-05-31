#!/usr/bin/env python3
"""Validate zentinel's autonomous task system.

This script intentionally uses only the Python standard library so it can run
in bootstrap environments before project dependencies exist.
"""

from __future__ import annotations

import json
import fnmatch
import hashlib
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
QUEUE_JSON = ROOT / "tasks" / "queue.json"
STATUS_JSON = ROOT / "tasks" / "status.json"
QUEUE_MD = ROOT / "tasks" / "QUEUE.md"
STATUS_MD = ROOT / "tasks" / "STATUS.md"
QUEUE_SCHEMA_JSON = ROOT / "tasks" / "schema" / "queue.v1.schema.json"
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

PROPERTY_GATE_TASK_IDS = {f"{task_id:03d}" for task_id in range(30, 50)}
DOCTEST_GATE_TASK_IDS = {f"{task_id:03d}" for task_id in range(40, 50)}
CANONICAL_GATE_SECTIONS = [
    "Required property tests",
    "Required doctests",
    "Mutation testing requirements",
]
LEGACY_GATE_HEADINGS = [
    "## Property tests required",
    "## Doctests required",
    "## Mutation tests required",
]

TASK_ID_RE = re.compile(r"^[0-9]{3}$")
TASK_FILE_RE = re.compile(r"^tasks/[0-9]{3}-.+\.md$")
TASK_REF_RE = re.compile(r"`((?:tasks/)?[0-9]{3}-[^`]+\.md)`")
NO_FOLLOW_UP_RE = re.compile(r"^None predefined\.")
ORDER_RE = re.compile(r"^[0-9]{3}(?:\.[0-9]+)*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
QUEUE_ROW_RE = re.compile(r"^\| ([0-9]{3}(?:\.[0-9]+)*) \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|$", re.MULTILINE)
INVARIANT_RE = re.compile(r"^\*\*(I-[0-9]{3})\.", re.MULTILINE)
FAILURE_MODE_RE = re.compile(r"^\*\*(F-[0-9]{3})\.", re.MULTILINE)
ERROR_CODE_RE = re.compile(r"`(ZNTL_[A-Z0-9_]+)`")
ADR_INDEX_RE = re.compile(r"^\| (ADR-[0-9]{4}) \| \[[^\]]+\]\(([^)]+)\) \| ([^|]+) \| ([^|]+) \|$", re.MULTILINE)
ZIG_LAYER_RE = re.compile(r"^\s*//\s*Layer:\s*([a-z_]+)\s*$", re.MULTILINE)
ZIG_IMPORT_RE = re.compile(r"@import\(\"([^\"]+)\"\)")

PINNED_ZIG_VERSION = "0.16.0"

TASK_CONTROL_FILES = {
    "tasks/QUEUE.md",
    "tasks/queue.json",
    "tasks/STATUS.md",
    "tasks/status.json",
}

QUEUE_TOP_LEVEL_FIELDS = {"schema_version", "ordering", "tasks"}
QUEUE_TASK_FIELDS = {
    "id",
    "order",
    "title",
    "file",
    "phase",
    "state",
    "dependencies",
    "allowed_files",
    "forbidden_files",
}
STATUS_TOP_LEVEL_FIELDS = {
    "schema_version",
    "active_task",
    "next_task",
    "completed_tasks",
    "blocked_tasks",
    "blocked_task_details",
    "last_validation",
    "completion_evidence",
    "clean_handoff_baseline",
    "history",
}
CLEAN_HANDOFF_BASELINE_FIELDS = {"task", "source_commit", "files", "notes"}
CLEAN_HANDOFF_BASELINE_FILE_FIELDS = {"path", "sha256"}
BLOCKED_TASK_DETAIL_FIELDS = {
    "task",
    "reason",
    "blocker_type",
    "evidence",
    "attempted_recovery",
    "prerequisite_task",
    "required_prerequisite_task",
    "requires_user_input",
    "edits_state",
    "notes",
}
BLOCKER_TYPES = {"missing_prerequisite", "scope_gap", "external_input", "spec_ambiguity", "prior_task_regression"}
BLOCKED_EDIT_STATES = {"no_edits", "task_control_only", "reverted", "preserved_behind_tests"}
LAST_VALIDATION_FIELDS = {"command", "status", "notes"}
LAST_VALIDATION_STATUSES = {"not_run", "passed", "failed"}
COMPLETION_SCOPE_CUTOVER_ORDER = "000.0.24"

ARCHITECTURE_LAYERS = {
    "deterministic_core",
    "pipeline_orchestration",
    "side_effect_adapter",
    "presentation_adapter",
    "advisory_adapter",
}
FORBIDDEN_LAYER_IMPORTS = {
    "deterministic_core": {
        "pipeline_orchestration",
        "side_effect_adapter",
        "presentation_adapter",
        "advisory_adapter",
    },
}
BOOTSTRAP_START_TASK_ID = "000"
CHRONOLOGY_PROOF_TASK_ID = "063"
PRE_063_CHRONOLOGY_LABELS = [
    "failing_command:",
    "failing_output_excerpt:",
    "implementation_started_after_failure:",
    "passing_command:",
]

PIPELINE_ARTIFACT_EXCEPTION = "artifacts/pipeline/<active-task-id>/**"
GAP_REGISTRY_EXCEPTION = "tests/coverage-gaps/<registry>.v1.json"
# The deterministic-core library root is the module-export + shared-dispatch hub
# (ADR-0009). Any task that introduces a core module must re-export it here, so
# root.zig is a project-wide allowed-files scope exception rather than a per-task file.
ROOT_MODULE_FILE = "src/root.zig"

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
    ".agents/roles/contract-editor.md",
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


def markdown_json_objects(path: Path, errors: list[str]) -> list[object]:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(errors, f"missing file: {path.relative_to(ROOT)}")
        return []

    values: list[object] = []
    for index, match in enumerate(re.finditer(r"```json\n(?P<body>.*?)\n```", text, flags=re.DOTALL), start=1):
        body = match.group("body")
        try:
            values.append(json.loads(body))
        except json.JSONDecodeError as exc:
            fail(errors, f"invalid JSON fence {index} in {path.relative_to(ROOT)}: {exc}")
    return values


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

    queue_keys = set(queue)
    for field in sorted(QUEUE_TOP_LEVEL_FIELDS - queue_keys):
        fail(errors, f"queue.json missing top-level field {field}")
    for field in sorted(queue_keys - QUEUE_TOP_LEVEL_FIELDS):
        fail(errors, f"queue.json contains unknown top-level field {field}")

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

        task_keys = set(task)
        for field in sorted(QUEUE_TASK_FIELDS - task_keys):
            fail(errors, f"task at index {index} missing field {field}")
        for field in sorted(task_keys - QUEUE_TASK_FIELDS):
            fail(errors, f"task at index {index} contains unknown field {field}")

        task_id = task.get("id")
        require(isinstance(task_id, str) and TASK_ID_RE.match(task_id) is not None, errors, f"task at index {index} has invalid id")
        if not isinstance(task_id, str):
            continue

        title = task.get("title")
        require(isinstance(title, str) and bool(title.strip()), errors, f"task {task_id} title must be a non-empty string")
        phase = task.get("phase")
        require(isinstance(phase, int) and phase >= 0, errors, f"task {task_id} phase must be a non-negative integer")

        require(task_id not in seen_ids, errors, f"duplicate task id {task_id}")
        seen_ids.add(task_id)

        explicit_order = task.get("order")
        require(isinstance(explicit_order, str) and ORDER_RE.match(explicit_order) is not None, errors, f"task {task_id} must have an explicit valid order")
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
        require(state in {"queued", "active", "blocked", "complete", "superseded"}, errors, f"task {task_id} has invalid state")

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

    # Task 060 (release acceptance) is the final Phase <=7 task. Phase 8 is a
    # documented post-release maintenance phase (audit follow-up backlog): its
    # tasks may follow 060 in execution order without being superseded, so
    # post-release work is tracked in-queue without reopening any earlier-phase
    # gate. Any non-Phase-8 task after 060 must still be superseded.
    release_index = next((index for index, task in enumerate(normalized) if task.get("file") == "tasks/060-release-acceptance-verification.md"), None)
    if release_index is not None:
        for later in normalized[release_index + 1:]:
            later_id = later.get("id")
            later_phase = later.get("phase")
            if isinstance(later_phase, int) and later_phase >= 8:
                continue
            require(later.get("state") == "superseded", errors, f"release acceptance task 060 must be the final non-superseded execution-order task; task {later_id} follows it")

    return normalized


def validate_status(status: object, tasks: list[dict[str, object]], errors: list[str]) -> None:
    require(isinstance(status, dict), errors, "status.json must contain an object")
    if not isinstance(status, dict):
        return

    status_keys = set(status)
    for field in sorted(STATUS_TOP_LEVEL_FIELDS - status_keys):
        fail(errors, f"status.json missing top-level field {field}")
    for field in sorted(status_keys - STATUS_TOP_LEVEL_FIELDS):
        fail(errors, f"status.json contains unknown top-level field {field}")

    require(status.get("schema_version") == "zentinel.tasks.status.v1", errors, "status.json schema_version mismatch")

    task_ids = [task["id"] for task in tasks if isinstance(task.get("id"), str)]
    task_by_id = {task["id"]: task for task in tasks if isinstance(task.get("id"), str)}
    validate_clean_handoff_baseline(status, task_by_id, errors)

    active_states = [task["id"] for task in tasks if task.get("state") == "active"]
    current_states = active_states
    require(len(active_states) <= 1, errors, "only one task may be active")
    require(len(current_states) <= 1, errors, "only one task may be active pending completion")

    active_task = status.get("active_task")
    require(active_task is None or (isinstance(active_task, str) and active_task in task_by_id), errors, "status.json active_task must be null or a known task id")
    if current_states:
        require(active_task == current_states[0], errors, "status active_task must match the current active queue state")
    else:
        require(active_task is None, errors, "status active_task must be null when no task is active")

    completed = status.get("completed_tasks")
    require(isinstance(completed, list), errors, "status completed_tasks must be an array")
    status_completed_ids: set[str] = set()
    if isinstance(completed, list):
        for task_id in completed:
            require(isinstance(task_id, str) and task_id in task_by_id, errors, f"completed task {task_id!r} is not known")
            if isinstance(task_id, str) and task_id in task_by_id:
                status_completed_ids.add(task_id)
                require(task_by_id[task_id].get("state") == "complete", errors, f"completed task {task_id} must have queue state complete")
        queue_completed_ids = {task["id"] for task in tasks if task.get("state") == "complete" and isinstance(task.get("id"), str)}
        for task_id in sorted(queue_completed_ids - status_completed_ids):
            fail(errors, f"queue complete task {task_id} is missing from status completed_tasks")
        for task_id in sorted(status_completed_ids - queue_completed_ids):
            fail(errors, f"status completed task {task_id} is not complete in queue.json")

    blocked = status.get("blocked_tasks")
    require(isinstance(blocked, list), errors, "status blocked_tasks must be an array")
    blocked_ids: set[str] = set()
    if isinstance(blocked, list):
        for task_id in blocked:
            require(isinstance(task_id, str) and task_id in task_by_id, errors, f"blocked task {task_id!r} is not known")
            if isinstance(task_id, str) and task_id in task_by_id:
                blocked_ids.add(task_id)
                require(task_by_id[task_id].get("state") == "blocked", errors, f"blocked task {task_id} must have queue state blocked")

    blocked_details = status.get("blocked_task_details")
    require(isinstance(blocked_details, list), errors, "status blocked_task_details must be an array")
    detail_task_ids: set[str] = set()
    if isinstance(blocked_details, list):
        for index, detail in enumerate(blocked_details):
            require(isinstance(detail, dict), errors, f"blocked_task_details entry {index} must be an object")
            if not isinstance(detail, dict):
                continue
            detail_keys = set(detail)
            for field in sorted(BLOCKED_TASK_DETAIL_FIELDS - detail_keys):
                fail(errors, f"blocked_task_details entry {index} missing field {field}")
            for field in sorted(detail_keys - BLOCKED_TASK_DETAIL_FIELDS):
                fail(errors, f"blocked_task_details entry {index} contains unknown field {field}")
            detail_task = detail.get("task")
            require(isinstance(detail_task, str) and detail_task in task_by_id, errors, f"blocked_task_details entry {index} task must be known")
            if isinstance(detail_task, str) and detail_task in task_by_id:
                detail_task_ids.add(detail_task)
            reason = detail.get("reason")
            require(isinstance(reason, str) and bool(reason.strip()), errors, f"blocked_task_details entry {index} reason must be non-empty")
            prerequisite_task = detail.get("prerequisite_task")
            require(
                prerequisite_task is None or (isinstance(prerequisite_task, str) and prerequisite_task in task_by_id),
                errors,
                f"blocked_task_details entry {index} prerequisite_task must be null or a known task id",
            )
            required_prerequisite_task = detail.get("required_prerequisite_task")
            require(
                required_prerequisite_task is None or (isinstance(required_prerequisite_task, str) and required_prerequisite_task in task_by_id),
                errors,
                f"blocked_task_details entry {index} required_prerequisite_task must be null or a known task id",
            )
            if isinstance(prerequisite_task, str) and isinstance(required_prerequisite_task, str):
                require(prerequisite_task == required_prerequisite_task, errors, f"blocked_task_details entry {index} prerequisite_task and required_prerequisite_task must match")
            for field in ["blocker_type", "evidence", "attempted_recovery", "edits_state"]:
                require(isinstance(detail.get(field), str) and bool(detail.get(field, "").strip()), errors, f"blocked_task_details entry {index} {field} must be non-empty")
            blocker_type = detail.get("blocker_type")
            require(blocker_type in BLOCKER_TYPES, errors, f"blocked_task_details entry {index} blocker_type must be a known enum value")
            edits_state = detail.get("edits_state")
            require(edits_state in BLOCKED_EDIT_STATES, errors, f"blocked_task_details entry {index} edits_state must be a known enum value")
            require(isinstance(detail.get("requires_user_input"), bool), errors, f"blocked_task_details entry {index} requires_user_input must be boolean")
            requires_user_input = detail.get("requires_user_input")
            if requires_user_input is False:
                require(isinstance(required_prerequisite_task, str), errors, f"blocked_task_details entry {index} required_prerequisite_task must be set unless user input is required")
            if isinstance(required_prerequisite_task, str):
                prerequisite = task_by_id.get(required_prerequisite_task)
                if isinstance(prerequisite, dict) and prerequisite.get("state") == "complete":
                    fail(errors, f"blocked_task_details entry {index} prerequisite {required_prerequisite_task} is complete; blocked task must return to queued")
            notes = detail.get("notes")
            require(isinstance(notes, str) and bool(notes.strip()), errors, f"blocked_task_details entry {index} notes must be non-empty")

    for task_id in sorted(blocked_ids - detail_task_ids):
        fail(errors, f"blocked task {task_id} is missing blocked_task_details entry")
    for task_id in sorted(detail_task_ids - blocked_ids):
        fail(errors, f"blocked_task_details entry {task_id} is not listed in blocked_tasks")

    for task in tasks:
        task_id = task.get("id")
        state = task.get("state")
        deps = task.get("dependencies")
        if not isinstance(task_id, str) or not isinstance(deps, list):
            continue
        if state not in {"active", "complete"}:
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

    last_validation = status.get("last_validation")
    require(isinstance(last_validation, dict), errors, "status last_validation must be an object")
    if isinstance(last_validation, dict):
        require(set(last_validation) == LAST_VALIDATION_FIELDS, errors, "status last_validation must contain command, status, and notes")
        require(isinstance(last_validation.get("command"), str) and bool(last_validation.get("command")), errors, "status last_validation.command must be non-empty")
        require(last_validation.get("status") in LAST_VALIDATION_STATUSES, errors, "status last_validation.status must be a known enum value")
        require(isinstance(last_validation.get("notes"), str) and bool(last_validation.get("notes")), errors, "status last_validation.notes must be non-empty")
    require(isinstance(status.get("history"), list), errors, "status history must be an array")
    validate_completion_evidence(status, task_by_id, errors)


def validate_completion_evidence(status: dict[object, object], task_by_id: dict[str, dict[str, object]], errors: list[str]) -> None:
    evidence = status.get("completion_evidence")
    require(isinstance(evidence, list), errors, "status completion_evidence must be an array")
    completed = status.get("completed_tasks")
    if not isinstance(evidence, list) or not isinstance(completed, list):
        return

    required_fields = {
        "task",
        "failing_evidence",
        "implementation_summary",
        "files_changed",
        "tests_added",
        "tests_run",
        "validator_result",
        "dogfooding_implication",
        "follow_up_tasks",
    }
    optional_fields = {"artifacts", "gap_registry_rows_changed", "task_control_changes"}
    evidence_by_task: dict[str, dict[str, object]] = {}
    for index, entry in enumerate(evidence):
        require(isinstance(entry, dict), errors, f"completion_evidence entry {index} must be an object")
        if not isinstance(entry, dict):
            continue
        keys = set(entry)
        missing = required_fields - keys
        extra = keys - required_fields - optional_fields
        for field in sorted(missing):
            fail(errors, f"completion_evidence entry {index} missing field {field}")
        for field in sorted(extra):
            fail(errors, f"completion_evidence entry {index} has unknown field {field}")

        task_id = entry.get("task")
        require(isinstance(task_id, str) and task_id in task_by_id, errors, f"completion_evidence entry {index} task must be known")
        if isinstance(task_id, str):
            require(task_id not in evidence_by_task, errors, f"completion_evidence has duplicate task {task_id}")
            evidence_by_task[task_id] = entry

        for field in ["failing_evidence", "implementation_summary", "dogfooding_implication"]:
            require(isinstance(entry.get(field), str) and bool(entry.get(field)), errors, f"completion_evidence entry {index} field {field} must be a non-empty string")
        for field in ["files_changed", "tests_added", "tests_run", "follow_up_tasks"]:
            require(isinstance(entry.get(field), list) and all(isinstance(item, str) and item for item in entry.get(field, [])), errors, f"completion_evidence entry {index} field {field} must be a string array")
        if "artifacts" in entry:
            require(isinstance(entry.get("artifacts"), list) and all(isinstance(item, str) and item for item in entry.get("artifacts", [])), errors, f"completion_evidence entry {index} field artifacts must be a string array")
        gap_rows = entry.get("gap_registry_rows_changed")
        if gap_rows is not None:
            require(isinstance(gap_rows, dict), errors, f"completion_evidence entry {index} gap_registry_rows_changed must be an object")
            if isinstance(gap_rows, dict):
                for registry_path, rows in gap_rows.items():
                    require(isinstance(registry_path, str) and re.match(r"^tests/coverage-gaps/[^/]+\.v1\.json$", registry_path) is not None, errors, f"completion_evidence entry {index} gap_registry_rows_changed key must be a gap registry path")
                    require(isinstance(rows, list) and all(isinstance(row, str) and row for row in rows), errors, f"completion_evidence entry {index} gap_registry_rows_changed rows for {registry_path!r} must be a non-empty string array")
        task_control_changes = entry.get("task_control_changes")
        if task_control_changes is not None:
            require(isinstance(task_control_changes, list) and all(isinstance(item, str) and item for item in task_control_changes), errors, f"completion_evidence entry {index} task_control_changes must be a string array")
        tests_run = entry.get("tests_run")
        require(isinstance(tests_run, list) and any(isinstance(item, str) and "python3 scripts/validate_task_system.py" in item for item in tests_run), errors, f"completion_evidence entry {index} tests_run must include python3 scripts/validate_task_system.py")
        tests_added = entry.get("tests_added")
        failing_evidence = entry.get("failing_evidence")
        if isinstance(tests_added, list) and not tests_added:
            require(
                isinstance(failing_evidence, str)
                and ("No new structural guardrail" in failing_evidence or "No behavior change" in failing_evidence),
                errors,
                f"completion_evidence entry {index} with empty tests_added must explain no new structural guardrail or no behavior change",
            )

        validator = entry.get("validator_result")
        require(isinstance(validator, dict), errors, f"completion_evidence entry {index} validator_result must be an object")
        if isinstance(validator, dict):
            require(set(validator) == {"command", "status", "notes"}, errors, f"completion_evidence entry {index} validator_result must contain command, status, and notes")
            require(isinstance(validator.get("command"), str) and bool(validator.get("command")), errors, f"completion_evidence entry {index} validator_result.command must be non-empty")
            require(validator.get("status") == "passed", errors, f"completion_evidence entry {index} validator_result.status must be passed")
            require(isinstance(validator.get("notes"), str) and bool(validator.get("notes")), errors, f"completion_evidence entry {index} validator_result.notes must be non-empty")

        if isinstance(task_id, str):
            task = task_by_id.get(task_id)
            if isinstance(task, dict) and order_key(task_order(task)) >= order_key(COMPLETION_SCOPE_CUTOVER_ORDER):
                all_tasks = list(task_by_id.values())
                validate_completion_scope_evidence(entry, task, index, all_tasks, errors)
            if isinstance(task, dict) and requires_pre063_chronology_labels(task, task_by_id):
                validate_pre063_chronology_labels(entry, task_id, index, errors)

    completed_ids = [task_id for task_id in completed if isinstance(task_id, str)]
    for task_id in completed_ids:
        require(task_id in evidence_by_task, errors, f"completed task {task_id} missing completion_evidence entry")

    task_041 = task_by_id.get("041")
    if isinstance(task_041, dict) and task_041.get("state") == "complete":
        order_041 = order_key(task_order(task_041))
        for task_id, entry in evidence_by_task.items():
            task = task_by_id.get(task_id)
            if isinstance(task, dict) and order_key(task_order(task)) > order_041:
                require("artifacts" in entry, errors, f"post-041 completion_evidence for task {task_id} must include artifacts")
                artifacts = entry.get("artifacts")
                if isinstance(artifacts, list):
                    for artifact in artifacts:
                        if not isinstance(artifact, str):
                            continue
                        require(artifact.startswith(f"artifacts/pipeline/{task_id}/"), errors, f"post-041 artifact {artifact} must live under artifacts/pipeline/{task_id}/")
                        require((ROOT / artifact).exists(), errors, f"post-041 artifact {artifact} must exist")


def validate_completion_scope_evidence(entry: dict[str, object], task: dict[str, object], index: int, all_tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_id = task.get("id")
    allowed_files = task.get("allowed_files")
    forbidden_files = task.get("forbidden_files")
    files_changed = entry.get("files_changed")
    if not isinstance(task_id, str) or not isinstance(files_changed, list):
        return

    for path in files_changed:
        if not isinstance(path, str):
            continue
        require(
            not path.startswith("/") and not path.startswith("task "),
            errors,
            f"completion_evidence entry {index} files_changed must use concrete project-relative paths after task 094: {path!r}",
        )
        if path_matches_any(path, forbidden_files):
            fail(errors, f"completion_evidence entry {index} file {path} is forbidden by task {task_id}")
            continue
        if is_global_scope_exception(path, task_id, all_tasks):
            if path in TASK_CONTROL_FILES:
                task_control_changes = entry.get("task_control_changes")
                require(isinstance(task_control_changes, list) and path in task_control_changes, errors, f"completion_evidence entry {index} task-control file {path} must be listed in task_control_changes")
            if re.match(r"^tests/coverage-gaps/[^/]+\.v1\.json$", path):
                gap_rows = entry.get("gap_registry_rows_changed")
                require(isinstance(gap_rows, dict) and isinstance(gap_rows.get(path), list) and bool(gap_rows.get(path)), errors, f"completion_evidence entry {index} gap registry file {path} must list changed row ids")
            continue
        require(path_matches_any(path, allowed_files), errors, f"completion_evidence entry {index} file {path} is outside task {task_id} allowed_files")


def requires_pre063_chronology_labels(task: dict[str, object], task_by_id: dict[str, dict[str, object]]) -> bool:
    """Require structured chronology labels for behavior-changing tasks before artifact timestamp proof exists."""
    task_000 = task_by_id.get(BOOTSTRAP_START_TASK_ID)
    task_063 = task_by_id.get(CHRONOLOGY_PROOF_TASK_ID)
    if not isinstance(task_000, dict) or not isinstance(task_063, dict):
        return False

    current_order = order_key(task_order(task))
    if current_order < order_key(task_order(task_000)) or current_order >= order_key(task_order(task_063)):
        return False

    allowed = task.get("allowed_files")
    if not isinstance(allowed, list):
        return False

    behavior_prefixes = ("src/", "test/", "scripts/", "schemas/")
    behavior_files = {"build.zig", "build.zig.zon"}
    for pattern in allowed:
        if not isinstance(pattern, str):
            continue
        if pattern in behavior_files or pattern.startswith(behavior_prefixes):
            return True
    return False


def validate_pre063_chronology_labels(entry: dict[str, object], task_id: str, index: int, errors: list[str]) -> None:
    text_parts: list[str] = []
    for field in ["failing_evidence", "implementation_summary", "dogfooding_implication"]:
        value = entry.get(field)
        if isinstance(value, str):
            text_parts.append(value)
    for field in ["tests_added", "tests_run", "follow_up_tasks"]:
        value = entry.get(field)
        if isinstance(value, list):
            text_parts.extend(item for item in value if isinstance(item, str))
    validator = entry.get("validator_result")
    if isinstance(validator, dict):
        text_parts.extend(item for item in validator.values() if isinstance(item, str))

    combined = "\n".join(text_parts)
    for label in PRE_063_CHRONOLOGY_LABELS:
        require(
            label in combined,
            errors,
            f"completion_evidence entry {index} for pre-063 behavior-changing task {task_id} must include structured chronology label {label!r}",
        )


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
        if task.get("state") != "superseded":
            required_tests = section_bullets(text, "Required tests")
            require(
                any("python3 scripts/validate_task_system.py" in item for item in required_tests),
                errors,
                f"{file_value} Required tests must include python3 scripts/validate_task_system.py",
            )

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
            require(ref.startswith("tasks/"), errors, f"{file_value} follow-up task reference must use canonical tasks/ path: {ref}")
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


def section_body(text: str, heading: str) -> str:
    match = re.search(rf"^## {re.escape(heading)}\n\n(?P<body>.*?)(?=\n## |\Z)", text, flags=re.MULTILINE | re.DOTALL)
    if match is None:
        return ""
    return match.group("body").strip()


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
    ordered_rows = [
        (match.group(2), {"order": match.group(1), "state": match.group(3).strip(), "phase": match.group(4).strip()})
        for match in QUEUE_ROW_RE.finditer(queue_text)
    ]
    rows = {file_value: row for file_value, row in ordered_rows}
    queue_files = {task.get("file") for task in tasks if isinstance(task.get("file"), str)}
    expected_files = [task.get("file") for task in tasks if isinstance(task.get("file"), str)]
    actual_files = [file_value for file_value, _row in ordered_rows]
    require(actual_files == expected_files, errors, "tasks/QUEUE.md row order must match queue.json execution order exactly")
    for file_value in sorted(set(rows) - queue_files):
        fail(errors, f"tasks/QUEUE.md has extra row not present in queue.json: {file_value}")
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


def git_stdout(args: list[str], errors: list[str], action: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        fail(errors, f"git {' '.join(args)} failed while {action}: {result.stderr.strip()}")
        return ""
    return result.stdout.strip()


def current_head_commit(errors: list[str]) -> str:
    return git_stdout(["rev-parse", "HEAD"], errors, "checking the clean handoff baseline source commit")


def is_project_relative_path(path: str) -> bool:
    posix_path = PurePosixPath(path)
    return bool(path) and not posix_path.is_absolute() and ".." not in posix_path.parts


def file_sha256(path: str) -> str | None:
    full_path = ROOT / path
    try:
        return hashlib.sha256(full_path.read_bytes()).hexdigest()
    except OSError:
        return None


def clean_handoff_baseline_file_hashes(status: object) -> dict[str, str]:
    if not isinstance(status, dict):
        return {}
    baseline = status.get("clean_handoff_baseline")
    if not isinstance(baseline, dict):
        return {}
    files = baseline.get("files")
    if not isinstance(files, list):
        return {}

    hashes: dict[str, str] = {}
    for entry in files:
        if not isinstance(entry, dict):
            continue
        path = entry.get("path")
        sha256 = entry.get("sha256")
        if isinstance(path, str) and isinstance(sha256, str) and SHA256_RE.match(sha256):
            hashes[path] = sha256
    return hashes


def validate_clean_handoff_baseline(
    status: dict[str, object],
    task_by_id: dict[str, dict[str, object]],
    errors: list[str],
) -> None:
    baseline = status.get("clean_handoff_baseline")
    if baseline is None:
        return
    require(isinstance(baseline, dict), errors, "status clean_handoff_baseline must be null or an object")
    if not isinstance(baseline, dict):
        return

    keys = set(baseline)
    for field in sorted(CLEAN_HANDOFF_BASELINE_FIELDS - keys):
        fail(errors, f"status clean_handoff_baseline missing field {field}")
    for field in sorted(keys - CLEAN_HANDOFF_BASELINE_FIELDS):
        fail(errors, f"status clean_handoff_baseline contains unknown field {field}")

    task_id = baseline.get("task")
    require(isinstance(task_id, str) and task_id in task_by_id, errors, "status clean_handoff_baseline.task must be a known task id")
    if isinstance(task_id, str) and task_id in task_by_id:
        require(task_by_id[task_id].get("state") == "complete", errors, "status clean_handoff_baseline.task must reference a complete task")

    source_commit = baseline.get("source_commit")
    require(isinstance(source_commit, str) and bool(source_commit.strip()), errors, "status clean_handoff_baseline.source_commit must be non-empty")
    notes = baseline.get("notes")
    require(isinstance(notes, str) and bool(notes.strip()), errors, "status clean_handoff_baseline.notes must be non-empty")

    files = baseline.get("files")
    require(isinstance(files, list), errors, "status clean_handoff_baseline.files must be an array")
    if not isinstance(files, list):
        return

    seen_paths: set[str] = set()
    for index, entry in enumerate(files):
        require(isinstance(entry, dict), errors, f"status clean_handoff_baseline.files[{index}] must be an object")
        if not isinstance(entry, dict):
            continue
        entry_keys = set(entry)
        for field in sorted(CLEAN_HANDOFF_BASELINE_FILE_FIELDS - entry_keys):
            fail(errors, f"status clean_handoff_baseline.files[{index}] missing field {field}")
        for field in sorted(entry_keys - CLEAN_HANDOFF_BASELINE_FILE_FIELDS):
            fail(errors, f"status clean_handoff_baseline.files[{index}] contains unknown field {field}")

        path = entry.get("path")
        sha256 = entry.get("sha256")
        require(isinstance(path, str) and is_project_relative_path(path), errors, f"status clean_handoff_baseline.files[{index}].path must be project-relative")
        require(isinstance(sha256, str) and SHA256_RE.match(sha256) is not None, errors, f"status clean_handoff_baseline.files[{index}].sha256 must be a lowercase SHA-256 hex digest")
        if not isinstance(path, str) or not isinstance(sha256, str):
            continue
        require(path not in seen_paths, errors, f"status clean_handoff_baseline duplicates file {path}")
        seen_paths.add(path)
        current_sha = file_sha256(path)
        require(current_sha == sha256, errors, f"status clean_handoff_baseline file {path} does not match recorded sha256")

    raw_changed = changed_files_against_head(errors)
    if not raw_changed:
        fail(errors, "status clean_handoff_baseline must be null when the worktree is clean")
    elif isinstance(source_commit, str):
        require(source_commit == current_head_commit(errors), errors, "status clean_handoff_baseline.source_commit must match current HEAD while dirty files are baselined")


def path_matches(path: str, pattern: str) -> bool:
    return path == pattern or fnmatch.fnmatchcase(path, pattern)


def path_matches_any(path: str, patterns: object) -> bool:
    return isinstance(patterns, list) and any(isinstance(pattern, str) and path_matches(path, pattern) for pattern in patterns)


def changed_files_against_head(errors: list[str]) -> list[str]:
    def git_names(args: list[str]) -> set[str]:
        result = subprocess.run(
            ["git", *args],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            fail(errors, f"git {' '.join(args)} failed while checking active task scope: {result.stderr.strip()}")
            return set()
        return {line.strip() for line in result.stdout.splitlines() if line.strip()}

    changed = git_names(["diff", "--name-only", "HEAD", "--"])
    changed.update(git_names(["ls-files", "--others", "--exclude-standard"]))
    return sorted(changed)


def changed_files_since_clean_handoff(status: object, errors: list[str]) -> list[str]:
    baseline_hashes = clean_handoff_baseline_file_hashes(status)
    changed: list[str] = []
    for path in changed_files_against_head(errors):
        if path in TASK_CONTROL_FILES:
            continue
        if baseline_hashes.get(path) == file_sha256(path):
            continue
        changed.append(path)
    return changed


def file_text_at_head(path: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"HEAD:{path}"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def latest_completed_evidence(status: dict[str, object]) -> dict[str, object] | None:
    completed = status.get("completed_tasks")
    evidence = status.get("completion_evidence")
    if not isinstance(completed, list) or not completed:
        return None
    if not isinstance(evidence, list):
        return None
    latest = completed[-1]
    if not isinstance(latest, str):
        return None
    for entry in evidence:
        if isinstance(entry, dict) and entry.get("task") == latest:
            return entry
    return None


def registry_row_id(entry: object) -> str | None:
    if not isinstance(entry, dict):
        return None
    for key in ("number", "operator", "version"):
        value = entry.get(key)
        if isinstance(value, str):
            return value
    return None


def registry_rows_by_id(data: object) -> dict[str, object]:
    if not isinstance(data, dict):
        return {}
    entries = data.get("entries")
    if not isinstance(entries, list):
        return {}
    rows: dict[str, object] = {}
    for entry in entries:
        row_id = registry_row_id(entry)
        if row_id is not None:
            rows[row_id] = entry
    return rows


def changed_gap_registry_rows_since_head(path: str, errors: list[str]) -> set[str]:
    current_path = ROOT / path
    current_data = load_json(current_path, errors)
    previous_text = file_text_at_head(path)
    if previous_text is None:
        return set(registry_rows_by_id(current_data))
    try:
        previous_data = json.loads(previous_text)
    except json.JSONDecodeError as exc:
        fail(errors, f"HEAD version of {path} is invalid JSON: {exc}")
        return set()

    current_rows = registry_rows_by_id(current_data)
    previous_rows = registry_rows_by_id(previous_data)
    changed: set[str] = set()
    for row_id in set(current_rows) | set(previous_rows):
        current_row = current_rows.get(row_id)
        previous_row = previous_rows.get(row_id)
        if json.dumps(current_row, sort_keys=True) != json.dumps(previous_row, sort_keys=True):
            changed.add(row_id)
    return changed


def task_is_complete(tasks: list[dict[str, object]], task_id: str) -> bool:
    return any(task.get("id") == task_id and task.get("state") == "complete" for task in tasks)


def is_global_scope_exception(path: str, active_task_id: str, tasks: list[dict[str, object]]) -> bool:
    if path in TASK_CONTROL_FILES:
        return True
    if path == ROOT_MODULE_FILE:
        return True
    if re.match(r"^tests/coverage-gaps/[^/]+\.v1\.json$", path):
        return True
    if task_is_complete(tasks, "041") and path_matches(path, f"artifacts/pipeline/{active_task_id}/**"):
        return True
    return False


def validate_active_task_changed_file_scope(status: object, tasks: list[dict[str, object]], errors: list[str]) -> None:
    if not isinstance(status, dict):
        return
    active_task_id = status.get("active_task")
    if not isinstance(active_task_id, str):
        return
    task_by_id = {task["id"]: task for task in tasks if isinstance(task.get("id"), str)}
    active_task = task_by_id.get(active_task_id)
    if active_task is None:
        return

    allowed_files = active_task.get("allowed_files")
    forbidden_files = active_task.get("forbidden_files")
    for path in changed_files_since_clean_handoff(status, errors):
        if path_matches_any(path, forbidden_files):
            fail(errors, f"changed file {path} is forbidden by active task {active_task_id}")
            continue
        if is_global_scope_exception(path, active_task_id, tasks):
            continue
        if not path_matches_any(path, allowed_files):
            fail(errors, f"changed file {path} is outside active task {active_task_id} allowed_files")


def validate_inactive_changed_file_scope(status: object, tasks: list[dict[str, object]], errors: list[str]) -> None:
    if not isinstance(status, dict):
        return
    if isinstance(status.get("active_task"), str):
        return

    changed = changed_files_since_clean_handoff(status, errors)
    if not changed:
        return

    evidence = latest_completed_evidence(status)
    if evidence is None:
        fail(errors, "dirty files exist with no active task and no latest completion_evidence entry")
        return

    files_changed = evidence.get("files_changed")
    task_id = evidence.get("task")
    if not isinstance(files_changed, list) or not isinstance(task_id, str):
        fail(errors, "dirty files exist with no active task but latest completion_evidence is incomplete")
        return

    recorded = {path for path in files_changed if isinstance(path, str)}
    for path in changed:
        require(
            path in recorded,
            errors,
            f"dirty file {path} is not listed in latest completion_evidence.files_changed for task {task_id}",
        )


def validate_inactive_gap_registry_row_scope(status: object, errors: list[str]) -> None:
    if not isinstance(status, dict):
        return
    if isinstance(status.get("active_task"), str):
        return

    dirty_registries = [
        path
        for path in changed_files_since_clean_handoff(status, errors)
        if re.match(r"^tests/coverage-gaps/[^/]+\.v1\.json$", path)
    ]
    if not dirty_registries:
        return

    evidence = latest_completed_evidence(status)
    if evidence is None:
        fail(errors, "dirty gap registry files exist with no latest completion_evidence entry")
        return
    gap_rows = evidence.get("gap_registry_rows_changed")
    if not isinstance(gap_rows, dict):
        fail(errors, "dirty gap registry files require latest completion_evidence.gap_registry_rows_changed")
        return

    for path in dirty_registries:
        declared_rows = gap_rows.get(path)
        actual_rows = changed_gap_registry_rows_since_head(path, errors)
        require(
            isinstance(declared_rows, list),
            errors,
            f"latest completion_evidence.gap_registry_rows_changed must list rows for dirty registry {path}",
        )
        if not isinstance(declared_rows, list):
            continue
        declared = {row for row in declared_rows if isinstance(row, str)}
        require(
            declared == actual_rows,
            errors,
            f"latest completion_evidence.gap_registry_rows_changed for {path} must match actual changed rows {sorted(actual_rows)}",
        )


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
            schema = load_json(path, errors)
            if rel == "tasks/schema/status.v1.schema.json" and isinstance(schema, dict):
                required_fields = schema.get("required")
                properties = schema.get("properties")
                require(isinstance(required_fields, list) and "completion_evidence" in required_fields, errors, "status schema must require completion_evidence")
                require(isinstance(properties, dict) and "completion_evidence" in properties, errors, "status schema must define completion_evidence")
                require(isinstance(required_fields, list) and "clean_handoff_baseline" in required_fields, errors, "status schema must require clean_handoff_baseline")
                require(isinstance(properties, dict) and "clean_handoff_baseline" in properties, errors, "status schema must define clean_handoff_baseline")
                require(isinstance(required_fields, list) and "blocked_task_details" in required_fields, errors, "status schema must require blocked_task_details")
                require(isinstance(properties, dict) and "blocked_task_details" in properties, errors, "status schema must define blocked_task_details")
                baseline_schema = properties.get("clean_handoff_baseline") if isinstance(properties, dict) else None
                baseline_text = json.dumps(baseline_schema, sort_keys=True)
                require("sha256" in baseline_text, errors, "status schema clean_handoff_baseline must record sha256 values")
                require("source_commit" in baseline_text, errors, "status schema clean_handoff_baseline must record source_commit")
                blocked_schema = properties.get("blocked_task_details") if isinstance(properties, dict) else None
                blocked_item = blocked_schema.get("items") if isinstance(blocked_schema, dict) else None
                blocked_required = blocked_item.get("required") if isinstance(blocked_item, dict) else None
                require(isinstance(blocked_required, list) and set(BLOCKED_TASK_DETAIL_FIELDS).issubset(set(blocked_required)), errors, "status schema blocked_task_details must require typed blocker metadata fields")
                completion_schema = properties.get("completion_evidence") if isinstance(properties, dict) else None
                completion_item = completion_schema.get("items") if isinstance(completion_schema, dict) else None
                completion_properties = completion_item.get("properties") if isinstance(completion_item, dict) else None
                require(isinstance(completion_properties, dict) and "artifacts" in completion_properties, errors, "status schema completion_evidence must define optional artifacts")


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
            "Only one task may be `active` pending completion at a time." in text,
            errors,
            ".agents/ORCHESTRATOR.md must include active-only single-task wording",
        )
        require(
            "More than one task is active pending completion." in text,
            errors,
            ".agents/ORCHESTRATOR.md stop conditions must use active-only task-control wording",
        )
        require(
            "queued -> active -> implemented -> verified -> complete" not in text,
            errors,
            ".agents/ORCHESTRATOR.md contains stale implemented/verified task-control state machine",
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
        require("04-contract-editor.json" in text and "05-test-author.json" in text, errors, "docs/HANDOFF_CONTRACTS.md must list deterministic JSON handoff names including the Contract Editor slot")

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

    # Task 040 pipeline foundation: the agent task pipeline must be discoverable
    # and terminologically consistent from the checked-in specs.
    arch = ROOT / "docs" / "AGENT_PIPELINE_ARCHITECTURE.md"
    role_spec = ROOT / "docs" / "AGENT_ROLE_SPEC.md"
    guide = ROOT / "docs" / "AGENT_GUIDE.md"
    # Canonical pipeline stages and the named roles in the architecture flow.
    pipeline_stages = ["Phase Planner", "Task Queue Manager", "Orchestrator", "Stateless Subagents"]
    pipeline_roles = [
        "Phase Planner",
        "Task Queue Manager",
        "Orchestrator",
        "Test Author",
        "Test Reviewer",
        "Contract Editor",
        "Implementer",
        "Implementation Reviewer",
        "Mutation Agent",
        "Mutation Triage Agent",
        "Property Test Agent",
        "Doctest Agent",
        "Verifier",
    ]
    require(arch.is_file(), errors, "missing docs/AGENT_PIPELINE_ARCHITECTURE.md")
    if arch.is_file():
        atext = arch.read_text(encoding="utf-8")
        for stage in pipeline_stages:
            require(stage in atext, errors, f"docs/AGENT_PIPELINE_ARCHITECTURE.md must name the pipeline stage '{stage}'")
    if role_spec.is_file():
        rtext = role_spec.read_text(encoding="utf-8")
        for role in pipeline_roles:
            require(role in rtext, errors, f"docs/AGENT_ROLE_SPEC.md must define the pipeline role '{role}'")
    if guide.is_file():
        gtext = guide.read_text(encoding="utf-8")
        require("docs/AGENT_PIPELINE_ARCHITECTURE.md" in gtext, errors, "docs/AGENT_GUIDE.md must point future agents to docs/AGENT_PIPELINE_ARCHITECTURE.md")

    # I-019 TDD-first wording is preserved, but I-019 stays uncovered: mechanical
    # chronology proof is deferred to task 063 (do not mark I-019 covered here).
    inv = ROOT / "tests" / "coverage-gaps" / "invariants.v1.json"
    if inv.is_file():
        idata = json.loads(inv.read_text(encoding="utf-8"))
        i019 = next((e for e in idata.get("entries", []) if e.get("number") == "I-019"), None)
        require(i019 is not None, errors, "invariants registry must keep I-019")
        if i019 is not None:
            # Task 063 implements and self-tests the role-timestamp chronology
            # validator (validate_pipeline_metadata), so I-019 is now covered; the
            # TDD-first wording must still be preserved.
            require(i019.get("covered") is True, errors, "I-019 is covered by the task 063 role-timestamp chronology validator")
            require("before implementation" in (i019.get("notes") or ""), errors, "I-019 must preserve TDD-first wording (failing evidence recorded before implementation)")


PIPELINE_SCHEMA_BY_VERSION = {
    "zentinel.pipeline.handoff.v1": "schemas/pipeline.handoff.v1.schema.json",
    "zentinel.pipeline.active_lock.v1": "schemas/pipeline.active_lock.v1.schema.json",
    "zentinel.pipeline.context.v1": "schemas/pipeline.context.v1.schema.json",
    "zentinel.pipeline.stale_context.v1": "schemas/pipeline.stale_context.v1.schema.json",
    "zentinel.pipeline.verification.v1": "schemas/pipeline.verification.v1.schema.json",
    "zentinel.pipeline.escalation.v1": "schemas/pipeline.escalation.v1.schema.json",
}
_PIPELINE_SCHEMA_CACHE: dict[str, object] = {}


def _subset_type_ok(instance: object, type_name: str) -> bool:
    if type_name == "string":
        return isinstance(instance, str)
    if type_name == "integer":
        return isinstance(instance, int) and not isinstance(instance, bool)
    if type_name == "number":
        return isinstance(instance, (int, float)) and not isinstance(instance, bool)
    if type_name == "boolean":
        return isinstance(instance, bool)
    if type_name == "null":
        return instance is None
    if type_name == "object":
        return isinstance(instance, dict)
    if type_name == "array":
        return isinstance(instance, list)
    return True


def subset_validate(instance: object, schema: dict, loc: str) -> list[str]:
    """Project-owned JSON Schema SUBSET validator for pipeline artifacts. NOT full
    Draft 2020-12: it supports type, required, additionalProperties:false, const,
    enum, pattern, nested properties, and array items only -- no conditionals,
    no arbitrary $ref traversal, no derived invariants. Returns violation strings."""
    out: list[str] = []
    if "const" in schema and instance != schema["const"]:
        out.append(f"{loc}: value does not match const {schema['const']!r}")
        return out
    if "enum" in schema and instance not in schema["enum"]:
        out.append(f"{loc}: value {instance!r} not in enum {schema['enum']}")
    declared_type = schema.get("type")
    if declared_type is not None:
        types = declared_type if isinstance(declared_type, list) else [declared_type]
        if not any(_subset_type_ok(instance, t) for t in types):
            out.append(f"{loc}: type {type(instance).__name__} not allowed (expected {types})")
            return out
    if "pattern" in schema and isinstance(instance, str):
        if re.match(schema["pattern"], instance) is None:
            out.append(f"{loc}: value {instance!r} does not match pattern {schema['pattern']}")
    if isinstance(instance, dict) and ("properties" in schema or schema.get("type") == "object"):
        props = schema.get("properties", {})
        for field in schema.get("required", []):
            if field not in instance:
                out.append(f"{loc}.{field}: missing required field")
        if schema.get("additionalProperties") is False:
            for key in instance:
                if key not in props:
                    out.append(f"{loc}.{key}: unknown field not allowed by schema")
        for key, value in instance.items():
            if key in props:
                out += subset_validate(value, props[key], f"{loc}.{key}")
    if isinstance(instance, list) and "items" in schema:
        for idx, item in enumerate(instance):
            out += subset_validate(item, schema["items"], f"{loc}[{idx}]")
    return out


def _load_pipeline_schema(version: str):
    rel = PIPELINE_SCHEMA_BY_VERSION.get(version)
    if rel is None:
        return None
    if rel not in _PIPELINE_SCHEMA_CACHE:
        try:
            _PIPELINE_SCHEMA_CACHE[rel] = json.loads((ROOT / rel).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
    schema = _PIPELINE_SCHEMA_CACHE[rel]
    return schema if isinstance(schema, dict) else None


def _load_json_or_none(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def validate_pipeline_artifact_tree(root) -> list[str]:
    """Validate one artifact tree rooted at <root>/artifacts/pipeline/<task-id>/.
    Deterministic and task-scoped; returns a list of violations (empty = valid)."""
    violations: list[str] = []
    pipeline_root = root / "artifacts" / "pipeline"
    if not pipeline_root.is_dir():
        return ["no artifacts/pipeline directory"]
    for task_dir in sorted(p for p in pipeline_root.iterdir() if p.is_dir()):
        task_id = task_dir.name
        handoff_dir = task_dir / "handoffs"
        handoffs: list = []
        if handoff_dir.is_dir():
            json_stems = {p.stem for p in handoff_dir.glob("*.json")}
            for md in sorted(handoff_dir.glob("*.md")):
                if md.stem not in json_stems:
                    violations.append(f"{md.relative_to(root)}: Markdown handoff without the required canonical JSON handoff")
            for hj in sorted(handoff_dir.glob("*.json")):
                data = _load_json_or_none(hj)
                if not isinstance(data, dict):
                    violations.append(f"{hj.relative_to(root)}: not a JSON object")
                    continue
                schema = _load_pipeline_schema("zentinel.pipeline.handoff.v1")
                if schema is not None:
                    violations += subset_validate(data, schema, str(hj.relative_to(root)))
                if data.get("task_id") != task_id:
                    violations.append(f"{hj.relative_to(root)}: task_id {data.get('task_id')!r} does not match artifact directory task {task_id}")
                handoffs.append((hj.name, data))
            ta = next((d for n, d in handoffs if "test-author" in n), None)
            impl = next((d for n, d in handoffs if "implementer" in n), None)
            if ta is not None and impl is not None:
                ta_t, impl_t = ta.get("created_at"), impl.get("created_at")
                if isinstance(ta_t, str) and isinstance(impl_t, str) and ta_t >= impl_t:
                    violations.append(f"{task_dir.relative_to(root)}: I-019 chronology violation: Test Author handoff {ta_t} is not before Implementer handoff {impl_t}")
        lock = task_dir / "locks" / "active-task-lock.json"
        if lock.is_file():
            data = _load_json_or_none(lock)
            if not isinstance(data, dict):
                violations.append(f"{lock.relative_to(root)}: not a JSON object")
            else:
                schema = _load_pipeline_schema("zentinel.pipeline.active_lock.v1")
                if schema is not None:
                    violations += subset_validate(data, schema, str(lock.relative_to(root)))
                if data.get("task_id") != task_id:
                    violations.append(f"{lock.relative_to(root)}: active lock task_id {data.get('task_id')!r} does not match artifact directory task {task_id}")
                cp = data.get("context_packet")
                if isinstance(cp, str) and f"/pipeline/{task_id}/" not in cp:
                    violations.append(f"{lock.relative_to(root)}: context_packet {cp!r} is not under task {task_id}")
        context_dir = task_dir / "context"
        if context_dir.is_dir():
            for cj in sorted(context_dir.glob("*.json")):
                data = _load_json_or_none(cj)
                if not isinstance(data, dict):
                    violations.append(f"{cj.relative_to(root)}: not a JSON object")
                    continue
                schema = _load_pipeline_schema("zentinel.pipeline.context.v1")
                if schema is not None:
                    violations += subset_validate(data, schema, str(cj.relative_to(root)))
    return violations


def validate_pipeline_metadata(errors: list[str]) -> None:
    """Self-test the project-owned pipeline metadata subset validator: the valid
    fixture tree must pass with no violations, and every invalid fixture tree
    must be rejected by at least one deterministic violation."""
    base = ROOT / "test" / "fixtures" / "pipeline" / "metadata_validator"
    if not base.is_dir():
        return
    valid_root = base / "valid"
    if valid_root.is_dir():
        valid_violations = validate_pipeline_artifact_tree(valid_root)
        require(not valid_violations, errors, f"valid pipeline artifact tree must pass the metadata validator but found: {valid_violations}")
    invalid_root = base / "invalid"
    if invalid_root.is_dir():
        for case in sorted(p for p in invalid_root.iterdir() if p.is_dir()):
            case_violations = validate_pipeline_artifact_tree(case)
            require(bool(case_violations), errors, f"invalid pipeline fixture {case.name} must be rejected by the metadata validator")


# Failure-recovery transition validator (task 065). The deterministic recovery
# state machine, valid transitions, and invariants are documented in
# docs/FAILURE_RECOVERY.md; this validator enforces them over the
# zentinel.pipeline.failure_recovery_transition.v1 artifact so a failed gate
# cannot be marked complete without auditable recovery evidence.
FAILURE_RECOVERY_SCHEMA = "zentinel.pipeline.failure_recovery_transition.v1"

# Documented retry limits keyed by task class (docs/FAILURE_RECOVERY.md Retry Limits).
FAILURE_RECOVERY_RETRY_LIMITS = {
    "low_risk": 1,
    "normal": 2,
    "high_risk": 3,
    "compiler_internal": 3,
    "architecture": 1,
}

# The only valid (from_state, trigger, to_state) transitions, expanded from the
# "/"-alternatives in the docs/FAILURE_RECOVERY.md Recovery Transitions table.
FAILURE_RECOVERY_TRANSITIONS = {
    ("active", "required_stages_passed", "complete"),
    ("active", "required_stage_failed", "failed_implementation"),
    ("active", "mutation_gate_blocked", "failed_mutation_gate"),
    ("active", "flaky_result", "flaky_verification"),
    ("active", "blocker_detected", "blocked"),
    ("failed_implementation", "bounded_fix_within_limit", "active"),
    ("failed_implementation", "retry_limit_exhausted", "escalated"),
    ("failed_implementation", "unrelated_user_edits", "rollback_required"),
    ("failed_mutation_gate", "missing_tests", "return_to_role"),
    ("failed_mutation_gate", "out_of_scope_survivor", "follow_up_created"),
    ("failed_mutation_gate", "needs_architecture_review", "escalated"),
    ("failed_mutation_gate", "invalid_mutants", "failed_implementation"),
    ("failed_mutation_gate", "baseline_failure", "failed_implementation"),
    ("flaky_verification", "reproduced_deterministic", "failed_implementation"),
    ("flaky_verification", "normalized_and_passed", "active"),
    ("blocked", "prerequisite_complete", "active"),
    ("rollback_required", "agent_edits_reverted", "blocked"),
    ("rollback_required", "agent_edits_reverted", "follow_up_created"),
    ("return_to_role", "tests_added", "active"),
    ("follow_up_created", "follow_up_queued", "complete"),
    ("escalated", "reviewer_resolution", "active"),
    ("escalated", "reviewer_resolution", "blocked"),
}

# The two (from_state, trigger) pairs that may legitimately reach `complete`.
FAILURE_RECOVERY_COMPLETE_SOURCES = {
    ("active", "required_stages_passed"),
    ("follow_up_created", "follow_up_queued"),
}


def validate_failure_recovery_record(record: dict, loc: str) -> list[str]:
    """Validate one failure-recovery transition record against the deterministic
    recovery state machine in docs/FAILURE_RECOVERY.md. Returns a sorted list of
    stable, project-relative diagnostics (empty when the record is valid)."""
    v: list[str] = []

    def bad(msg: str) -> None:
        v.append(f"{loc}: {msg}")

    if record.get("schema_version") != FAILURE_RECOVERY_SCHEMA:
        bad(f"schema_version must be {FAILURE_RECOVERY_SCHEMA!r}")

    task_id = record.get("task_id")
    if not isinstance(task_id, str) or not task_id:
        bad("task_id must be a non-empty string")

    from_state = record.get("from_state")
    trigger = record.get("trigger")
    to_state = record.get("to_state")
    for name, value in (("from_state", from_state), ("trigger", trigger), ("to_state", to_state)):
        if not isinstance(value, str) or not value:
            bad(f"{name} must be a non-empty string")

    evidence = record.get("evidence")
    if not isinstance(evidence, str) or not evidence.strip():
        bad("evidence must be a non-empty string so the recovery is auditable")

    if record.get("auditable") is not True:
        bad("auditable must be true")

    # Retry block must match the documented Retry Limits table for its task class.
    retry = record.get("retry")
    cycle = limit = None
    if not isinstance(retry, dict):
        bad("retry must be an object with task_class, cycle, and limit")
    else:
        task_class = retry.get("task_class")
        cycle = retry.get("cycle")
        limit = retry.get("limit")
        if task_class not in FAILURE_RECOVERY_RETRY_LIMITS:
            bad(f"retry.task_class {task_class!r} is not a documented task class")
        if not isinstance(cycle, int) or isinstance(cycle, bool) or cycle < 1:
            bad("retry.cycle must be a positive integer")
            cycle = None
        if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1:
            bad("retry.limit must be a positive integer")
            limit = None
        elif task_class in FAILURE_RECOVERY_RETRY_LIMITS and limit != FAILURE_RECOVERY_RETRY_LIMITS[task_class]:
            bad(f"retry.limit {limit} does not match the documented limit {FAILURE_RECOVERY_RETRY_LIMITS[task_class]} for task class {task_class!r}")

    # Invariant: a flaky verification result is never waived.
    if trigger == "waived" or to_state == "waived":
        bad("a flaky_verification result is never waived; it must reproduce deterministically or normalize and pass")

    # Invariant: rollback evidence must be agent-owned and path-based.
    rollback = record.get("rollback")
    if rollback is not None:
        if not isinstance(rollback, dict):
            bad("rollback must be an object")
        else:
            if rollback.get("scope") != "agent_owned":
                bad("rollback.scope must be 'agent_owned'; reverting pre-existing user edits is not a valid recovery")
            changed_files = rollback.get("changed_files")
            if not isinstance(changed_files, list) or not changed_files or not all(isinstance(p, str) and p for p in changed_files):
                bad("rollback.changed_files must be a non-empty list of project-relative paths")
            elif any(p.startswith("/") or ".." in p.split("/") for p in changed_files):
                bad("rollback.changed_files must be project-relative paths without '..' or a leading '/'")
    if (from_state == "rollback_required" or to_state == "rollback_required") and not isinstance(rollback, dict):
        bad("a rollback_required transition must record agent-owned changed-file evidence under rollback.changed_files")

    # Invariant: a failure state never transitions directly to complete.
    if to_state == "complete" and (from_state, trigger) not in FAILURE_RECOVERY_COMPLETE_SOURCES:
        bad("a failure state cannot transition directly to complete; completion is only from (active, required_stages_passed) or (follow_up_created, follow_up_queued)")

    # Invariant: when retry.cycle exceeds retry.limit the only valid target is escalated.
    if isinstance(cycle, int) and isinstance(limit, int) and cycle > limit and to_state != "escalated":
        bad("retry.cycle exceeds retry.limit; the only valid transition is to 'escalated'")

    # Backstop: the (from_state, trigger, to_state) triple must be documented.
    if (
        isinstance(from_state, str)
        and isinstance(trigger, str)
        and isinstance(to_state, str)
        and (from_state, trigger, to_state) not in FAILURE_RECOVERY_TRANSITIONS
    ):
        bad(f"transition ({from_state} -{trigger}-> {to_state}) is not in the documented recovery state machine")

    return sorted(v)


def validate_failure_recovery(errors: list[str]) -> None:
    """Self-test the failure-recovery transition validator: every valid fixture
    must pass with no violations and every invalid fixture must be rejected by at
    least one deterministic violation."""
    base = ROOT / "test" / "fixtures" / "pipeline" / "failure_recovery_validator"
    if not base.is_dir():
        return
    valid_root = base / "valid"
    if valid_root.is_dir():
        for fx in sorted(valid_root.glob("*.json")):
            rel = str(fx.relative_to(ROOT))
            data = _load_json_or_none(fx)
            if not isinstance(data, dict):
                fail(errors, f"{rel}: valid failure-recovery fixture must be a JSON object")
                continue
            violations = validate_failure_recovery_record(data, rel)
            require(not violations, errors, f"valid failure-recovery fixture {fx.name} must pass but found: {violations}")
    invalid_root = base / "invalid"
    if invalid_root.is_dir():
        for fx in sorted(invalid_root.glob("*.json")):
            rel = str(fx.relative_to(ROOT))
            data = _load_json_or_none(fx)
            if not isinstance(data, dict):
                continue
            violations = validate_failure_recovery_record(data, rel)
            require(bool(violations), errors, f"invalid failure-recovery fixture {fx.name} must be rejected by the recovery validator")


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
            "Read the selected or active task file and required docs from `AGENTS.md` before changing implementation files.",
            "When starting a queued task, mark it `active` in `tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, and `tasks/STATUS.md`.",
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
        ".agents/workflows/sync.md": ["first dependency-ready queued task by execution order", "active task"],
        ".agents/roles/task-queue-manager.md": ["first dependency-ready queued task by execution order"],
        "docs/AGENT_ROLE_SPEC.md": ["at most one task is active pending completion"],
    }
    stale_phrases = [
        "first queued task",
        "active or implemented pending verification",
        "active, implemented, or verified pending completion",
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
    require("--input-report <path>" in cli_text, errors, "docs/CLI_SPEC.md must define AI input report path option")
    require("--report <path>" not in cli_text, errors, "docs/CLI_SPEC.md must not use --report for AI input report paths")
    require("zig-out/zentinel/report.json" in cli_text, errors, "docs/CLI_SPEC.md must define the default mutation AI report path")
    require("zig-out/zentinel/doctest/report.json" in cli_text, errors, "docs/CLI_SPEC.md must define the default doctest AI report path")
    require("Display IDs are scoped to the report" in cli_text, errors, "docs/CLI_SPEC.md must scope display IDs to the selected report")
    require("case anchor line" in cli_text, errors, "docs/CLI_SPEC.md must define doctest source refs as anchor-line selectors")
    require("--format <text|json>" in doctest_mutation_text, errors, "docs/DOCTEST_MUTATION_STRATEGY.md must use --format for output selection")
    require("--report <text|json>" not in doctest_mutation_text, errors, "docs/DOCTEST_MUTATION_STRATEGY.md must not use --report for doctest output format")

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
        require("--input-report <path>" in task054_text, errors, "tasks/054-ai-advisory-commands.md must require AI input report path tests")
        require("--report <path>" not in task054_text, errors, "tasks/054-ai-advisory-commands.md must not use --report for AI input report paths")

    if task055_path.is_file():
        task055_text = task055_path.read_text(encoding="utf-8")
        for required in ["src/cli.zig", "src/main.zig", "docs/CLI_SPEC.md", "schemas/ai.prompt.v1.schema.json", "test/ai_doctest_cli_test.zig"]:
            require(required in task055_text, errors, f"tasks/055-ai-doctest-assistance.md must allow {required}")
        require("zentinel doctest explain <case-ref>" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest explain CLI tests")
        require("zentinel doctest suggest <doc-path>" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must require doctest suggest CLI tests")
        require("--input-report" in task055_text, errors, "tasks/055-ai-doctest-assistance.md must use --input-report for optional report context")
        require("--report" not in task055_text, errors, "tasks/055-ai-doctest-assistance.md must not use --report for AI report input context")
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

    ai_integration_path = ROOT / "docs" / "DOCTEST_AI_INTEGRATION.md"
    survivor_examples = [
        value
        for value in markdown_json_objects(ai_integration_path, errors)
        if isinstance(value, dict) and value.get("kind") == "doctest_survivor"
    ]
    require(survivor_examples, errors, "docs/DOCTEST_AI_INTEGRATION.md must include a doctest_survivor JSON example")
    for index, example in enumerate(survivor_examples, start=1):
        source_case = example.get("source_case")
        mutation_case = example.get("mutation_case")
        require(isinstance(source_case, dict), errors, f"doctest_survivor example {index} source_case must be an object")
        require(isinstance(mutation_case, dict), errors, f"doctest_survivor example {index} mutation_case must be an object")
        if isinstance(source_case, dict):
            source_id = source_case.get("id")
            require(isinstance(source_id, str) and source_id.startswith("dt_"), errors, f"doctest_survivor example {index} source_case.id must use dt_ ordinary doctest case identity")
        if isinstance(mutation_case, dict):
            mutation_id = mutation_case.get("id")
            require(isinstance(mutation_id, str) and mutation_id.startswith("dm_"), errors, f"doctest_survivor example {index} mutation_case.id must use dm_ mutation-aware report entry identity")


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

    task025 = task_by_id.get("025")
    require(task025 is not None, errors, "task 025 must exist for backlog audit scope validation")
    if isinstance(task025, dict):
        allowed = task025.get("allowed_files")
        require(
            isinstance(allowed, list) and "tasks/[0-9][0-9][0-9]-*.md" in allowed,
            errors,
            "task 025 must allow next-unused task markdown creation when backlog audit finds a concrete gap",
        )

    required_phrases = {
        "tasks/000-project-bootstrap.md": [
            "top-level `test/*_test.zig`",
            "`test/bootstrap_discovery_test.zig`",
            "without per-task `build.zig` edits",
            "Add `test/bootstrap_test.zig` and `test/bootstrap_discovery_test.zig` before adding `build.zig`",
            "missing build scaffold or unresolved root-module import",
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
        "tasks/025-autonomous-backlog-audit.md": [
            "tasks/[0-9][0-9][0-9]-*.md",
            "next unused task file",
            "concrete missing task",
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
            "| Architecture | Phase Planner, Contract Editor, Architecture Reviewer, Test Reviewer for executable contracts, Verifier |",
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
            "refine the baseline context and stale-context schemas created by task `041`",
        ],
        "tasks/046-verification-pipeline.md": [
            "refine the baseline verification schema created by task `041`",
        ],
        "tasks/049-pipeline-escalation.md": [
            "refine the baseline escalation schema created by task `041`",
        ],
        "docs/SCHEMA_REGISTRY.md": [
            "Task `tasks/041-handoff-artifacts.md` creates the baseline pipeline handoff, active-lock, context, stale-context, verification, and escalation schema files.",
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
                require(entry.get("deferred_to") == "tasks/041-handoff-artifacts.md", errors, f"schemas.v1.json {version} must defer baseline schema creation to task 041")
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


def validate_dogfood_release_gate_sequence_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_by_id = {task.get("id"): task for task in tasks}
    task059 = task_by_id.get("059")
    task085 = task_by_id.get("085")
    task060 = task_by_id.get("060")

    require(not (ROOT / "tasks" / "059-production-dogfood-ci.md").exists(), errors, "task 059 must be renamed away from production dogfood wording")

    require(isinstance(task059, dict), errors, "task 059 must exist")
    if isinstance(task059, dict):
        require(task059.get("title") == "Initial Dogfood CI", errors, "task 059 title must be Initial Dogfood CI")
        require(task059.get("file") == "tasks/059-initial-dogfood-ci.md", errors, "task 059 file must be tasks/059-initial-dogfood-ci.md")

    require(isinstance(task085, dict), errors, "task 085 final release dogfood gate must exist")
    if isinstance(task085, dict):
        require(task085.get("title") == "Final Dogfood Release Gate", errors, "task 085 title must be Final Dogfood Release Gate")
        require(task085.get("file") == "tasks/085-final-dogfood-release-gate.md", errors, "task 085 file must be tasks/085-final-dogfood-release-gate.md")
        deps = task085.get("dependencies")
        require(isinstance(deps, list) and "067" in deps, errors, "task 085 must depend on task 067")

    if isinstance(task085, dict) and isinstance(task060, dict):
        require(order_key(task_order(task085)) < order_key(task_order(task060)), errors, "task 085 must execute before release acceptance task 060")
        deps060 = task060.get("dependencies")
        require(isinstance(deps060, list) and "085" in deps060, errors, "task 060 must depend on final dogfood gate task 085")

    task059_path = ROOT / "tasks" / "059-initial-dogfood-ci.md"
    task085_path = ROOT / "tasks" / "085-final-dogfood-release-gate.md"
    if task059_path.is_file():
        text059 = task059_path.read_text(encoding="utf-8")
        require("initial advisory dogfood" in text059, errors, "task 059 must describe initial advisory dogfood")
        require("not the final release dogfood gate" in text059, errors, "task 059 must state it is not the final release dogfood gate")
    if task085_path.is_file():
        text085 = task085_path.read_text(encoding="utf-8")
        require("final release dogfood gate" in text085, errors, "task 085 must describe the final release dogfood gate")
        require("after tasks `061`, `062`, `064`, `065`, `066`, and `067`" in text085, errors, "task 085 must name the late hardening tasks it follows")


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


def validate_analysis_findings_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    arch_path = ROOT / "docs" / "DOCTEST_ARCHITECTURE.md"
    block_path = ROOT / "docs" / "DOCTEST_BLOCK_FORMATS.md"
    task031_path = ROOT / "tasks" / "031-doctest-parser.md"
    version_policy_path = ROOT / "docs" / "ZIG_VERSION_POLICY.md"
    task005_path = ROOT / "tasks" / "005-version-policy.md"
    required_fence_phrase = "Supported doctest fences use exactly three or four backticks."

    for path in [arch_path, block_path, task031_path, version_policy_path, task005_path]:
        require(path.is_file(), errors, f"missing analysis-closure contract file {path.relative_to(ROOT)}")
    if not all(path.is_file() for path in [arch_path, block_path, task031_path, version_policy_path, task005_path]):
        return

    arch_text = arch_path.read_text(encoding="utf-8")
    block_text = block_path.read_text(encoding="utf-8")
    task031_text = task031_path.read_text(encoding="utf-8")
    version_policy_text = version_policy_path.read_text(encoding="utf-8")
    task005_text = task005_path.read_text(encoding="utf-8")

    require(required_fence_phrase in arch_text, errors, "docs/DOCTEST_ARCHITECTURE.md must define exact supported doctest fence lengths")
    require(required_fence_phrase in block_text, errors, "docs/DOCTEST_BLOCK_FORMATS.md must define exact supported doctest fence lengths")
    require("opening and closing fence lengths must match Markdown rules" not in block_text, errors, "docs/DOCTEST_BLOCK_FORMATS.md must not leave fence length to generic Markdown rules")
    require("five-backtick" in task031_text and "documentation-only" in task031_text, errors, "tasks/031-doctest-parser.md must test unsupported five-backtick fences as documentation-only")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task000 = task_by_id.get("000")
    require(isinstance(task000, dict), errors, "task 000 must exist for task-control scope validation")
    if isinstance(task000, dict):
        allowed = task000.get("allowed_files")
        require(isinstance(allowed, list), errors, "task 000 allowed_files must be an array")
        if isinstance(allowed, list):
            for task_control_file in sorted(TASK_CONTROL_FILES):
                require(task_control_file in allowed, errors, f"task 000 must explicitly allow task-control file {task_control_file}")

    require("<detected-version>" in version_policy_text, errors, "docs/ZIG_VERSION_POLICY.md diagnostic example must include <detected-version>")
    require(PINNED_ZIG_VERSION in version_policy_text, errors, f"docs/ZIG_VERSION_POLICY.md must pin Zig {PINNED_ZIG_VERSION}")
    require("No live latest-stable lookup is required for task `005`." in version_policy_text, errors, "docs/ZIG_VERSION_POLICY.md must remove task 005 live latest-stable lookup")
    require(PINNED_ZIG_VERSION in task005_text, errors, f"tasks/005-version-policy.md must pin Zig {PINNED_ZIG_VERSION}")
    require("No live latest-stable lookup is required." in task005_text, errors, "tasks/005-version-policy.md must remove live latest-stable lookup")

    for task in tasks:
        task_id = task.get("id")
        file_value = task.get("file")
        if not isinstance(task_id, str) or not isinstance(file_value, str):
            continue
        path = ROOT / file_value
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for heading in LEGACY_GATE_HEADINGS:
            legacy_heading = re.search(rf"^{re.escape(heading)}$", text, flags=re.MULTILINE)
            require(legacy_heading is None, errors, f"{file_value} must use canonical gate heading instead of {heading}")
        if task_id in PROPERTY_GATE_TASK_IDS:
            require("## Required property tests" in text, errors, f"{file_value} must include canonical Required property tests section")
        if task_id in DOCTEST_GATE_TASK_IDS:
            require("## Required doctests" in text, errors, f"{file_value} must include canonical Required doctests section")
        for heading in CANONICAL_GATE_SECTIONS:
            if f"## {heading}" in text:
                require(bool(section_body(text, heading)), errors, f"{file_value} section {heading!r} must not be empty")


def validate_agent_tooling_contract_hardening_contracts(errors: list[str]) -> None:
    queue_schema = load_json(QUEUE_SCHEMA_JSON, errors)
    if isinstance(queue_schema, dict):
        required = (
            queue_schema.get("properties", {})
            .get("tasks", {})
            .get("items", {})
            .get("required")
        )
        require(isinstance(required, list) and "order" in required, errors, "tasks/schema/queue.v1.schema.json must require task order")

    required_phrases = {
        "docs/SEQUENTIAL_EXECUTION_POLICY.md": [
            "Every task entry in `tasks/queue.json` contains an explicit `order` key.",
        ],
        "docs/AGENT_GUIDE.md": [
            "Every task entry in `tasks/queue.json` contains an explicit `order` key.",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Every task entry in `tasks/queue.json` contains an explicit `order` key.",
        ],
        "docs/REPORT_FORMAT.md": [
            "JSON Schema validation checks report shape",
            "deterministic semantic validation must also verify derived invariants",
            "summary counts match the `mutants` entries",
        ],
        "tasks/006-report-schema.md": [
            "deterministic report semantic validator",
            "schema validation is not the only report oracle",
            "summary counts match the serialized `mutants` entries",
        ],
        "docs/ZIG_VERSION_POLICY.md": [
            "durable verification evidence",
            "pinned supported Zig version",
            "0.16.0",
            "local `zig version`",
            "match or mismatch result",
            "No live latest-stable lookup is required for task `005`.",
        ],
        "tasks/005-version-policy.md": [
            "durable verification evidence",
            "pinned supported Zig version",
            "0.16.0",
            "local `zig version`",
            "match or mismatch result",
            "No live latest-stable lookup is required.",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing agent-tooling contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain agent-tooling contract phrase '{phrase}'")


def validate_contract_traceability_and_scope_hardening_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 090 contracts so future agents do not reintroduce analysis blockers."""
    error_codes_path = ROOT / "docs" / "ERROR_CODES.md"
    failure_modes_path = ROOT / "docs" / "FAILURE_MODES.md"
    for path in [error_codes_path, failure_modes_path]:
        require(path.is_file(), errors, f"missing contract hardening file {path.relative_to(ROOT)}")
    if error_codes_path.is_file() and failure_modes_path.is_file():
        error_text = error_codes_path.read_text(encoding="utf-8")
        failure_text = failure_modes_path.read_text(encoding="utf-8")
        for code in sorted(set(ERROR_CODE_RE.findall(error_text))):
            require(code in failure_text, errors, f"docs/FAILURE_MODES.md must trace public error code {code}")
        require(
            "not the pinned supported Zig version for this zentinel release" in error_text,
            errors,
            "docs/ERROR_CODES.md must describe unsupported Zig as pinned-version mismatch",
        )

    required_phrases = {
        "AGENTS.md": [
            "Support only pinned Zig `0.16.0` for this zentinel version.",
        ],
        "docs/VISION.md": [
            "Pinned Zig 0.16.0 only",
        ],
        "docs/NON_GOALS.md": [
            "Zig versions other than the pinned supported version. [never]",
            "Preview mutator implementation in the minimum complete product. [not v1]",
        ],
        "docs/INVARIANTS.md": [
            f"**I-006.** zentinel supports exactly Zig `{PINNED_ZIG_VERSION}` for this zentinel version.",
        ],
        "docs/ZIG_VERSION_POLICY.md": [
            f"zentinel pins Zig `{PINNED_ZIG_VERSION}` for this zentinel version.",
            "No live latest-stable lookup is required for task `005`.",
        ],
        "tasks/005-version-policy.md": [
            f"pinned supported Zig version `{PINNED_ZIG_VERSION}`",
            "No live latest-stable lookup is required.",
        ],
        "docs/CONFIG_SPEC.md": [
            'version = "0.16.0"',
            "| `version` | string | `0.16.0` |",
        ],
        "docs/CLI_SPEC.md": [
            "zig 0.16.0",
        ],
        "docs/ZIG_SEMANTICS.md": [
            "zentinel supports exactly Zig `0.16.0` for this zentinel version.",
        ],
        "docs/TDD_POLICY.md": [
            "A successful `python3 scripts/validate_task_system.py` run is not product proof.",
            "does not replace the active task's failing evidence",
        ],
        "docs/AGENT_GUIDE.md": [
            "validator pass is not product proof",
            "does not replace task-specific failing evidence",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "validator pass is not product proof",
            "does not replace task-specific failing evidence",
        ],
        "docs/MUTATOR_SPEC.md": [
            "End-to-end completion excludes preview mutator implementation.",
        ],
        "docs/PROJECT_ACCEPTANCE_CRITERIA.md": [
            "End-to-end completion excludes preview mutator implementation.",
        ],
        "docs/ROADMAP.md": [
            "End-to-end completion excludes preview mutator implementation.",
        ],
        "docs/adr/README.md": [
            "ADR-0007",
            "Pin Zig 0.16.0 for this zentinel version",
        ],
        "docs/adr/0001-latest-stable-zig-only.md": [
            "Superseded by ADR-0007",
        ],
        "docs/adr/0007-pin-zig-0-16-0.md": [
            "# ADR-0007: Pin Zig 0.16.0 for this zentinel version",
            f"Zig `{PINNED_ZIG_VERSION}`",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing contract hardening file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain contract hardening phrase '{phrase}'")

    forbidden_phrases = {
        "AGENTS.md": [
            "Support only latest stable Zig.",
        ],
        "docs/CONFIG_SPEC.md": [
            'version = "latest-stable"',
            "| `version` | string | `latest-stable` |",
        ],
        "docs/CLI_SPEC.md": [
            "zig latest-stable",
        ],
        "docs/ZIG_SEMANTICS.md": [
            "supports only the latest stable Zig version",
        ],
        "docs/ZIG_VERSION_POLICY.md": [
            "Current latest stable Zig release",
            "official latest stable Zig release",
            "intentionally tracks latest stable Zig",
        ],
        "tasks/005-version-policy.md": [
            "official latest stable Zig",
            "A local `zig version` result alone is not enough",
            "latest-stable selection",
        ],
        "docs/VISION.md": [
            "Latest stable Zig only",
        ],
        "docs/NON_GOALS.md": [
            "targets only the latest stable Zig release",
        ],
        "docs/INVARIANTS.md": [
            "latest stable Zig release",
        ],
    }
    for rel, phrases in forbidden_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing stale contract hardening file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase not in text, errors, f"{rel} contains stale contract hardening phrase '{phrase}'")

    gap_path = GAP_REGISTRY_DIR / "mutators.v1.json"
    if gap_path.is_file():
        data = load_json(gap_path, errors)
        entries = data.get("entries") if isinstance(data, dict) else None
        if isinstance(entries, list):
            for entry in entries:
                if not isinstance(entry, dict) or entry.get("stability") != "preview":
                    continue
                require(
                    entry.get("deferred_to") == "preview backlog after minimum complete product",
                    errors,
                    f"preview mutator {entry.get('operator')} must defer to preview backlog after minimum complete product",
                )

    for task in tasks:
        if task.get("state") not in {"queued", "active"}:
            continue
        file_value = task.get("file")
        if not isinstance(file_value, str):
            continue
        path = ROOT / file_value
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        required_tests = section_bullets(text, "Required tests")
        failing_bullets = [item for item in required_tests if "failing" in item.lower()]
        non_validator_failing = [item for item in failing_bullets if "validate_task_system.py" not in item]
        structural_task = "structural validator guardrail" in text or "This is a conventions task." in text
        require(
            bool(non_validator_failing) or structural_task,
            errors,
            f"{file_value} must require task-specific failing evidence or explicitly identify itself as a structural guardrail/conventions task",
        )


def validate_analysis_followup_hardening_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 092's agent-readiness fixes against future drift."""
    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}

    task030 = task_by_id.get("030")
    require(task030 is not None, errors, "task 030 must exist for doctest fixture contract validation")
    task030_path = ROOT / "tasks/030-doctest-conventions.md"
    if task030_path.is_file():
        text = task030_path.read_text(encoding="utf-8")
        required_doctest_phrases = [
            "validator-backed fixture-presence evidence",
            "test/fixtures/doctest",
            "zig test",
            "zig compile_fail",
            "bash cli",
            "text output",
            "json expected",
            "toml config",
            "zig before",
            "zig after",
        ]
        for phrase in required_doctest_phrases:
            require(phrase in text, errors, f"tasks/030-doctest-conventions.md must contain doctest fixture contract phrase '{phrase}'")
    else:
        fail(errors, "missing task 030 doctest conventions file")

    if isinstance(task030, dict) and task030.get("state") in {"active", "complete"}:
        fixture_dir = ROOT / "test" / "fixtures" / "doctest"
        fixture_files = sorted(fixture_dir.rglob("*.md")) if fixture_dir.is_dir() else []
        require(bool(fixture_files), errors, "task 030 requires doctest markdown fixtures under test/fixtures/doctest")
        fixture_text = "\n".join(path.read_text(encoding="utf-8") for path in fixture_files)
        for marker in ("zig test", "zig compile_fail", "bash cli", "text output", "json expected", "toml config", "zig before", "zig after"):
            require(marker in fixture_text, errors, f"task 030 doctest fixtures must include marker '{marker}'")

    handoff_files = {
        "docs/HANDOFF_CONTRACTS.md": [
            "tests_added is cumulative task-level evidence",
            "role-local test changes",
            "00-orchestrator.json",
            "01-phase-planner.json",
            "02-task-queue-manager-start.json",
            "03-planner.json",
            "04-contract-editor.json",
            "05-test-author.json",
            "06-test-reviewer.json",
            "07-implementer.json",
            "08-implementation-reviewer.json",
            "09-mutation-agent.json",
            "10-mutation-triage-agent.json",
            "11-property-test-agent.json",
            "12-doctest-agent.json",
            "13-architecture-reviewer.json",
            "14-verifier.json",
            "15-task-queue-manager-complete.json",
        ],
        "docs/PIPELINE_ARTIFACTS.md": [
            "00-orchestrator.json",
            "01-phase-planner.json",
            "02-task-queue-manager-start.json",
            "03-planner.json",
            "04-contract-editor.json",
            "05-test-author.json",
            "06-test-reviewer.json",
            "07-implementer.json",
            "08-implementation-reviewer.json",
            "09-mutation-agent.json",
            "10-mutation-triage-agent.json",
            "11-property-test-agent.json",
            "12-doctest-agent.json",
            "13-architecture-reviewer.json",
            "14-verifier.json",
            "15-task-queue-manager-complete.json",
        ],
        "tasks/041-handoff-artifacts.md": [
            "deterministic handoff names for every emitting role",
            "tests_added is cumulative task-level evidence",
        ],
        ".agents/README.md": [
            "Implementation Reviewer",
            "Task Queue Manager Start",
            "Task Queue Manager Complete",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Implementation Reviewer",
        ],
    }
    for rel, phrases in handoff_files.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing handoff hardening contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain handoff hardening phrase '{phrase}'")

    for rel in ("docs/AUTONOMOUS_AGENT_PROTOCOL.md", ".agents/README.md", "docs/HANDOFF_CONTRACTS.md"):
        path = ROOT / rel
        if path.is_file():
            require("Code Reviewer" not in path.read_text(encoding="utf-8"), errors, f"{rel} must use canonical Implementation Reviewer terminology")

    backend_required_phrases = {
        "docs/AST_BACKEND.md": [
            "pinned Zig `0.16.0`",
        ],
        "docs/ZIR_BACKEND.md": [
            "`backend_stability` is `experimental`",
            "out-of-report backend diagnostics",
            "report v1 does not define backend-specific diagnostic fields",
            "pinned Zig `0.16.0`",
        ],
        "docs/AIR_BACKEND.md": [
            "`backend_stability` is `experimental`",
            "out-of-report AIR diagnostics",
            "report v1 does not define backend-specific diagnostic fields",
            "pinned Zig `0.16.0`",
        ],
        "docs/REPORT_FORMAT.md": [
            "report v1 has no backend-specific diagnostics namespace",
            "`backend_stability`",
        ],
        "tasks/056-zir-backend-experiment.md": [
            "`backend_stability`",
            "out-of-report diagnostics",
        ],
        "tasks/057-air-backend-experiment.md": [
            "`backend_stability`",
            "out-of-report diagnostics",
        ],
    }
    for rel, phrases in backend_required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing backend hardening contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain backend hardening phrase '{phrase}'")

    backend_forbidden_phrases = {
        "docs/AST_BACKEND.md": ["Latest-stable", "latest-stable"],
        "docs/ZIR_BACKEND.md": ["Latest-stable", "latest-stable", "\"stability\":", "\"source_mapping\":"],
        "docs/AIR_BACKEND.md": ["Latest-stable", "latest-stable"],
    }
    for rel, phrases in backend_forbidden_phrases.items():
        path = ROOT / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase not in text, errors, f"{rel} contains stale backend phrase '{phrase}'")


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
                if isinstance(tests, list):
                    for test_path in tests:
                        if isinstance(test_path, str):
                            require((ROOT / test_path).exists(), errors, f"tests/coverage-gaps/{filename} {value!r} covered row test path is missing: {test_path}")
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


def validate_gap_registry_deferred_task_closure(tasks: list[dict[str, object]], errors: list[str]) -> None:
    task_by_file = {task.get("file"): task for task in tasks if isinstance(task.get("file"), str)}
    for path in sorted(GAP_REGISTRY_DIR.glob("*.v1.json")):
        data = load_json(path, errors)
        if not isinstance(data, dict):
            continue
        entries = data.get("entries")
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict) or entry.get("covered") is True:
                continue
            deferred_to = entry.get("deferred_to")
            if not isinstance(deferred_to, str):
                continue
            task = task_by_file.get(deferred_to)
            if not isinstance(task, dict) or task.get("state") != "complete":
                continue
            notes = entry.get("notes")
            superseded = entry.get("superseded_by")
            require(
                (isinstance(notes, str) and "superseded" in notes.lower()) or isinstance(superseded, str),
                errors,
                f"{path.relative_to(ROOT)} entry {index} is uncovered but deferred_to complete task {deferred_to}",
            )


def validate_agent_readiness_validator_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard the final pre-bootstrap autonomous-agent readiness fixes from task 094."""
    required_phrases = {
        "docs/TASK_LIFECYCLE.md": [
            "`implemented` and `verified` are pipeline artifact stages, not task-control states",
            "Task-control state transitions are `queued -> active -> complete`",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "`implemented` and `verified` are reserved for pipeline artifact stages",
            "completed prerequisites cannot leave the blocked task in `blocked`",
        ],
        "docs/AGENT_GUIDE.md": [
            "Run final active-scope validation while the task is active, then complete in one task-control transition",
        ],
        "docs/ORCHESTRATION_SPEC.md": [
            "Low-risk tasks may omit Test Reviewer and Implementation Reviewer only when `docs/PIPELINE_ESCALATION_POLICY.md` allows it",
            "Architecture tasks that edit contracts route through Planner or Phase Planner for planning, Contract Editor for the edit step, and Architecture Reviewer for review",
        ],
        "docs/PIPELINE_ESCALATION_POLICY.md": [
            "Architecture contract edits still need an explicit editing role before Architecture Reviewer",
        ],
        "docs/GAP_REGISTRIES.md": [
            "`completion_evidence.gap_registry_rows_changed` must list each changed registry path and row id",
        ],
        "docs/CONFIG_SPEC.md": [
            "`phase2` expands only to stable Phase 2 operators",
            "`impact_graph` is rejected until task `051` completes",
        ],
        "docs/MUTATOR_SPEC.md": [
            "`phase2` means stable Phase 2 operators only",
        ],
        "docs/TEST_SELECTION.md": [
            "Before task `051`, `impact_graph` is not available and must be rejected by config validation",
        ],
        "docs/REPORT_FORMAT.md": [
            "`failure_kind` distinguishes `compile_error` from test assertion failure",
            "`backend_version` is intentionally omitted from report v1 public mutant entries",
            "mode-matrix reporting is owned by task `058`",
        ],
        "docs/SANDBOX_SECURITY.md": [
            "The default minimal environment allowlist is exactly",
            "Command output excerpts are bounded to 4096 bytes per stream",
        ],
        "docs/AI_PROMPT_CONTRACTS.md": [
            "Doctest stub provider mappings",
            "review_snapshot -> zentinel.ai.doctest.snapshot_review.response.v1",
        ],
        "docs/DOCTEST_BLOCK_FORMATS.md": [
            "Plain `zig` compile-pass blocks must not consume `text output`",
        ],
        "docs/DOCTEST_ARCHITECTURE.md": [
            "`zig` followed by `text output` is invalid",
        ],
        "docs/AI_CONTEXT_SCHEMA.md": [
            "`backend_version` is intentionally omitted from AI context v1",
        ],
        "docs/INTERNAL_API_CONTRACTS.md": [
            "`backend_version` remains internal and is not emitted in report v1 or AI context v1",
        ],
        "tasks/015-mutant-runner.md": [
            "Add a failing test for `failure_kind = \"compile_error\"` versus `failure_kind = \"test_failure\"`",
        ],
        "tasks/020-test-selection-same-file.md": [
            "Reject `impact_graph` before task `051`",
        ],
        "tasks/051-fail-fast-impact-analysis.md": [
            "task `051` is the first task allowed to accept `impact_graph`",
        ],
        "tasks/055-ai-doctest-assistance.md": [
            "Add failing stub-provider snapshots for every task-owned doctest AI flow",
        ],
        "tasks/058-safety-mode-matrix.md": [
            "schemas/report.v1.schema.json",
            "docs/REPORT_FORMAT.md",
        ],
        "tasks/067-ai-doctest-survivor-assistance.md": [
            "Add a failing stub-provider output snapshot for the survivor flow",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 094 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 094 contract phrase {phrase!r}")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task058 = task_by_id.get("058")
    if isinstance(task058, dict):
        allowed = task058.get("allowed_files")
        require(isinstance(allowed, list) and "schemas/report.v1.schema.json" in allowed, errors, "task 058 must allow schemas/report.v1.schema.json")
        require(isinstance(allowed, list) and "docs/REPORT_FORMAT.md" in allowed, errors, "task 058 must allow docs/REPORT_FORMAT.md")


def validate_autonomous_agent_contract_repair_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 095's autonomous-agent contract repairs against future drift."""

    required_phrases = {
        ".agents/ORCHESTRATOR.md": [
            "Task-control states are `queued`, `active`, `blocked`, `complete`, and `superseded`.",
            "Only one task may be `active` pending completion at a time.",
            "Before task `041`, context packets and handoffs are recorded in task status or completion summaries.",
        ],
        ".agents/README.md": [
            "Before task `041`, context packets and handoffs are recorded in task status or completion summaries.",
        ],
        ".agents/roles/task-queue-manager.md": [
            "ensure at most one task is active pending completion",
            "may create or rename task markdown files under `tasks/`",
        ],
        ".agents/workflows/sync.md": [
            "first dependency-ready queued task by execution order",
            "current active task",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Normal task-control transitions are `queued`, `active`, and `complete`",
            "Only one task may be `active` pending completion at a time.",
        ],
        "docs/TASK_LIFECYCLE.md": [
            "Task-control state transitions are `queued -> active -> complete`",
            "Agents must not write those names to `tasks/queue.json`, `tasks/status.json`, `tasks/QUEUE.md`, or `tasks/STATUS.md`.",
        ],
        "docs/AGENT_GUIDE.md": [
            "After completion, the validator checks the actual dirty file set against the latest completion evidence.",
        ],
        "docs/ORCHESTRATION_SPEC.md": [
            "Before task `041`, context packets and handoffs are recorded in task status or completion summaries.",
            "After task `041`, they are persisted under `artifacts/pipeline/<task-id>/**`.",
        ],
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "Before task `041`, context packets and handoffs are recorded in task status or completion summaries.",
            "Only the Verifier can approve completion evidence; artifact stages do not change task-control state.",
        ],
        "docs/AGENT_ROLE_SPEC.md": [
            "ensure at most one task is active pending completion",
        ],
        "docs/GAP_REGISTRIES.md": [
            "The validator compares actual changed row ids against `completion_evidence.gap_registry_rows_changed`",
            "Covered row test paths must exist in the repository.",
        ],
        "docs/REPORT_FORMAT.md": [
            "A baseline compiler crash uses `status = \"compiler_crash\"`, `failure_kind = \"compiler_crash\"`, and `run.status = \"baseline_failed\"`.",
        ],
        "docs/AI_CONTEXT_SCHEMA.md": [
            "Each command entry requires `failure_kind`.",
        ],
        "tasks/014-baseline-runner.md": [
            "Add a failing baseline compiler-crash classification test",
        ],
        "tasks/040-agent-pipeline-foundation.md": [
            "Add a failing structural guardrail proving I-019 TDD-first wording is preserved",
        ],
        "tasks/041-handoff-artifacts.md": [
            "If project-owned schema validation tooling does not exist yet, use a deterministic external schema or fixture validation command",
        ],
        "tasks/046-verification-pipeline.md": [
            "artifact stages do not change task-control state",
        ],
    }
    stale_phrases = {
        ".agents/ORCHESTRATOR.md": [
            "queued -> active -> implemented -> verified -> complete",
            "More than one task is active, implemented, or verified pending completion.",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Only one task may be `active`, `implemented`, or `verified` pending completion at a time.",
        ],
        "docs/INVARIANTS.md": [
            "At most one task is active, implemented, or verified pending completion at any time.",
        ],
        "docs/AGENT_ROLE_SPEC.md": [
            "active, implemented, or verified pending completion",
        ],
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "move a task to verified or complete",
        ],
        "tasks/046-verification-pipeline.md": [
            "move from implemented to verified and complete",
            "transitions for implemented, verified, complete, and blocked states",
        ],
    }

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 095 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 095 contract phrase {phrase!r}")

    for rel, phrases in stale_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 095 stale-scan file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase not in text, errors, f"{rel} contains stale task 095 phrase {phrase!r}")

    queue_schema = load_json(QUEUE_SCHEMA_JSON, errors)
    if isinstance(queue_schema, dict):
        task_schema = queue_schema.get("properties", {}).get("tasks", {}).get("items", {}) if isinstance(queue_schema.get("properties"), dict) else {}
        state_schema = task_schema.get("properties", {}).get("state", {}) if isinstance(task_schema, dict) and isinstance(task_schema.get("properties"), dict) else {}
        state_enum = state_schema.get("enum") if isinstance(state_schema, dict) else None
        require(isinstance(state_enum, list) and "implemented" not in state_enum and "verified" not in state_enum, errors, "queue schema must not permit implemented or verified task-control states")

    ai_schema = load_json(ROOT / "schemas" / "ai.context.v1.schema.json", errors)
    if isinstance(ai_schema, dict):
        defs = ai_schema.get("$defs")
        command_schema = defs.get("mutant_command_result") if isinstance(defs, dict) else None
        required = command_schema.get("required") if isinstance(command_schema, dict) else None
        properties = command_schema.get("properties") if isinstance(command_schema, dict) else None
        require(isinstance(required, list) and "failure_kind" in required, errors, "AI context mutant_command_result must require failure_kind")
        require(isinstance(properties, dict) and "failure_kind" in properties, errors, "AI context mutant_command_result must define failure_kind")

    report_schema = load_json(ROOT / "schemas" / "report.v1.schema.json", errors)
    if isinstance(report_schema, dict):
        defs = report_schema.get("$defs")
        baseline = defs.get("baseline_command_result") if isinstance(defs, dict) else None
        properties = baseline.get("properties") if isinstance(baseline, dict) else None
        status_enum = properties.get("status", {}).get("enum") if isinstance(properties, dict) and isinstance(properties.get("status"), dict) else None
        failure_enum = properties.get("failure_kind", {}).get("enum") if isinstance(properties, dict) and isinstance(properties.get("failure_kind"), dict) else None
        require(isinstance(status_enum, list) and "compiler_crash" in status_enum, errors, "report baseline_command_result status must include compiler_crash")
        require(isinstance(failure_enum, list) and "compiler_crash" in failure_enum, errors, "report baseline_command_result failure_kind must include compiler_crash")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    for task_id in ("020", "051"):
        task = task_by_id.get(task_id)
        if isinstance(task, dict):
            allowed = task.get("allowed_files")
            require(isinstance(allowed, list) and "src/config.zig" in allowed, errors, f"task {task_id} must allow src/config.zig for impact_graph config validation")
            require(isinstance(allowed, list) and "test/config_test.zig" in allowed, errors, f"task {task_id} must allow test/config_test.zig for impact_graph config validation")
    task040 = task_by_id.get("040")
    if isinstance(task040, dict):
        allowed = task040.get("allowed_files")
        require(isinstance(allowed, list) and "scripts/validate_task_system.py" in allowed, errors, "task 040 must allow validator guardrails for I-019")
        require(isinstance(allowed, list) and "tests/coverage-gaps/invariants.v1.json" in allowed, errors, "task 040 must allow invariant gap row updates for I-019")


def validate_audit_finding_contract_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 096's audit-finding contract closures against future drift."""

    required_phrases = {
        "docs/TEST_SELECTION.md": [
            "Generated same-file selected commands are authorized generated selected test commands",
            "A generated selected command must pass an unmutated preflight before it can classify a mutant",
        ],
        "docs/SANDBOX_SECURITY.md": [
            "configured commands or authorized generated selected test commands",
            "unmutated preflight",
        ],
        "docs/ARCHITECTURE.md": [
            "Run unmutated preflight for selected commands that were generated after baseline discovery",
        ],
        "docs/AGENT_ROLE_SPEC.md": [
            "## Planner",
            "Planner confirms task scope",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Add or update follow-up tasks when needed while the task remains current.",
            "`queued` means a task is not active, blocked, complete, or superseded",
            "dependency-ready queued",
        ],
        "docs/TASK_LIFECYCLE.md": [
            "`queued` means a task is not active, blocked, complete, or superseded",
            "dependency-ready queued",
        ],
        "docs/PIPELINE_ESCALATION_POLICY.md": [
            "Property Test Agent or Mutation Agent as applicable",
            "Use both specialized roles only when both triggers apply",
        ],
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "Property Test Agent or Mutation Agent as applicable",
            "Use both specialized roles only when both triggers apply",
        ],
        "docs/AI_PROMPT_CONTRACTS.md": [
            '"failure_kind": "none"',
        ],
        "docs/AI_CONTEXT_SCHEMA.md": [
            "`stdout_excerpt` and `stderr_excerpt` are capped at 4096 UTF-8 bytes",
        ],
        "docs/REPORT_FORMAT.md": [
            'semantic validator must reject `baseline.status = "not_run"` with non-empty `mutants`',
            "mode-matrix reporting remains an additive `zentinel.report.v1` extension",
        ],
        "docs/CLI_SPEC.md": [
            "Explicit `--output <path>` inherits the same project-root restriction as `report.output_dir`",
        ],
        "docs/CONFIG_SPEC.md": [
            "The CLI `--output <path>` override inherits this same project-root restriction",
        ],
        "tasks/006-report-schema.md": [
            'Reject `baseline.status = "not_run"` with non-empty `mutants`',
        ],
        "tasks/016-minimal-run-command.md": [
            "Explicit `--output <path>` inherits the same project-root restriction as `report.output_dir`",
        ],
        "tasks/020-test-selection-same-file.md": [
            "generated selected command must pass an unmutated preflight",
        ],
        "tasks/049-pipeline-escalation.md": [
            "Use both specialized roles only when both triggers apply",
        ],
        "tasks/053-ai-provider-and-context.md": [
            "stdout_excerpt and stderr_excerpt are capped at 4096 UTF-8 bytes",
        ],
        "tasks/054-ai-advisory-commands.md": [
            "prompt examples include command `failure_kind`",
        ],
        "tasks/058-safety-mode-matrix.md": [
            "optional `result.mode_matrix`",
            "preserve `result.mode` semantics",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 096 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 096 contract phrase {phrase!r}")

    forbidden_phrases = {
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "Property Test Agent and Mutation Agent",
        ],
    }
    for rel, phrases in forbidden_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 096 stale-scan file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase not in text, errors, f"{rel} contains stale task 096 phrase {phrase!r}")

    source_text = (ROOT / "scripts" / "validate_task_system.py").read_text(encoding="utf-8")
    require("all_tasks = list(task_by_id.values())" in source_text, errors, "completion scope validation must build a full task list for global exceptions")
    require(
        "is_global_scope_exception(path, task_id, all_tasks)" in source_text,
        errors,
        "completion scope validation must check pipeline artifact exceptions against the full task list",
    )

    ai_schema = load_json(ROOT / "schemas" / "ai.context.v1.schema.json", errors)
    if isinstance(ai_schema, dict):
        defs = ai_schema.get("$defs")
        evidence_schema = defs.get("evidence") if isinstance(defs, dict) else None
        properties = evidence_schema.get("properties") if isinstance(evidence_schema, dict) else None
        if isinstance(properties, dict):
            for field in ("stdout_excerpt", "stderr_excerpt"):
                field_schema = properties.get(field)
                require(
                    isinstance(field_schema, dict) and field_schema.get("maxLength") == 4096,
                    errors,
                    f"AI context {field} must have maxLength 4096",
                )


def validate_autonomous_agent_contract_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 097's autonomous-agent closure contracts against future drift."""

    required_phrases = {
        "docs/TEST_SELECTION.md": [
            "Report writers must copy generated-command preflight evidence into `test_selection.preflight_commands`",
        ],
        "docs/REPORT_FORMAT.md": [
            "`test_selection.preflight_commands` is the canonical report location for generated selected-command preflight evidence.",
            "`result.skip_reason` is required and non-null when `result.status = \"skipped\"`",
        ],
        "docs/SCHEMA_REGISTRY.md": [
            "Task `tasks/041-handoff-artifacts.md` creates the baseline pipeline handoff, active-lock, context, stale-context, verification, and escalation schema files.",
        ],
        "docs/PIPELINE_ARTIFACTS.md": [
            "The first post-`041` pipeline task may use those baseline schemas immediately",
        ],
        "tasks/063-pipeline-metadata-validator.md": [
            "consume and validate baseline pipeline schema files created by task `041`",
        ],
        "docs/TASK_LIFECYCLE.md": [
            "The inserted prerequisite task must depend on the immediately previous non-superseded execution-order task",
            '"blocked_task_details": [',
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "If a task is already active, resume that active task instead of selecting another task.",
            "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active.",
            "The inserted prerequisite task must depend on the immediately previous non-superseded execution-order task",
            '"blocked_task_details": [',
        ],
        "docs/TDD_POLICY.md": [
            "Current mechanical checks verify recorded evidence fields and role handoffs; they do not independently prove chronological order until pipeline artifact validation covers role timestamps.",
        ],
        "docs/INVARIANTS.md": [
            "Current machine checks verify required evidence fields and role handoffs, but do not independently prove chronology until pipeline artifact validation covers role timestamps.",
        ],
        "tasks/STATUS.md": [
            "| TDD-first policy | required; mechanical chronology proof limited until pipeline artifact validation |",
        ],
        "docs/AGENT_ROLE_SPEC.md": [
            "## Contract Editor",
            "Contract Editor owns public contract edits",
        ],
        ".agents/README.md": [
            "| Contract Editor | public contracts, schemas, ADRs, or architecture docs change |",
        ],
        ".agents/ORCHESTRATOR.md": [
            "Contract Editor",
            "Public contract changes route through Contract Editor",
        ],
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "Contract Editor",
            "Public contract changes route through Contract Editor",
        ],
        "docs/ORCHESTRATION_SPEC.md": [
            "Contract Editor",
            "Public contract changes route through Contract Editor",
        ],
        "docs/PIPELINE_ESCALATION_POLICY.md": [
            "Contract Editor",
            "Public contract changes route through Contract Editor",
        ],
        "docs/CLI_SPEC.md": [
            "`list-mutants --backend zir` is owned by task `056`; `list-mutants --backend air` is owned by task `057`.",
        ],
        "docs/CONFIG_SPEC.md": [
            "The experimental CLI backend flag is `list-mutants --backend <zir|air>` and is owned by tasks `056` and `057`.",
        ],
        "tasks/056-zir-backend-experiment.md": [
            "`list-mutants --backend zir`",
        ],
        "tasks/057-air-backend-experiment.md": [
            "`list-mutants --backend air`",
        ],
        "docs/DOCTEST_SPEC.md": [
            "`run.error` is required and null for `completed` or `failed`; for `internal_error` it is a closed object",
        ],
        "tasks/035-cli-doctests.md": [
            "closed `run.error` object for `internal_error` doctest reports",
        ],
        ".agents/workflows/task-plan.md": [
            "If a task is already active, resume it instead of selecting a new task.",
            "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active.",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 097 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 097 contract phrase {phrase!r}")

    contract_editor = ROOT / ".agents" / "roles" / "contract-editor.md"
    require(contract_editor.is_file(), errors, "missing Contract Editor role profile .agents/roles/contract-editor.md")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task041 = task_by_id.get("041")
    if isinstance(task041, dict):
        allowed = task041.get("allowed_files")
        for rel in [
            "schemas/pipeline.handoff.v1.schema.json",
            "schemas/pipeline.active_lock.v1.schema.json",
            "schemas/pipeline.context.v1.schema.json",
            "schemas/pipeline.stale_context.v1.schema.json",
            "schemas/pipeline.verification.v1.schema.json",
            "schemas/pipeline.escalation.v1.schema.json",
        ]:
            require(isinstance(allowed, list) and rel in allowed, errors, f"task 041 must own baseline pipeline schema file {rel}")
    task063 = task_by_id.get("063")
    if isinstance(task063, dict):
        task063_text = (ROOT / "tasks" / "063-pipeline-metadata-validator.md").read_text(encoding="utf-8")
        require(
            "not create them" in task063_text,
            errors,
            "task 063 must keep baseline pipeline schema creation owned by task 041",
        )
    for task_id, cli_file, test_file in [
        ("056", "src/cli.zig", "test/cli_backend_experiment_test.zig"),
        ("057", "src/cli.zig", "test/cli_backend_experiment_test.zig"),
    ]:
        task = task_by_id.get(task_id)
        if isinstance(task, dict):
            allowed = task.get("allowed_files")
            require(isinstance(allowed, list) and cli_file in allowed, errors, f"task {task_id} must allow {cli_file} for experimental backend CLI opt-in")
            require(isinstance(allowed, list) and test_file in allowed, errors, f"task {task_id} must allow {test_file} for experimental backend CLI opt-in tests")

    source_text = (ROOT / "scripts" / "validate_task_system.py").read_text(encoding="utf-8")
    require("actual_files == expected_files" in source_text, errors, "validator must compare tasks/QUEUE.md row order to queue.json order")

    report_schema = load_json(ROOT / "schemas" / "report.v1.schema.json", errors)
    if isinstance(report_schema, dict):
        defs = report_schema.get("$defs")
        result = defs.get("result") if isinstance(defs, dict) else None
        result_required = result.get("required") if isinstance(result, dict) else None
        result_properties = result.get("properties") if isinstance(result, dict) else None
        require(isinstance(result_required, list) and "skip_reason" in result_required, errors, "report result must require skip_reason")
        require(isinstance(result_properties, dict) and "skip_reason" in result_properties, errors, "report result must define skip_reason")
        mutant = defs.get("mutant") if isinstance(defs, dict) else None
        mutant_properties = mutant.get("properties") if isinstance(mutant, dict) else None
        test_selection = mutant_properties.get("test_selection") if isinstance(mutant_properties, dict) else None
        selection_required = test_selection.get("required") if isinstance(test_selection, dict) else None
        selection_properties = test_selection.get("properties") if isinstance(test_selection, dict) else None
        require(isinstance(selection_required, list) and "preflight_commands" in selection_required, errors, "report test_selection must require preflight_commands")
        require(isinstance(selection_properties, dict) and "preflight_commands" in selection_properties, errors, "report test_selection must define preflight_commands")
        require(isinstance(defs, dict) and "selection_preflight_command_result" in defs, errors, "report schema must define selection_preflight_command_result")


def validate_agent_implementation_blocker_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 098's final implementation-blocker closures against drift."""

    required_phrases = {
        "docs/AGENT_GUIDE.md": [
            "clean handoff boundary",
            "Before activating a different task, the Task Queue Manager must either commit the completed task changes or record a validator-readable clean baseline",
            "Pre-`041` handoffs are recorded in the active task's `tasks/STATUS.md` completion log entry and the matching `tasks/status.json` `completion_evidence` entry.",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "clean handoff boundary",
            "Before activating a different task, the Task Queue Manager must either commit the completed task changes or record a validator-readable clean baseline",
        ],
        "docs/SEQUENTIAL_EXECUTION_POLICY.md": [
            "A different task must not be activated across uncommitted prior-task changes unless a validator-readable clean handoff baseline is recorded.",
        ],
        ".agents/workflows/task-done.md": [
            "clean handoff boundary",
            "If completed-task changes remain uncommitted, record `clean_handoff_baseline`",
        ],
        ".agents/workflows/task-plan.md": [
            "After task `041`, create `artifacts/pipeline/<task-id>/locks/active-task-lock.json` and the first context packet, then run `python3 scripts/validate_task_system.py`.",
        ],
        "docs/TDD_POLICY.md": [
            "Mechanical chronology proof for I-019 starts at task `063` when pipeline artifact validation can check role timestamps.",
        ],
        "docs/INVARIANTS.md": [
            "Mechanical chronology proof starts at task `063` when pipeline artifact validation can check role timestamps.",
        ],
        "docs/GAP_REGISTRIES.md": [
            "I-019 chronology coverage must defer to the pipeline metadata validator rather than a wording-preservation task.",
        ],
        "tasks/040-agent-pipeline-foundation.md": [
            "Preserve I-019 wording but do not mark I-019 covered",
        ],
        "tasks/041-handoff-artifacts.md": [
            "test/fixtures/pipeline/active_lock/**",
            "test/fixtures/pipeline/context/**",
            "test/fixtures/pipeline/stale_context/**",
            "test/fixtures/pipeline/verification/**",
            "test/fixtures/pipeline/escalation/**",
        ],
        "tasks/063-pipeline-metadata-validator.md": [
            "validate I-019 chronology by checking pipeline artifact role timestamps",
            "may tighten schema validation or fixtures across all baseline pipeline schemas but must not create them",
        ],
        "docs/PIPELINE_ARTIFACTS.md": [
            "After task `041`, mark the task active, create the active-lock artifact, create the first context packet, then run `python3 scripts/validate_task_system.py` before role work starts.",
            "artifacts/pipeline/<task-id>/dogfood/",
        ],
        "docs/AGENT_CONTEXT_PACKETS.md": [
            "After task `041`, the first context packet must exist before post-activation validation dispatches role work.",
        ],
        "docs/AI_CONTEXT_SCHEMA.md": [
            "`result.skip_reason` is required and non-null when `result.status = \"skipped\"`; all other result statuses set it to `null`.",
        ],
        "docs/SANDBOX_SECURITY.md": [
            "phase label (`baseline`, `selection_preflight`, or `mutant`)",
        ],
        "docs/HANDOFF_CONTRACTS.md": [
            "Pre-`041` handoffs are recorded in the active task's `tasks/STATUS.md` completion log entry and the matching `tasks/status.json` `completion_evidence` entry.",
        ],
        ".agents/README.md": [
            "Pre-`041` handoffs are recorded in the active task's `tasks/STATUS.md` completion log entry and the matching `tasks/status.json` `completion_evidence` entry.",
        ],
        "docs/ORCHESTRATION_SPEC.md": [
            "Contract Editor runs before Test Author when public contract changes define or change the tests' expected behavior; otherwise Test Author runs before implementation.",
        ],
        "docs/AGENT_PIPELINE_ARCHITECTURE.md": [
            "Contract Editor runs before Test Author when public contract changes define or change the tests' expected behavior; otherwise Test Author runs before implementation.",
        ],
        ".agents/ORCHESTRATOR.md": [
            "Contract Editor runs before Test Author when public contract changes define or change the tests' expected behavior; otherwise Test Author runs before implementation.",
        ],
        ".agents/roles/contract-editor.md": [
            "When public contract changes define or change expected behavior, Contract Editor runs before Test Author so tests target the approved contract.",
        ],
        "docs/CI_STRATEGY.md": [
            "Final release dogfood archives live under `artifacts/pipeline/<task-id>/dogfood/`; `zig-out` paths are runtime output paths, not canonical archives.",
        ],
        "docs/DOGFOODING.md": [
            "Final dogfood reports are archived under `artifacts/pipeline/<task-id>/dogfood/`; `zig-out` paths are runtime output paths, not canonical archives.",
        ],
        "docs/PROJECT_ACCEPTANCE_CRITERIA.md": [
            "archived under `artifacts/pipeline/<task-id>/dogfood/`",
        ],
        "tasks/085-final-dogfood-release-gate.md": [
            "artifacts/pipeline/085/dogfood/",
            "`zig-out` runtime outputs are not the canonical archive",
        ],
        "tasks/053-ai-provider-and-context.md": [
            "result-level `skip_reason`",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 098 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 098 phrase {phrase!r}")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task041 = task_by_id.get("041")
    if isinstance(task041, dict):
        allowed = task041.get("allowed_files")
        for rel in [
            "test/fixtures/pipeline/handoff/**",
            "test/fixtures/pipeline/active_lock/**",
            "test/fixtures/pipeline/context/**",
            "test/fixtures/pipeline/stale_context/**",
            "test/fixtures/pipeline/verification/**",
            "test/fixtures/pipeline/escalation/**",
        ]:
            require(isinstance(allowed, list) and rel in allowed, errors, f"task 041 must allow baseline pipeline fixture scope {rel}")
    task063 = task_by_id.get("063")
    if isinstance(task063, dict):
        allowed = task063.get("allowed_files")
        for rel in [
            "schemas/pipeline.handoff.v1.schema.json",
            "schemas/pipeline.active_lock.v1.schema.json",
            "schemas/pipeline.context.v1.schema.json",
            "schemas/pipeline.stale_context.v1.schema.json",
            "schemas/pipeline.verification.v1.schema.json",
            "schemas/pipeline.escalation.v1.schema.json",
        ]:
            require(isinstance(allowed, list) and rel in allowed, errors, f"task 063 must allow baseline pipeline schema validation target {rel}")

    invariants_gap = load_json(ROOT / "tests" / "coverage-gaps" / "invariants.v1.json", errors)
    if isinstance(invariants_gap, dict):
        entries = invariants_gap.get("entries")
        if isinstance(entries, list):
            i019 = next((entry for entry in entries if isinstance(entry, dict) and entry.get("number") == "I-019"), None)
            require(isinstance(i019, dict), errors, "invariant gap registry must include I-019")
            if isinstance(i019, dict):
                # Role timestamp validation now exists (task 063), so I-019 is covered.
                require(i019.get("covered") is True, errors, "I-019 gap row is covered now that task 063 role timestamp validation exists")
                notes = i019.get("notes")
                require(isinstance(notes, str) and "role timestamps" in notes, errors, "I-019 gap row notes must mention role timestamp validation")

    ai_schema = load_json(ROOT / "schemas" / "ai.context.v1.schema.json", errors)
    if isinstance(ai_schema, dict):
        defs = ai_schema.get("$defs")
        result = defs.get("result") if isinstance(defs, dict) else None
        required = result.get("required") if isinstance(result, dict) else None
        properties = result.get("properties") if isinstance(result, dict) else None
        require(isinstance(required, list) and "skip_reason" in required, errors, "AI context result must require skip_reason")
        require(isinstance(properties, dict) and "skip_reason" in properties, errors, "AI context result must define skip_reason")


def validate_handoff_baseline_and_contract_drift_closure_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 099's handoff-baseline and downstream drift closures."""

    required_phrases = {
        "docs/AGENT_GUIDE.md": [
            "clean_handoff_baseline",
            "per-file SHA-256",
            "unchanged files explicitly covered by the current clean handoff baseline",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active.",
            "After task `041`, mark the task active, create the active-lock artifact, create the first context packet, then run `python3 scripts/validate_task_system.py` before role work starts.",
        ],
        ".agents/workflows/task-plan.md": [
            "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active.",
            "After task `041`, create `artifacts/pipeline/<task-id>/locks/active-task-lock.json` and the first context packet, then run `python3 scripts/validate_task_system.py`.",
        ],
        ".agents/workflows/task-done.md": [
            "clean_handoff_baseline",
            "per-file SHA-256",
        ],
        "docs/PIPELINE_ARTIFACTS.md": [
            "After task `041`, mark the task active, create the active-lock artifact, create the first context packet, then run `python3 scripts/validate_task_system.py` before role work starts.",
        ],
        "docs/AI_PROMPT_CONTRACTS.md": [
            '"skip_reason": null',
        ],
        "docs/REPORT_FORMAT.md": [
            "For `invalid`, `failure_summary` starts with one of `patch:`, `sandbox:`, or `backend:`.",
        ],
        "docs/CLI_SPEC.md": [
            "Until task `005` is complete, task `001` treats version output as policy-only",
        ],
        "docs/MUTATOR_SPEC.md": [
            "When AST syntax alone cannot prove an optional/null, error-path, errdefer, integer-boundary, or loop-boundary rewrite preserves Zig grammar, the mutator must filter the candidate before execution rather than emitting a `compile_error` result.",
        ],
        "docs/ZIR_BACKEND.md": [
            "artifacts/pipeline/<task-id>/experimental-backend-diagnostics/",
        ],
        "docs/AIR_BACKEND.md": [
            "artifacts/pipeline/<task-id>/experimental-backend-diagnostics/",
        ],
        "docs/DOCTEST_MUTATION_STRATEGY.md": [
            "`failure_kind`",
            "mutation-aware doctest runner evidence",
        ],
        "docs/DOCTEST_AI_INTEGRATION.md": [
            "`failure_kind`",
            "mutation-aware doctest runner evidence",
        ],
        "tasks/041-handoff-artifacts.md": [
            "standard-library-only fixture sanity check",
        ],
        "tasks/001-cli-shell.md": [
            "Until task `005` is complete, task `001` treats version output as policy-only",
        ],
        "tasks/006-report-schema.md": [
            "For `invalid`, `failure_summary` starts with one of `patch:`, `sandbox:`, or `backend:`.",
        ],
        "tasks/039-doctest-mutation-experiments.md": [
            "`failure_kind`",
            "mutation-aware doctest runner evidence",
        ],
        "tasks/056-zir-backend-experiment.md": [
            "artifacts/pipeline/<task-id>/experimental-backend-diagnostics/",
        ],
        "tasks/057-air-backend-experiment.md": [
            "artifacts/pipeline/<task-id>/experimental-backend-diagnostics/",
        ],
        "tasks/061-doctest-mutate-stabilization.md": [
            "`failure_kind`",
            "mutation-aware doctest runner evidence",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 099 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 099 phrase {phrase!r}")

    schema = load_json(ROOT / "tasks" / "schema" / "status.v1.schema.json", errors)
    if isinstance(schema, dict):
        required = schema.get("required")
        properties = schema.get("properties")
        require(isinstance(required, list) and "clean_handoff_baseline" in required, errors, "status schema must require clean_handoff_baseline")
        require(isinstance(properties, dict) and "clean_handoff_baseline" in properties, errors, "status schema must define clean_handoff_baseline")
        baseline = properties.get("clean_handoff_baseline") if isinstance(properties, dict) else None
        baseline_text = json.dumps(baseline, sort_keys=True)
        require("sha256" in baseline_text, errors, "status schema clean_handoff_baseline must record sha256 values")
        require("source_commit" in baseline_text, errors, "status schema clean_handoff_baseline must record source_commit")

    require(isinstance(status, dict) and "clean_handoff_baseline" in status, errors, "status.json must contain clean_handoff_baseline")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task000 = task_by_id.get("000")
    task101 = task_by_id.get("101")
    if isinstance(task101, dict):
        deps = task101.get("dependencies")
        require(isinstance(deps, list) and "100" in deps, errors, "task 101 must depend on task 100")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "101" in deps, errors, "task 000 must depend on task 101")


def validate_clean_handoff_lifecycle_closure_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 100's clean-handoff lifecycle closure."""

    required_phrases = {
        "docs/AGENT_GUIDE.md": [
            "After completed-task changes are committed, `clean_handoff_baseline` must be cleared to `null`",
            "A non-null clean handoff baseline is only valid for uncommitted prior-task files carried forward from the recorded `source_commit`",
        ],
        ".agents/workflows/task-done.md": [
            "After committing completed-task changes, clear `clean_handoff_baseline` to `null`",
            "If completed-task changes remain uncommitted, record `clean_handoff_baseline`",
        ],
        "tasks/STATUS.md": [
            "pre-bootstrap hardening tasks `071` through `105`",
            "Task `100` completed at execution order `000.0.30` before project bootstrap.",
        ],
        "tasks/041-handoff-artifacts.md": [
            "row-scoped gap registry exception",
            "pipeline schema rows",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 100 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 100 phrase {phrase!r}")

    protocol = ROOT / "docs" / "AUTONOMOUS_AGENT_PROTOCOL.md"
    if protocol.is_file():
        text = protocol.read_text(encoding="utf-8")
        phrase = "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active."
        require(text.count(phrase) == 1, errors, "docs/AUTONOMOUS_AGENT_PROTOCOL.md must contain the pre-041 active validator sentence exactly once")

    require(isinstance(status, dict) and status.get("clean_handoff_baseline") is None, errors, "status clean_handoff_baseline must be null after committed task 099 handoff")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task000 = task_by_id.get("000")
    task101 = task_by_id.get("101")
    if isinstance(task101, dict):
        deps = task101.get("dependencies")
        require(isinstance(deps, list) and "100" in deps, errors, "task 101 must depend on task 100 after clean handoff lifecycle closure")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "101" in deps, errors, "task 000 must depend on task 101 after version command and evidence closure")


def validate_version_command_and_evidence_closure_contracts(tasks: list[dict[str, object]], errors: list[str]) -> None:
    """Guard task 101's version-command and pre-pipeline evidence contracts."""

    required_phrases = {
        "docs/CLI_SPEC.md": [
            "Task `001` owns only policy-label `zentinel version` output.",
            "Task `005` adds real Zig discovery to `zentinel version` and `zentinel check`.",
            "When Zig is missing, `zentinel version` exits `0`",
            "When Zig is missing, `zentinel check` exits `2` with `ZNTL_ZIG_NOT_FOUND`",
        ],
        "docs/FAILURE_MODES.md": [
            "Fatal for commands that require Zig.",
            "`zentinel version` records this as non-fatal environment status",
        ],
        "docs/TDD_POLICY.md": [
            "`failing_command`",
            "`failing_output_excerpt`",
            "`implementation_started_after_failure`",
            "`passing_command`",
        ],
        "docs/AGENT_GUIDE.md": [
            "pre-`063` structured chronology evidence",
            "`implementation_started_after_failure`",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "pre-`063` structured chronology evidence",
            "`implementation_started_after_failure`",
        ],
        "tasks/005-version-policy.md": [
            "Add failing CLI tests for `zentinel version` with supported Zig `0.16.0`, missing Zig executable, and unsupported Zig version.",
            "Add failing CLI tests that `zentinel check` treats missing Zig and unsupported Zig as fatal environment errors.",
            "`zentinel version` reports Zig discovery status without making missing or unsupported Zig fatal for that command.",
            "`zentinel check` exits `2` for missing or unsupported Zig",
        ],
        "tasks/000-project-bootstrap.md": [
            "after task `104` is complete",
        ],
        "tasks/STATUS.md": [
            "pre-bootstrap hardening tasks `071` through `105`",
        ],
    }

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 101 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 101 phrase {phrase!r}")

    pipeline_artifacts = ROOT / "docs" / "PIPELINE_ARTIFACTS.md"
    if pipeline_artifacts.is_file():
        text = pipeline_artifacts.read_text(encoding="utf-8")
        activation_phrase = "After task `041`, mark the task active, create the active-lock artifact, create the first context packet, then run `python3 scripts/validate_task_system.py` before role work starts."
        require(text.count(activation_phrase) == 1, errors, "docs/PIPELINE_ARTIFACTS.md must contain one canonical post-041 activation-order sentence")
        require("After task `041`, activation order is:" not in text, errors, "docs/PIPELINE_ARTIFACTS.md must not duplicate post-041 activation order wording")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task101 = task_by_id.get("101")
    if isinstance(task101, dict):
        deps = task101.get("dependencies")
        require(isinstance(deps, list) and "100" in deps, errors, "task 101 must depend on task 100")
    task000 = task_by_id.get("000")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "101" in deps, errors, "task 000 must depend on task 101")


def validate_agent_workflow_cleanup_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 102's agent-workflow cleanup contracts."""

    task_plan = ROOT / ".agents" / "workflows" / "task-plan.md"
    if task_plan.is_file():
        text = task_plan.read_text(encoding="utf-8")
        pre_041_phrase = "Before task `041`, run `python3 scripts/validate_task_system.py` immediately after marking a task active."
        post_041_phrase = "After task `041`, create `artifacts/pipeline/<task-id>/locks/active-task-lock.json` and the first context packet, then run `python3 scripts/validate_task_system.py`."
        require(text.count(pre_041_phrase) == 1, errors, ".agents/workflows/task-plan.md must contain one canonical pre-041 active-validator sentence")
        require("Run `python3 scripts/validate_task_system.py` immediately after activation." not in text, errors, ".agents/workflows/task-plan.md must not contain duplicate generic activation-validator wording")
        require(text.count(post_041_phrase) == 1, errors, ".agents/workflows/task-plan.md must contain one canonical post-041 activation-order sentence")
        require("After task `041`, mark the task active, create the active-lock artifact, create the first context packet" not in text, errors, ".agents/workflows/task-plan.md must not repeat task activation in post-041 branch prose")
        require("After task `041`, activate the task, write `artifacts/pipeline/<task-id>/locks/active-task-lock.json`, write the first context packet" not in text, errors, ".agents/workflows/task-plan.md must not contain duplicate post-041 activation-order wording")
    else:
        fail(errors, "missing task 102 contract file .agents/workflows/task-plan.md")

    required_phrases = {
        "tasks/STATUS.md": [
            "pre-bootstrap hardening tasks `071` through `105`",
            "Task `102`",
        ],
        "tasks/000-project-bootstrap.md": [
            "after task `104` is complete",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 102 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 102 phrase {phrase!r}")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task102 = task_by_id.get("102")
    if isinstance(task102, dict):
        deps = task102.get("dependencies")
        require(isinstance(deps, list) and "101" in deps, errors, "task 102 must depend on task 101")
    task000 = task_by_id.get("000")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "101" in deps and "102" in deps and "103" in deps, errors, "task 000 must depend on task 101, task 102, and task 103")

    if not isinstance(status, dict):
        return
    completion_evidence = status.get("completion_evidence")
    task101_evidence = None
    if isinstance(completion_evidence, list):
        task101_evidence = next(
            (
                entry
                for entry in completion_evidence
                if isinstance(entry, dict) and entry.get("task") == "101"
            ),
            None,
        )
    require(isinstance(task101_evidence, dict), errors, "task 101 completion_evidence must exist for task 102 evidence cleanup")
    if isinstance(task101_evidence, dict):
        validator_result = task101_evidence.get("validator_result")
        notes = validator_result.get("notes") if isinstance(validator_result, dict) else None
        require(isinstance(notes, str) and "active-state validation passed before completion" in notes, errors, "task 101 validator_result.notes must mention active-state validation before completion")
        require(isinstance(notes, str) and "complete-state validation passed after completion" in notes, errors, "task 101 validator_result.notes must mention complete-state validation after completion")


def validate_contract_ambiguity_cleanup_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 103's contract-ambiguity cleanup."""

    required_phrases = {
        "tasks/STATUS.md": [
            "pre-bootstrap hardening tasks `071` through `105`",
            "Task `103`",
        ],
        "tasks/000-project-bootstrap.md": [
            "after task `104` is complete",
        ],
        "tasks/002-config-parser.md": [
            "Task `002` validates that `test.commands` is present, non-empty, and contains non-empty string values only.",
            "It must not implement shell/argv command syntax parsing.",
            "Command syntax validation and `src/command.zig` are owned by task `005`.",
        ],
        "docs/CONFIG_SPEC.md": [
            "Before task `005`, config parsing validates that `test.commands` is a non-empty list of non-empty strings.",
            "Full command grammar validation begins when task `005` introduces `src/command.zig`.",
        ],
        "docs/AI_CONTEXT_SCHEMA.md": [
            "4096 UTF-8 bytes",
            "safe character boundary",
        ],
        "docs/SCHEMA_REGISTRY.md": [
            "JSON Schema `maxLength: 4096` is a secondary structural guard",
            "canonical output excerpt bound is 4096 UTF-8 bytes",
        ],
        ".agents/workflows/task-plan.md": [
            "After task `041`, create `artifacts/pipeline/<task-id>/locks/active-task-lock.json` and the first context packet, then run `python3 scripts/validate_task_system.py`.",
        ],
    }

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 103 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 103 phrase {phrase!r}")

    task_plan = ROOT / ".agents" / "workflows" / "task-plan.md"
    if task_plan.is_file():
        text = task_plan.read_text(encoding="utf-8")
        require("After task `041`, mark the task active, create the active-lock artifact, create the first context packet" not in text, errors, ".agents/workflows/task-plan.md must not repeat task activation in post-041 branch prose")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task103 = task_by_id.get("103")
    if isinstance(task103, dict):
        deps = task103.get("dependencies")
        require(isinstance(deps, list) and "102" in deps, errors, "task 103 must depend on task 102")
    task000 = task_by_id.get("000")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "103" in deps, errors, "task 000 must depend on task 103")

    if isinstance(status, dict) and isinstance(task103, dict) and task103.get("state") == "complete":
        completion_evidence = status.get("completion_evidence")
        task103_evidence = None
        if isinstance(completion_evidence, list):
            task103_evidence = next(
                (
                    entry
                    for entry in completion_evidence
                    if isinstance(entry, dict) and entry.get("task") == "103"
                ),
                None,
            )
        require(isinstance(task103_evidence, dict), errors, "task 103 completion_evidence must exist")


def validate_output_bound_wording_cleanup_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 104's stale output-bound wording cleanup."""

    stale_phrases = [f"4096 {unit}" for unit in ["characters"]]
    stale_phrases.append("4096-" + "character")
    stale_targets = [
        "tasks/096-audit-finding-contract-closure.md",
        "tasks/104-output-bound-wording-cleanup.md",
        "tasks/status.json",
        "tests/coverage-gaps/schemas.v1.json",
    ]
    for rel in stale_targets:
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 104 stale-wording target {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in stale_phrases:
            require(phrase not in text, errors, f"{rel} must not contain stale output-bound phrase {phrase!r}")

    required_phrases = {
        "tests/coverage-gaps/schemas.v1.json": [
            "4096 UTF-8 byte stdout/stderr excerpt bounds",
        ],
        "tasks/096-audit-finding-contract-closure.md": [
            "AI context stdout/stderr excerpts are bounded to 4096 UTF-8 bytes",
        ],
        "tasks/status.json": [
            "capped AI context stdout/stderr excerpts at 4096 UTF-8 bytes",
            "canonicalized output excerpt bounds as 4096 UTF-8 bytes",
        ],
        "tasks/STATUS.md": [
            "pre-bootstrap hardening tasks `071` through `105`",
            "Task `105` closes architecture boundary enforcement before project bootstrap.",
        ],
        "tasks/000-project-bootstrap.md": [
            "after task `104` is complete",
        ],
    }
    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 104 contract file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 104 phrase {phrase!r}")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task104 = task_by_id.get("104")
    require(isinstance(task104, dict), errors, "task 104 must exist for output-bound wording cleanup")
    if isinstance(task104, dict):
        deps = task104.get("dependencies")
        require(isinstance(deps, list) and "103" in deps, errors, "task 104 must depend on task 103")
    task000 = task_by_id.get("000")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "104" in deps, errors, "task 000 must depend on task 104")

    if isinstance(status, dict) and isinstance(task104, dict) and task104.get("state") == "complete":
        completion_evidence = status.get("completion_evidence")
        task104_evidence = None
        if isinstance(completion_evidence, list):
            task104_evidence = next(
                (
                    entry
                    for entry in completion_evidence
                    if isinstance(entry, dict) and entry.get("task") == "104"
                ),
                None,
            )
        require(isinstance(task104_evidence, dict), errors, "task 104 completion_evidence must exist")


def validate_architecture_boundary_enforcement_contracts(
    tasks: list[dict[str, object]],
    status: object,
    errors: list[str],
) -> None:
    """Guard task 105's deterministic architecture boundary contracts."""

    required_phrases = {
        "docs/adr/README.md": [
            "ADR-0008",
            "Deterministic pipeline core with ports at side-effect boundaries",
            "0008-deterministic-pipeline-core.md",
        ],
        "docs/adr/0008-deterministic-pipeline-core.md": [
            "# ADR-0008: Deterministic pipeline core with ports at side-effect boundaries",
            "Status: Accepted",
            "zentinel's primary architecture is a deterministic pipeline with a functional core",
            "Ports and adapters are allowed only at side-effect and advisory boundaries",
        ],
        "docs/ARCHITECTURE.md": [
            "The primary architecture is a deterministic pipeline with a functional core.",
            "Ports and adapters are boundary tools, not the system architecture.",
            "Architecture Boundary Contract",
            "Deterministic core modules must not import adapters.",
        ],
        "docs/INTERNAL_API_CONTRACTS.md": [
            "Layer Registry",
            "All future `src/**/*.zig` files must declare `// Layer: <layer>`",
            "deterministic_core",
            "pipeline_orchestration",
            "side_effect_adapter",
            "advisory_adapter",
            "Forbidden Import Edges",
        ],
        "docs/INVARIANTS.md": [
            "**I-022.** Deterministic core modules do not import side-effect or advisory adapters.",
        ],
        "docs/GLOSSARY.md": [
            "**Architecture boundary**",
            "**Functional core**",
            "**Port or adapter**",
        ],
        "docs/DISCIPLINE.md": [
            "**D-603.** Deterministic core modules must not import side-effect adapters, advisory AI adapters, CLI command routers, or report renderers.",
        ],
        "docs/AGENT_GUIDE.md": [
            "Architecture Boundary Checklist",
            "Does this change add or modify an import edge?",
        ],
        "docs/AUTONOMOUS_AGENT_PROTOCOL.md": [
            "Architecture Boundary Handling",
            "If a task needs a forbidden dependency edge, insert a prerequisite contract task",
        ],
        ".agents/ORCHESTRATOR.md": [
            "Architecture boundary checks are mandatory",
        ],
        ".agents/roles/architecture-reviewer.md": [
            "verify layer declarations and import direction",
            "reject deterministic core imports of side-effect or advisory adapters",
        ],
        ".agents/roles/implementation-reviewer.md": [
            "review added or changed import edges against `docs/INTERNAL_API_CONTRACTS.md`",
        ],
        ".agents/roles/verifier.md": [
            "run architecture boundary validator checks",
        ],
        "tests/coverage-gaps/invariants.v1.json": [
            '"number": "I-022"',
            '"tests": [',
            '"scripts/validate_task_system.py"',
        ],
        "tasks/000-project-bootstrap.md": [
            "after task `105` is complete",
        ],
    }

    for rel, phrases in required_phrases.items():
        path = ROOT / rel
        require(path.is_file(), errors, f"missing task 105 architecture-boundary file {rel}")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for phrase in phrases:
            require(phrase in text, errors, f"{rel} must contain task 105 architecture-boundary phrase {phrase!r}")

    task_by_id = {task.get("id"): task for task in tasks if isinstance(task.get("id"), str)}
    task105 = task_by_id.get("105")
    require(isinstance(task105, dict), errors, "task 105 must exist for architecture boundary enforcement")
    if isinstance(task105, dict):
        deps = task105.get("dependencies")
        require(isinstance(deps, list) and "104" in deps, errors, "task 105 must depend on task 104")
    task000 = task_by_id.get("000")
    if isinstance(task000, dict):
        deps = task000.get("dependencies")
        require(isinstance(deps, list) and "105" in deps, errors, "task 000 must depend on task 105")

    validate_zig_architecture_layers(errors)

    if isinstance(status, dict) and isinstance(task105, dict) and task105.get("state") == "complete":
        completion_evidence = status.get("completion_evidence")
        task105_evidence = None
        if isinstance(completion_evidence, list):
            task105_evidence = next(
                (
                    entry
                    for entry in completion_evidence
                    if isinstance(entry, dict) and entry.get("task") == "105"
                ),
                None,
            )
        require(isinstance(task105_evidence, dict), errors, "task 105 completion_evidence must exist")


def validate_zig_architecture_layers(errors: list[str]) -> None:
    src_dir = ROOT / "src"
    if not src_dir.is_dir():
        return

    layers_by_path: dict[Path, str] = {}
    for path in sorted(src_dir.rglob("*.zig")):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT).as_posix()
        match = ZIG_LAYER_RE.search(text)
        require(match is not None, errors, f"{rel} must declare an architecture layer with // Layer: <layer>")
        if match is None:
            continue
        layer = match.group(1)
        require(layer in ARCHITECTURE_LAYERS, errors, f"{rel} declares unknown architecture layer {layer!r}")
        layers_by_path[path.resolve()] = layer

    for path, layer in sorted(layers_by_path.items(), key=lambda item: item[0].as_posix()):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT).as_posix()
        forbidden_targets = FORBIDDEN_LAYER_IMPORTS.get(layer, set())
        if not forbidden_targets:
            continue
        for imported in ZIG_IMPORT_RE.findall(text):
            target = resolve_zig_import(path, imported)
            if target is None:
                continue
            target_layer = layers_by_path.get(target)
            if target_layer is None:
                continue
            require(
                target_layer not in forbidden_targets,
                errors,
                f"{rel} layer {layer} must not import {target.relative_to(ROOT).as_posix()} layer {target_layer}",
            )


def resolve_zig_import(importer: Path, imported: str) -> Path | None:
    if not imported.endswith(".zig"):
        return None
    if imported.startswith("src/"):
        candidate = ROOT / imported
    else:
        candidate = importer.parent / imported
    try:
        resolved = candidate.resolve()
    except OSError:
        return None
    if not resolved.is_file():
        return None
    try:
        resolved.relative_to(ROOT / "src")
    except ValueError:
        return None
    return resolved


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
    validate_active_task_changed_file_scope(status, tasks, errors)
    validate_inactive_changed_file_scope(status, tasks, errors)
    validate_inactive_gap_registry_row_scope(status, errors)
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
    validate_dogfood_release_gate_sequence_contracts(tasks, errors)
    validate_markdown_table_shapes(errors)
    validate_analysis_findings_closure_contracts(tasks, errors)
    validate_agent_tooling_contract_hardening_contracts(errors)
    validate_contract_traceability_and_scope_hardening_contracts(tasks, errors)
    validate_analysis_followup_hardening_contracts(tasks, errors)
    validate_agent_readiness_validator_closure_contracts(tasks, errors)
    validate_autonomous_agent_contract_repair_contracts(tasks, errors)
    validate_audit_finding_contract_closure_contracts(tasks, errors)
    validate_autonomous_agent_contract_closure_contracts(tasks, errors)
    validate_agent_implementation_blocker_closure_contracts(tasks, errors)
    validate_handoff_baseline_and_contract_drift_closure_contracts(tasks, status, errors)
    validate_clean_handoff_lifecycle_closure_contracts(tasks, status, errors)
    validate_version_command_and_evidence_closure_contracts(tasks, errors)
    validate_agent_workflow_cleanup_contracts(tasks, status, errors)
    validate_contract_ambiguity_cleanup_contracts(tasks, status, errors)
    validate_output_bound_wording_cleanup_contracts(tasks, status, errors)
    validate_architecture_boundary_enforcement_contracts(tasks, status, errors)
    validate_adr_system(errors)
    validate_gap_registries(errors)
    validate_schema_gap_ownership(tasks, errors)
    validate_gap_registry_deferred_task_closure(tasks, errors)
    validate_pipeline_metadata(errors)
    validate_failure_recovery(errors)

    if errors:
        print("task system validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"task system validation passed: {len(tasks)} tasks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
