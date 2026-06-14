---
name: script-recast-cache-builder
description: Project-local workflow for building, repairing, and proofreading Novel Studio Script Recast caches in NAI_NEW. Use when the user asks to make or fix "剧本缓存", "剧本 cache", "Script Recast cache", role field cache, AI role extraction cache, per-script character-slot cache, or a source-evidence-only character/frame/slot cache.
---

# Script Recast Cache Builder

Use this skill only inside `C:\Users\admin\Downloads\NAI_NEW`. It handles the
project's Script Recast cache format: each character role, the frames where it
appears, the slot/source appearances it belongs to, and the five role fields
`identity`, `upper_body`, `lower_body`, `upper_clothing`, and
`lower_clothing`.

## Hard Rules

- User hard requirement: no external skills; do not chain or rely on other
  skills during cache production or proofreading.
- User hard requirement: do not call the user's configured Script AI API,
  OpenAI-compatible endpoint, token, proxy, or any project-stored API credential
  when rebuilding caches, translating cache display names, or filling
  translation cache entries. Use Codex's own reasoning/model capacity and
  allowed subagents instead.
- Do not invoke external skills while producing or proofreading caches. Work
  from this skill, repository code, repository tools, cache JSON, source frame
  prompts, and user-provided instructions.
- Do not use unrelated app-wide asset, image, browser, OpenAI-docs, or design
  workflows to infer role fields.
- Do not invent, translate, prettify, or silently rewrite prompt terms. Any
  changed term needs source evidence and must be reported.
- Every real role must have a human-facing Chinese name/translation available
  for the UI. Keep source prompt tokens and canonical identity in their original
  form; put translation only in display metadata or UI-facing labels.
- Do not fill missing clothing/body fields from character defaults or memory.
  Empty fields are valid when the source frame evidence is missing.
- Do not write action, scene, camera, pose, expression, transient state, warning,
  or non-role material into role fields.
- Do not put body traits in clothing fields or worn garments in body fields.
- Outfit/stage display names should include source-evidenced context when it
  helps recognition, such as "浴室裸体" or "车间工装". Context belongs in the
  stage/display label, not in the five prompt replacement fields unless the
  underlying tag is itself valid role evidence for that field.
- Split stages by replacement-relevant outfit/body state, not by story beat,
  action, pose, camera, or contiguous frame range. Equivalent appearances such
  as the same nude state or the same primary upper garment should be one stage
  with possibly non-contiguous `frame_indexes`.
- A completed cache must not leave duplicate stage labels under the same role.
  If two stages would show the same UI outfit/body-state label for one role,
  merge them and preserve all source frame indexes unless source evidence proves
  they are replacement-different appearances.
- Preserve long-term `script_recast/knowledge.json` unless the user explicitly
  asks to update confirmed knowledge.

## Required Context

Read `references/cache-contract.md` before changing cache files or sending work
to subagents.

Always identify:

- active cache directory, usually
  `C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\script_recast\cache`;
- source root and any ASCII junction/copy used for shell safety;
- target script ids and frame counts;
- whether caches are ready, idle, partial, or stale.

## Workflow

1. Inspect existing project memory with `bd prime` and search for relevant prior
   cache work, but do not treat historical memories as process exemplars unless
   their provenance is verified. Use the synthetic example in
   `references/cache-contract.md` only for schema shape.
2. Inspect the target cache JSON and source frame evidence. The source of truth
   is `scriptSnapshot.frames[*].parsed`, especially `baseCaption`,
   `charCaptions`, coordinates, and raw metadata copied into the snapshot.
3. Build or repair `aiRoleExtraction.roles` so every real role has:
   `source_role_id`, display/canonical identity, `frame_indexes`,
   `appearances[*].source_id`, a Chinese UI-facing display translation, and
   stage-level five-field output plus context-aware Chinese outfit labels.
4. When the batch is large, split work by independent script ids or frame ranges
   and open subagents if available. Subagent prompts must say not to use other
   skills and must pass the cache contract, raw target ids, and audit goals
   only; do not pass expected answers.
5. Apply changes only after making a backup under `build/` or another explicit
   backup directory.
6. Proofread every result with the quality gates in `references/cache-contract.md`.
7. Summarize changed files, role counts, audit reports, unresolved blanks, and
   anything left for user review.

## Quality Gate

A cache is not done until all applicable checks pass:

- source/root/frame integrity has zero issues;
- slot coverage and role frame references have zero issues;
- every parsed frame with non-empty `charCaptions` is covered by a role unless
  explicitly classified as no-role scene/transition;
- role fields contain only source-evidenced identity/body/clothing terms;
- every real role has a Chinese UI-facing name/translation, while canonical
  prompt identity remains source-faithful;
- outfit/stage labels are Chinese and include source-evidenced context when
  useful without leaking scene/action terms into five fields;
- per-role duplicate outfit/stage labels are zero after generation;
- role field proofreading dry-run reports zero remaining changes;
- custom structural repair dry-run, if created, reports zero changes;
- all term changes are visible in a report or final summary.

If any gate fails, repair and rerun the same gate. Do not call the task complete
because the output "looks plausible".
