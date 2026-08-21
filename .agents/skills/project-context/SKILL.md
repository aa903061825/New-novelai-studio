---
name: project-context
description: Use when non-trivial project-specific work may need the on-demand project knowledge index for architecture, conventions, verification, accepted features, or known failure patterns.
---

# Project Knowledge Index

Use this skill for non-trivial project work when project knowledge can reduce broad scanning or repeated explanation. This is a narrow, on-demand project stewardship layer for architecture, current knowledge, and relevant closed history, not an active task, backlog, priority, or status workflow.

Workflow:

1. Form an ephemeral goal brief from the intended outcome, constraints, likely project areas, and required verification.
2. Read `references/index.md` first. It routes to current knowledge such as `references/architecture.md`.
3. Load only the current reference files relevant to the goal.
4. For targeted lookup, use `scripts/manage-knowledge.ps1 -Action find -Query "<terms>"` and load only the matching records.
5. Treat generated observations and failure patterns as clues, then verify current claims against source code, tests, manifests, and command output.
6. Complete the work and run the required verification.
7. Never persist the goal brief as a task.
8. Codex decides when project history is relevant. When it is useful, read `history/index.md` first and load the history needed for the task.
9. After the user accepts a verified non-trivial result, use `scripts/capture-accepted-change.ps1` for accepted features or `scripts/manage-knowledge.ps1 -Action add` for architecture, rules, failures, and decisions, then invoke `scripts/record-history.ps1` once with the closed outcome and verification evidence before the final response.

Accepted feature entries must record purpose, existing project-contained entry points and key files, how to use, nonempty verification evidence, and a nonfuture verification timestamp with an explicit offset. This captures only verified and accepted durable current knowledge. If the result is not accepted yet or any fact is uncertain, write only a `.updates/` proposal instead of canonical references.

Structured records under `references/records/` are canonical. The JSONL catalog and Markdown/HTML dashboards under `references/generated/` are replaceable views. Refresh maps changed source paths to pending knowledge reviews. Use `scripts/review-knowledge.ps1`, then resolve one exact record with `scripts/accept-knowledge-review.ps1`; never accept a review without fresh evidence.

History recording is append-only bookkeeping after the outcome closes. Reading recorded history is a separate context decision made according to the task.

When Doctor reports that the 30-day retention review is due, only report the reminder. Run `scripts/review-history-cleanup.ps1` to create a metadata-only proposal only when the user explicitly asks to review or clean history. Review never applies a proposal, loads history bodies into current context, or reads archives. Applying cleanup requires the separate global command, the exact proposal path, and explicit approval; it is never automatic.

Codex may consult project history without a separate user instruction whenever it can help. Start at `history/index.md`, then read the records useful to the task. Use historical conclusions according to context and risk; if historical and current evidence actually conflict, resolve the conflict using the evidence appropriate to the task.
