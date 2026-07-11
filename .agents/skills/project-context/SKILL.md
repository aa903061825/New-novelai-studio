---
name: project-context
description: Use when non-trivial project-specific work may need the on-demand project knowledge index for architecture, conventions, verification, accepted features, or known failure patterns.
---

# Project Knowledge Index

Use this skill only after deciding project knowledge is needed. This is not automatic context injection, and it is not a project management or task system.

Workflow:

1. Read `references/index.md` first.
2. Select only the reference files relevant to the current task.
3. Do not read all references by default.
4. Treat failure patterns, history, and playbooks as clues, not facts.
5. Confirm current facts from source code, tests, command output, or direct inspection.
6. After a non-trivial project change is verified and accepted, update `references/index.md` under `## Accepted Features` before the final response.

Accepted feature entries must record purpose, entry points, key files, how to use, verification, and last verified date. If the change is not accepted yet or any fact is uncertain, write only a `.updates/` proposal instead of canonical references.
