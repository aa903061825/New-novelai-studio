---
name: project-context
description: Use when non-trivial project-specific work may need the on-demand project knowledge index for architecture, conventions, verification, accepted features, or known failure patterns.
---

# Project Knowledge Index

Use this skill for non-trivial project work when current project knowledge can reduce broad scanning or repeated explanation. This is a narrow, on-demand project stewardship layer for architecture, current knowledge, and explicitly requested closed history, not an active task, backlog, priority, or status workflow.

Workflow:

1. Form an ephemeral goal brief from the intended outcome, constraints, likely project areas, and required verification.
2. Read `references/index.md` first. It routes to current knowledge such as `references/architecture.md`.
3. Load only the current reference files relevant to the goal.
4. Treat generated observations and failure patterns as clues, then verify current claims against source code, tests, manifests, and command output.
5. Complete the work and run the required verification.
6. Never persist the goal brief as a task.
7. Never read `history/index.md` or history records unless the user explicitly asks to consult project history.
8. After the user accepts a verified non-trivial result, first use `scripts/capture-accepted-change.ps1` to update durable current knowledge in Accepted Features, then invoke `scripts/record-history.ps1` once with the closed outcome and verification evidence before the final response.

Accepted feature entries must record purpose, existing project-contained entry points and key files, how to use, nonempty verification evidence, and a nonfuture verification timestamp with an explicit offset. This captures only verified and accepted durable current knowledge. If the result is not accepted yet or any fact is uncertain, write only a `.updates/` proposal instead of canonical references.

History recording is append-only bookkeeping after the outcome closes. Recording a closed outcome never permits reading cold history.

When Doctor reports that the 30-day retention review is due, only report the reminder. Run `scripts/review-history-cleanup.ps1` to create a metadata-only proposal only when the user explicitly asks to review or clean history. Review never applies a proposal, loads history bodies into current context, or reads archives. Applying cleanup requires the separate global command, the exact proposal path, and explicit approval; it is never automatic.

Only after the user explicitly asks to consult project history, read `history/index.md` first, select the smallest relevant record set, and read only those records. Treat historical records as leads, never as current facts; verify current claims against source code, tests, command output, or Git.
