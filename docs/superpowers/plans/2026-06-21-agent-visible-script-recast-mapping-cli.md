# Agent-Visible Script Recast Mapping CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This repository is in stealth mode, so git commit steps are intentionally omitted.

**Goal:** Add a local tool that lets Codex apply visible Script Workbench mapping-only patches to Script Recast caches with backup and validation.

**Architecture:** Create a focused Dart CLI under `tool/` that loads one target cache from a workspace or explicit cache file, applies an upsert patch to `mapping.rolePromptReplacements` and `mapping.scenePromptReplacements`, preserves `aiRoleExtraction` by default, writes a timestamped backup, and saves the updated cache. Keep the existing Script Workbench UI and replacement engine unchanged.

**Tech Stack:** Dart, Flutter test, existing `RecastScriptCache`, `RecastMapping`, `ScriptRolePromptReplacement`, `ScriptScenePromptReplacement`, and `WorkspaceService` JSON formats.

---

## File Structure

- Create `tool/agent_script_recast_mapping.dart`: CLI entrypoint plus small pure helpers for parsing patch JSON, applying replacement upserts, computing cache paths, backing up files, and validating extraction preservation.
- Create `test/tool/agent_script_recast_mapping_test.dart`: focused tests for mapping-only behavior, backup creation, dry-run behavior, and invalid script-id protection.

## Patch Contract

The tool accepts a JSON patch file:

```json
{
  "scriptId": "script-a",
  "rolePromptReplacements": [
    {
      "sourceRoleId": "slot-0",
      "displayLabel": "Role A",
      "rules": [
        {
          "id": "agent-rule-hair",
          "sourceTerms": [
            {
              "id": "source-long-hair",
              "text": "long hair",
              "category": "body",
              "frameIndexes": [1, 2]
            }
          ],
          "targetPrompt": "short hair"
        }
      ]
    }
  ],
  "scenePromptReplacements": []
}
```

The tool upserts role groups by `sourceRoleId` and scene groups by `id`. Groups
not included in the patch remain unchanged. `aiRoleExtraction` must remain
byte-for-byte equivalent after JSON serialization unless a future explicit mode
is added for extraction repair.

## Task 1: Failing Tests

**Files:**
- Create: `test/tool/agent_script_recast_mapping_test.dart`
- Create later: `tool/agent_script_recast_mapping.dart`

- [ ] **Step 1: Write tests for mapping-only apply**

Create `test/tool/agent_script_recast_mapping_test.dart` with tests that:

- write a temporary cache file containing `aiRoleExtraction`;
- write a patch file containing one role replacement group and one scene group;
- call `runAgentScriptRecastMapping(['apply', '--cache-file', cachePath, '--patch', patchPath, '--backup-dir', backupPath])`;
- assert the cache mapping contains the new visible replacement groups;
- assert serialized `aiRoleExtraction` is unchanged;
- assert one backup file exists.

- [ ] **Step 2: Write tests for dry-run and script-id mismatch**

Add tests that:

- run `--dry-run` and assert the cache file is unchanged and no backup is written;
- pass a patch whose `scriptId` differs from the cache and assert the command exits non-zero without mutating the cache.

- [ ] **Step 3: Run tests and verify RED**

Run:

```powershell
flutter test --no-pub test/tool/agent_script_recast_mapping_test.dart -r expanded
```

Expected: FAIL because `tool/agent_script_recast_mapping.dart` does not exist.

## Task 2: Minimal CLI Implementation

**Files:**
- Create: `tool/agent_script_recast_mapping.dart`
- Test: `test/tool/agent_script_recast_mapping_test.dart`

- [ ] **Step 1: Add CLI entrypoint and argument parser**

Implement `main(List<String> args)` and `runAgentScriptRecastMapping(List<String> args)`. Support only:

```text
apply --patch <file> (--cache-file <file> | --workspace <dir> --script-id <id>) [--backup-dir <dir>] [--dry-run]
```

- [ ] **Step 2: Load cache and patch**

Parse cache JSON through `RecastScriptCache.fromJson`. Parse patch JSON into a small `AgentScriptRecastMappingPatch` that contains `scriptId`, `rolePromptReplacements`, and `scenePromptReplacements`.

- [ ] **Step 3: Apply mapping-only upserts**

Build a new cache with:

- role replacement groups upserted by `sourceRoleId`;
- scene replacement groups upserted by `id`;
- `updatedAt` refreshed only for real writes;
- all other cache fields preserved.

- [ ] **Step 4: Validate `aiRoleExtraction` preservation**

Serialize `aiRoleExtraction.toJson()` before and after applying the patch and fail if they differ.

- [ ] **Step 5: Backup and write**

For non-dry-runs, copy the original cache file into `backupDir` or a default `build/script_recast_agent_mapping_backups/<timestamp>` directory before writing the compacted updated cache.

- [ ] **Step 6: Run tests and verify GREEN**

Run:

```powershell
flutter test --no-pub test/tool/agent_script_recast_mapping_test.dart -r expanded
```

Expected: PASS.

## Task 3: Focused Integration Check

**Files:**
- Test: `test/tool/agent_script_recast_mapping_test.dart`
- Existing verification: `test/data/studio/services/script_recast_engine_test.dart`

- [ ] **Step 1: Run mapping CLI tests**

Run:

```powershell
flutter test --no-pub test/tool/agent_script_recast_mapping_test.dart -r expanded
```

- [ ] **Step 2: Run replacement engine tests**

Run:

```powershell
flutter test --no-pub test/data/studio/services/script_prompt_replacement_engine_test.dart test/data/studio/services/script_recast_engine_test.dart -r expanded
```

- [ ] **Step 3: Report impact**

Summarize that the new tool is additive, does not change Script Workbench UI, does not mutate extraction data, and only changes target cache files when explicitly run.
