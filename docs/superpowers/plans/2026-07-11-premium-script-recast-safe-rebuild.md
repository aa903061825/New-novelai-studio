# Premium Script Recast Safe Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild every Script Recast cache under `E:\NAI的脚本群\作品集\带图精品` without hidden slot mappings, male-role replacement, or POV-hand pseudo roles, then promote only a fully validated staging set.

**Architecture:** Rebuild in an isolated staging directory from copies of the active caches. The offline extraction tool regenerates role evidence, the target-mapping tool writes only identity-level mappings, and a fail-closed validator audits the entire staged set before any active cache is replaced. Promotion uses a timestamped full backup and copies only the exact eligible cache-file set.

**Tech Stack:** Flutter/Dart tests, Node.js offline cache tools, JSON Script Recast caches, PowerShell filesystem orchestration.

## Global Constraints

- Never call the configured API, OpenAI-compatible endpoint, NAI token, proxy, or any project-stored credential.
- Do not modify source images or source script directories under `E:\NAI的脚本群\作品集\带图精品`.
- Do not promote staged caches unless every strict validator counter is zero and all focused Dart tests pass.
- Back up every active cache selected for promotion before overwriting it.
- Treat filename `ペコリーヌ 悪堕ち調教_合并2个图集_p32.png` as the concrete regression frame: its male slot must remain male and must not receive a target-character prompt.

---

### Task 1: Remove Hidden Slot Mapping Execution

**Files:**
- Modify: `lib/data/studio/services/script_recast_engine.dart`
- Modify: `tool/apply_ntr_story_target_mapping_offline.mjs`
- Test: `test/data/studio/services/script_recast_engine_test.dart`
- Test: `test/tool/apply_ntr_story_target_mapping_offline_test.dart`

**Interfaces:**
- Consumes: `RecastMapping.rolePromptReplacements`, role assembly appearances, legacy `roleSwaps`.
- Produces: identity-level mappings that own their dynamic slots and no generated global slot swaps.

- [x] **Step 1: Add a failing engine regression for a female role moving between slots while a hidden legacy swap targets the male slot.**
- [x] **Step 2: Verify the regression fails because the male caption becomes the target character.**
- [x] **Step 3: Suppress legacy swaps on every slot owned by an identity-level replacement.**
- [x] **Step 4: Add and verify a failing mapping-tool regression that observes generated global slot swaps.**
- [x] **Step 5: Stop the mapping tool from writing `roleSwaps` and verify both tests pass.**

### Task 2: Remove POV-Hand Pseudo Roles

**Files:**
- Modify: `tool/build_script_recast_ai_extraction_offline.mjs`
- Test: `test/tool/build_script_recast_ai_extraction_offline_test.dart`

**Interfaces:**
- Consumes: per-frame character captions.
- Produces: roles only for whole-character or stable identity evidence; captions such as `girl, pov hands, white gloves` remain non-role evidence.

- [x] **Step 1: Add a failing fixture containing one POV-hand slot and one concrete character slot.**
- [x] **Step 2: Verify extraction incorrectly emits `role-girl-slot-0`.**
- [x] **Step 3: Reject generic POV/only-hand/disembodied-hand captions without concrete or whole-character evidence.**
- [x] **Step 4: Verify the concrete role remains and the pseudo role disappears.**

### Task 3: Add Fail-Closed Batch Validation

**Files:**
- Create: `tool/validate_script_recast_mapping_safety.mjs`
- Create: `test/tool/validate_script_recast_mapping_safety_test.dart`

**Interfaces:**
- Consumes: `--cache-dir`, `--source-root`, optional `--report`, and optional frame regression selectors.
- Produces: JSON counters and exit code `0` only when all safety invariants pass.

- [x] **Step 1: Add a failing test fixture with a hidden `roleSwap`, mapped male role, POV pseudo role, and overlapping role appearances.**
- [x] **Step 2: Verify the validator reports each violation and exits nonzero.**
- [x] **Step 3: Implement checks for parse failures, duplicate IDs, hidden swaps, mapped male roles, pseudo partial-body roles, appearance collisions, target/stage mismatch, missing identity rules, and the P32 male-slot regression.**
- [x] **Step 4: Add a clean fixture and verify exit code `0` with every violation counter equal to zero.**

### Task 4: Build the Complete Staging Set

**Files:**
- Generate: `build/script_recast_premium_rebuild_20260711/source_cache/`
- Generate: `build/script_recast_premium_rebuild_20260711/offline_cache/`
- Generate: `build/script_recast_premium_rebuild_20260711/workspace/script_recast/cache/`
- Generate: JSON selection and rebuild reports in the same build directory.

**Interfaces:**
- Consumes: active caches whose normalized `sourceRootPath` is under the requested source root.
- Produces: an exact one-for-one staged cache set.

- [x] **Step 1: Select eligible active caches by parsed `sourceRootPath`; record filenames, script IDs, source paths, hashes, and counts.**
- [x] **Step 2: Copy only that manifest set into `source_cache`.**
- [x] **Step 3: Run `node tool/build_script_recast_ai_extraction_offline.mjs --cache-dir ... --output-dir ... --apply` without API-backed helpers.**
- [x] **Step 4: Verify input/output filename sets and counts are identical.**
- [x] **Step 5: Run `node tool/apply_ntr_story_target_mapping_offline.mjs --workspace ... --source-root "E:\NAI的脚本群\作品集\带图精品" --apply`.**

### Task 5: Strict Acceptance and Promotion

**Files:**
- Generate: `build/script_recast_premium_rebuild_20260711/strict_validation.json`
- Generate: `build/script_recast_premium_rebuild_20260711/complete_term_audit.json`
- Generate: `%APPDATA%\Novel Studio\Novel Studio\novel_studio\script_recast\cache_backup_before_premium_rebuild_20260711-*\`
- Modify: only eligible JSON files in the active Script Recast cache directory.

**Interfaces:**
- Consumes: staged mapped caches and the selection manifest.
- Produces: backed-up, validated active caches.

- [x] **Step 1: Run the strict validator and require zero violations.**
- [x] **Step 2: Run the complete-term audit in read-only mode and record uncovered-term and path-integrity counts.**
- [x] **Step 3: Run focused engine, extraction, mapping, validator, cache-model, and restore tests.**
- [x] **Step 4: Assert the P32 source male slot remains unchanged and contains no configured target identity after resolution.**
- [x] **Step 5: Back up the exact active manifest set, copy staged files into active cache, and compare promoted hashes to staged hashes.**
- [x] **Step 6: Re-run strict validation against active cache and require the same clean result.**
