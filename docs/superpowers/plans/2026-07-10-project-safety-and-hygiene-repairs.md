# Project Safety And Hygiene Repairs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for every behavior change. Work in the current tree because the bugs exist in uncommitted project work; never revert unrelated changes.

**Goal:** Repair the confirmed persistence and async-state bugs while preserving the intentional image-orphan deletion policy, then apply only mechanically verifiable repository cleanup.

**Architecture:** Use existing workspace and view-model boundaries. Recover missing workspace metadata without overwriting data files, bind asynchronous UI operations to monotonic generations, and serialize character prompt mutations against the latest local catalog snapshot. Repository cleanup is limited to invalid CI/tool syntax, ignored runtime output, and zero-reference artifacts.

**Tech Stack:** Flutter, Dart, Hive, flutter_test, GitHub Actions YAML, Node.js ESM tools.

## Global Constraints

- Preserve the existing Script Exhibition rule that unreferenced images under configured generated roots are deleted.
- Do not call any configured API, translation endpoint, NAI token, proxy, or cache-generation workflow.
- Preserve every unrelated uncommitted change in the current worktree.
- Add deterministic regression tests before each Dart behavior fix and observe the expected failure.
- Use `flutter test --no-pub` and `flutter analyze --no-pub` for verification.

---

### Task 1: Recover A Workspace With A Missing Manifest

**Files:**
- Modify: `test/data/studio/studio_data_service_test.dart`
- Modify: `lib/data/studio/studio_data_service.dart`
- Modify: `lib/data/workspace/workspace_service.dart`

- [x] Add tests that create characters, delete only `studio_manifest.json`, and verify initialization preserves characters both with and without a bundled cache.
- [x] Run `flutter test --no-pub test/data/studio/studio_data_service_test.dart` and verify the new tests fail because characters are cleared or overwritten.
- [x] Add a workspace-data presence check and a scaffold recovery path that writes a new manifest and only creates missing files.
- [x] Verify recovery happens before legacy-workspace comparison so current data cannot be overwritten by a legacy root.
- [x] Re-run the focused tests and verify they pass.

### Task 2: Make Config Persistence Target Stable

**Files:**
- Modify: `test/data/services/config_service_preview_test.dart`
- Modify: `lib/data/services/config_service.dart`

- [x] Add tests proving `saveConfig` keeps the UUID captured before its first await, immediate rename after `saveConfigByUuid` is retained, and deletion persists the updated index.
- [x] Run `flutter test --no-pub test/data/services/config_service_preview_test.dart` and verify all three regressions fail for their expected reasons.
- [x] Capture the UUID before awaiting, publish a new index entry before the config write yields, and save the index after deletion.
- [x] Re-run the focused test and verify it passes.

### Task 3: Stop Stale Production Requests Before Saving

**Files:**
- Modify: `test/data/studio/services/production_executor_service_test.dart`
- Modify: `lib/data/studio/services/production_executor_service.dart`

- [x] Add a completer-controlled test that invalidates a run while `requestImage` is pending and asserts no image save occurs after the request completes.
- [x] Run `flutter test --no-pub test/data/studio/services/production_executor_service_test.dart` and verify the new test fails because save is called.
- [x] Separate "may start another task" from "may accept this result" so pause can finish the current task while stop discards a stale response.
- [x] Re-run the focused executor and production-queue tests and verify they pass.

### Task 4: Bind Script Imports And Sends To Their Document

**Files:**
- Modify: `test/ui/studio_script/studio_script_page_test.dart`
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`

- [x] Add a two-completer parser test showing a slow first import cannot replace a newer completed import.
- [x] Add a pending production test showing a send from script A cannot mark subsequently imported script B as sent.
- [x] Run the focused tests and verify both fail for stale state writes.
- [x] Capture and check the script-open generation after every awaited import stage; add a production-send generation and apply/finalize results only when both the generation and script identity still match.
- [x] Invalidate import and send generations during disposal and cover both pending-operation cases with regression tests.
- [x] Guard picker returns and cache-restore exception paths with explicit disposal state so no fresh token or notification can escape after disposal.
- [x] Re-run the focused tests and verify they pass.

### Task 5: Serialize Asset Character Prompt Mutations

**Files:**
- Modify: `test/ui/studio_shell/asset_library_page_test.dart`
- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`

- [x] Add widget tests for overlapping prompt edits, delete-versus-save ordering, and queued saves that finish after page disposal.
- [x] Run the focused tests and verify the old snapshot and parallel-save failures.
- [x] Add a non-failing character mutation tail plus a working catalog that survives disposal until every queued mutation completes.
- [x] Route all character/outfit saves, copies, deletes, preview deletes, and prompt edits through the same mutation queue.
- [x] Wait for queued mutations before opening character/outfit editors and resolve the edited entity from the newest catalog.
- [x] Re-run the focused tests and verify they pass.

### Task 6: Repair Deterministic Repository Hygiene Problems

**Files:**
- Modify: `.gitignore`
- Modify: `.github/workflows/android.yml`
- Modify: the 17 `tool/*.mjs` files reported by `node --check`
- Modify: `README.md`

- [x] Add `.codex-runtime/` to ignored local runtime output without changing the intentional tracked `.codex` project configuration.
- [x] Decode `SECRETS_JSON_CONTENT` through the shell pipeline outside the quoted secret value.
- [x] Replace the literal `\\n` in each broken MJS tool while preserving both required `Novel Studio` path segments.
- [x] Remove obsolete Beads commands from the contributor instructions because neither the files nor `bd` command exist.
- [x] Remove only zero-reference artifacts and dependencies whose deletion is mechanically verifiable.
- [x] Run `node --check` across all `tool/*.mjs` and verify zero syntax failures.

### Task 7: Verify The Integrated Result

- [x] Run focused tests for all five Dart repair areas.
- [x] Run `flutter analyze --no-pub` and require zero issues.
- [x] Run `git diff --check` and distinguish pre-existing whitespace issues from new ones.
- [x] Review the final diff by file and confirm no Script Exhibition orphan-deletion behavior changed.
