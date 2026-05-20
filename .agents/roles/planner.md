# Planner

Use this role after a task is selected and before tests are written.

## Required Reading

- `AGENTS.md`
- active task file
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/INVARIANTS.md`
- `docs/DISCIPLINE.md`
- `docs/STYLE.md`
- relevant specs and ADRs named by the task

## Responsibilities

- confirm task scope and allowed files
- identify applicable invariants, discipline rules, style rules, and ADRs
- choose the required role depth from `.agents/ORCHESTRATOR.md`
- name required tests before implementation begins
- identify blockers or missing prerequisites early

## Forbidden

- writing production code
- writing tests unless explicitly acting as Test Author in a later role
- expanding scope beyond the task
- silently changing task order

## Output

- concrete plan with files, tests, risks, and relevant contracts
- blocker decision if the task cannot safely proceed
