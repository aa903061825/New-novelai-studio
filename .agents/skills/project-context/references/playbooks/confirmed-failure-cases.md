# Confirmed Failure Cases

Historical examples only. These are not task instructions and not authoritative current facts.

## Case: Single-script saves felt stuck because they scanned the full Recast cache

Source record: `NAI_NEW-dl3c`, 2026-06-09
User confirmation: user-facing stuck behavior was reproduced and root cause was confirmed.
Case note: verified historical performance failure

Applies when: editing Script Recast save/restore, cache loaders, StudioScriptViewModel, or workbench persistence.

Do not infer: that current cache size or loader names are unchanged; inspect current code and runtime cache.

What happened: single-script save/restore fell back to full `loadRecastCaches` even when targeted `loadRecastCacheByScriptId` was available. The active cache had 102 JSON files totaling about 1.08GB; full read plus JSON parse sampling took about 3.3s before Dart model construction.

Useful lesson: preservation guards must not silently trigger bulk cache scans on ordinary edits.

Verify now by: measuring targeted save/restore path, checking cache-loader tests, and confirming no full-directory parse occurs for a single-script edit.

## Case: Fix appeared invisible because a stale app process rewrote old cache

Source record: `NAI_NEW-cis7`, 2026-06-17
User confirmation: user still saw old UI until stale process/cache were removed.
Case note: verified historical runtime/cache failure

Applies when: code changes seem not to appear in the running Windows app.

Do not infer: that a code fix failed before checking process, build output, and cache ownership.

What happened: the user was viewing a stale `Novel_Studio` process that rewrote schema 6 asset cache. Stopping the stale process, deleting cache, rebuilding release, and launching a fresh process made the change visible.

Useful lesson: debug runtime visibility by validating process identity, build artifact freshness, workspace path, and cache schema before changing logic again.

Verify now by: checking running processes, release artifact timestamps, cache schema/version, and actual runtime workspace path.

## Case: Drag selection and card dragging regressed each other

Source record: `NAI_NEW-uboe`, 2026-06-20
User confirmation: user repeatedly reported marquee/drag regressions after partial fixes.
Case note: verified historical interaction regression pattern

Applies when: editing Script Exhibition Room marquee selection, card drag gestures, card rect caches, or scrolled shelf geometry.

Do not infer: that one pointer-down rule can handle both card drag and empty-gap marquee.

What happened: gutter marquee, inter-card gap marquee, scrolled geometry, and card body dragging each regressed when the fix treated hit testing too broadly. The accepted direction split drag initiation from marquee initiation and refreshed geometry correctly for scrolled shelves.

Useful lesson: card body drag and empty-area marquee must be tested separately, including scrolled shelves and inter-card gaps.

Verify now by: running focused widget tests for card drag, gutter marquee, inter-card gap marquee, scrolled selection, and card rect cache refresh.

## Case: Mistaken deletion required non-overwriting recovery from local backups

Source record: `NAI_NEW-l9nd`, 2026-06-17
User confirmation: user had intended to delete a version, not the exhibition record.
Case note: verified historical recovery pattern

Applies when: handling Script Exhibition deletion, restore, cache recovery, gallery recovery, or backup search.

Do not infer: that backups still exist at old paths.

What happened: missing Script Exhibition recast caches were restored by non-overwriting copy from backup directories. Existing production plans and generated outputs were verified before reporting recovery.

Useful lesson: recovery must be scoped and non-destructive. Search local cache backups, production plans, gallery records, source folders, and generated outputs before touching source files.

Verify now by: listing candidate backups, diffing target paths, using non-overwriting copy, and verifying restored records against current production plans/outputs.

## Case: AI role extraction ran after zero parsed frames

Source record: `NAI_NEW-rkad`, 2026-06-03
User confirmation: user-facing AI role extraction failed with no parsed frames.
Case note: verified historical guard failure

Applies when: editing script import, parser filename handling, AI role extraction, or empty import guidance.

Do not infer: that all valid frame names are still limited to the old patterns.

What happened: AI role extraction was allowed to run after importing a script with zero parsed frames, causing a backend failure. The accepted fix stopped before the AI call, recorded a blocking `no_parsed_frames` failure, and gave actionable guidance.

Useful lesson: validate parsed-frame presence before invoking AI or downstream role extraction. Empty import should be a local actionable error, not an AI request failure.

Verify now by: parser tests, empty-frame UI tests, AI role extraction service tests, and focused analyze.
