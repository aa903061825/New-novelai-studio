# Script Recast Complete AI Term Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Script Recast project AI and Codex offline script handling use the same complete source-term contract for role replacement, scene replacement, translation suggestions, classification suggestions, and mapping preservation.

**Architecture:** Local code prepares complete deduplicated source-term evidence with cache hit metadata and never performs semantic replacement filtering before AI. AI/Codex outputs role prompt terms, scene terms, cache suggestions, and exclusions. Application merge logic treats the new result as the latest structure while preserving existing user mappings and confirmed cache entries.

**Tech Stack:** Flutter/Dart models and services, existing Script Recast cache JSON, existing `TranslationCache`, existing `PromptTagClassificationCache`, Node/Dart tool scripts for offline migration and audit.

## Global Constraints

- Do not call project-configured API, NAI token, proxy, OpenAI-compatible endpoint, or stored credentials from Codex offline repair.
- Do not use local semantic filters to decide replacement membership before AI sees source terms.
- Preserve existing user-confirmed role and scene replacement mappings when rebuilding or repairing caches.
- Preserve manual translation/classification cache entries unless the user explicitly asks to replace them.
- Scene terms belong in a scene replacement area, not in role replacement terms.
- Base/global prompt terms must be sent to AI as complete evidence and must not be treated as scene-only by local code.
- Existing cache repair scripts that use local regex whitelists are deprecated unless converted to audit-only or schema-driven behavior.

---

## File Structure

- Modify `lib/data/studio/services/script_ai_role_evidence_builder.dart`
  - Responsibility: Build complete source-term evidence for AI request previews.
- Modify `lib/data/studio/services/script_ai_role_extraction_client.dart`
  - Responsibility: Prompt contract and expected AI JSON schema.
- Modify `lib/data/studio/services/script_ai_role_extraction_parser.dart`
  - Responsibility: Parse extended output fields and fail clearly on invalid output.
- Modify `lib/data/studio/models/script_ai_role_extraction.dart`
  - Responsibility: Store scene terms and cache suggestions in typed form.
- Modify `lib/data/studio/services/script_ai_role_extraction_service.dart`
  - Responsibility: Orchestrate extraction, merge cache suggestions, preserve prompt weights, and keep chunk merge stable.
- Modify `lib/data/studio/services/script_ai_role_assembly_application.dart`
  - Responsibility: Apply role/scene terms into mapping while preserving user mappings.
- Modify `lib/data/studio/models/script_recast.dart`
  - Responsibility: Add or confirm durable scene replacement mapping if current mapping cannot preserve scene user choices.
- Modify `lib/data/studio/tools/translation_cache.dart`
  - Responsibility: Merge missing AI/Codex translation suggestions without overriding manual entries.
- Modify `lib/data/studio/tools/prompt_tag_classifier.dart`
  - Responsibility: Merge missing AI/Codex classification suggestions without overriding manual entries.
- Modify `tool/normalize_script_recast_ai_cache.dart`
  - Responsibility: Stop synthesizing replacement terms with local semantic filters; preserve and normalize existing AI output and mappings.
- Replace or deprecate `tool/repair_script_recast_role_prompt_terms_20260627.mjs`
  - Responsibility: Become schema-driven offline audit/repair using complete source terms, not regex replacement membership.
- Test files:
  - `test/data/studio/services/script_ai_role_evidence_builder_test.dart`
  - `test/data/studio/services/script_ai_role_extraction_parser_test.dart`
  - `test/data/studio/services/script_ai_role_extraction_service_test.dart`
  - `test/data/studio/services/script_ai_role_assembly_application_test.dart`
  - `test/tool/normalize_script_recast_ai_cache_test.dart`
  - New offline tool tests if a replacement tool is added.

## Task 1: Complete Source-Term Evidence

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_evidence_builder.dart`
- Test: `test/data/studio/services/script_ai_role_evidence_builder_test.dart`

**Interfaces:**
- Consumes: `Script` and parsed `ScriptFrame` objects.
- Produces: AI request chunks containing complete per-term evidence entries with source, frame, cache, and polarity metadata.

- [ ] **Step 1: Write failing tests for complete source evidence**

Add tests that build a script with:

```text
base_caption: "bedroom, demon girl, wings, looking at viewer"
char_captions[0]: "double bun, gyaru, shirt lift, holding skirt"
negative_base: "bad anatomy"
```

Expected request preview:

- includes all positive base and slot terms
- includes action terms such as `looking at viewer`, `holding skirt`
- includes scene term `bedroom`
- includes role-like terms from base caption
- marks source id and source kind correctly
- does not drop terms by category

- [ ] **Step 2: Run the focused evidence builder test**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart --plain-name "builds complete source term evidence"
```

Expected: FAIL because complete term evidence table does not exist yet or lacks required fields.

- [ ] **Step 3: Implement complete term evidence entries**

Add a source term table to each chunk. Preserve existing `frame_prompts`, `sources[].tag_evidence`, and `timeline_segments` for compatibility.

Each entry should include:

```json
{
  "text": "double bun",
  "normalized": "double bun",
  "source_id": "slot-0",
  "source_kind": "slot",
  "polarity": "positive",
  "frame_indexes": [1],
  "source_phrase": "double bun, gyaru, shirt lift, holding skirt",
  "cached_translation": "",
  "cached_category": "",
  "needs_translation": true,
  "needs_category": true
}
```

- [ ] **Step 4: Add cache hit plumbing without semantic filtering**

Accept optional `TranslationCache` and `PromptTagClassificationCache` inputs in the request-building path or a companion enrichment step. Cache hits populate `cached_translation` and `cached_category`; misses set flags. Do not remove terms from the request.

- [ ] **Step 5: Verify evidence builder tests pass**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart
```

Expected: PASS.

## Task 2: AI Prompt And Output Schema

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_extraction_client.dart`
- Modify: `lib/data/studio/services/script_ai_role_extraction_parser.dart`
- Modify: `lib/data/studio/models/script_ai_role_extraction.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_parser_test.dart`

**Interfaces:**
- Consumes: complete source-term evidence.
- Produces: typed role prompt terms, scene terms, term cache suggestions, and optional excluded terms.

- [ ] **Step 1: Write parser tests for extended output**

Add a parser fixture with:

```json
{
  "schema_version": 1,
  "status": "ready",
  "roles": [
    {
      "source_role_id": "slot-0",
      "display_name": "角色A",
      "prompt_terms": [
        {
          "id": "term-double-bun",
          "text": "double bun",
          "category": "body",
          "source_phrase": "double bun",
          "source_location": "slot-0 prompt",
          "frame_indexes": [1]
        },
        {
          "id": "term-holding-skirt",
          "text": "holding skirt",
          "category": "clothing_state",
          "source_phrase": "holding skirt",
          "source_location": "slot-0 prompt",
          "frame_indexes": [1]
        }
      ],
      "stages": []
    }
  ],
  "scene_terms": [
    {
      "id": "scene-bedroom",
      "text": "bedroom",
      "category": "scene",
      "source_phrase": "bedroom",
      "source_location": "base prompt",
      "frame_indexes": [1]
    }
  ],
  "term_cache_suggestions": [
    {
      "text": "double bun",
      "translation": "双丸子头",
      "category": "upperBody",
      "source": "ai_extraction"
    }
  ]
}
```

Expected: parser preserves role terms, scene terms, and cache suggestions.

- [ ] **Step 2: Run parser test to verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_parser_test.dart --plain-name "parses scene terms and cache suggestions"
```

Expected: FAIL until model/parser supports cache suggestions.

- [ ] **Step 3: Extend model types**

Add typed structures for cache suggestions and optional excluded terms. Reuse existing `ScriptAiExtractedPromptTerm` for `scene_terms` when possible.

- [ ] **Step 4: Update client prompt**

Revise the system prompt so it states:

- The input term table is complete.
- Do not assume base prompt is scene-only.
- Do not hard-filter role-scoped terms.
- Use `other` for role-scoped replacement terms that do not fit a specific category.
- Put environment/place/background/time/light/weather into `scene_terms`.
- Only suggest translations/classifications for terms marked missing.
- Preserve cached values as context.

- [ ] **Step 5: Verify parser tests pass**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_parser_test.dart
```

Expected: PASS.

## Task 3: Cache Suggestion Merge

**Files:**
- Modify: `lib/data/studio/services/script_ai_role_extraction_service.dart`
- Modify: `lib/data/studio/tools/translation_cache.dart`
- Modify: `lib/data/studio/tools/prompt_tag_classifier.dart`
- Test: `test/data/studio/tools/translation_cache_test.dart`
- Test: `test/data/studio/tools/prompt_tag_classifier_test.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_service_test.dart`

**Interfaces:**
- Consumes: AI cache suggestions.
- Produces: updated cache entries for misses while preserving manual entries.

- [ ] **Step 1: Write tests for cache merge priority**

Cases:

- missing translation gets inserted with `source: ai_extraction`
- manual translation is not overwritten
- existing machine translation can be refreshed only when policy allows
- missing classification gets inserted
- manual classification is not overwritten

- [ ] **Step 2: Run cache merge tests to verify failure**

Run:

```powershell
flutter test test/data/studio/tools/translation_cache_test.dart test/data/studio/tools/prompt_tag_classifier_test.dart
```

Expected: FAIL on missing merge APIs or priority behavior.

- [ ] **Step 3: Add merge APIs**

Add methods equivalent to:

```dart
int mergeMissingSuggestions(Iterable<TermCacheSuggestion> suggestions);
```

Manual entries must win. Machine entries must carry source and timestamp.

- [ ] **Step 4: Wire extraction service to save suggestions**

When project AI extraction finishes, service merges missing translation/classification suggestions. If persistence fails, extraction result remains usable and warning/audit is recorded.

- [ ] **Step 5: Verify service/cache tests pass**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_service_test.dart test/data/studio/tools/translation_cache_test.dart test/data/studio/tools/prompt_tag_classifier_test.dart
```

Expected: PASS.

## Task 4: Role And Scene Replacement Merge

**Files:**
- Modify: `lib/data/studio/models/script_recast.dart`
- Modify: `lib/data/studio/services/script_ai_role_assembly_application.dart`
- Test: `test/data/studio/services/script_ai_role_assembly_application_test.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

**Interfaces:**
- Consumes: AI extraction with role prompt terms and scene terms.
- Produces: role and scene replacement mappings that preserve user choices.

- [ ] **Step 1: Write tests for preserving role mappings**

Fixture:

- existing `rolePromptReplacements` has `targetCharacterId`, `targetIdentityPrompt`, and a manual rule
- new AI extraction adds `double bun` and `wings`

Expected:

- old target and manual rule remain
- matching existing source terms reuse existing rules
- new source terms are appended as new rules

- [ ] **Step 2: Write tests for scene replacement mapping**

Fixture:

- existing scene replacement has a selected target or manual rule
- new AI extraction returns `scene_terms`

Expected:

- old scene mapping is preserved
- new scene terms are added
- scene terms do not appear inside role replacement mappings

- [ ] **Step 3: Run mapping tests to verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_assembly_application_test.dart --plain-name "merges AI role and scene replacement terms without losing user mappings"
```

Expected: FAIL until merge logic supports the new contract.

- [ ] **Step 4: Implement merge logic**

Use new AI/Codex result as structure baseline, but merge existing user data:

- preserve user targets
- preserve manual rules
- preserve stale user rules with audit flag
- append missing new terms
- keep role and scene mappings separate

- [ ] **Step 5: Verify UI replacement tests**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction keeps prompt and scene replacement terms when applied"
```

Expected: PASS.

## Task 5: Normalize Tool Cleanup

**Files:**
- Modify: `tool/normalize_script_recast_ai_cache.dart`
- Test: `test/tool/normalize_script_recast_ai_cache_test.dart`

**Interfaces:**
- Consumes: existing cache JSON.
- Produces: normalized cache JSON without local semantic replacement synthesis.

- [ ] **Step 1: Add test that local normalization does not synthesize semantic prompt terms**

Input cache:

- source captions contain role and action terms
- AI extraction has no `prompt_terms`

Expected:

- normalizer does not create replacement terms from local whitelist
- existing mappings are preserved
- audit output can report missing AI terms

- [ ] **Step 2: Add test that normalizer preserves existing prompt terms and mappings**

Input cache:

- AI extraction has `prompt_terms`
- mapping has existing selected target

Expected:

- prompt terms are retained
- mapping target is retained
- new structure can be normalized without clearing user work

- [ ] **Step 3: Run tests to verify failure**

Run:

```powershell
flutter test test/tool/normalize_script_recast_ai_cache_test.dart --plain-name "normalizer preserves AI prompt terms without local semantic synthesis"
```

Expected: FAIL until old local fallback behavior is removed or gated.

- [ ] **Step 4: Remove or gate local semantic synthesis**

Remove local role prompt candidate filters from normalizer. If needed, replace them with audit-only diagnostics.

- [ ] **Step 5: Verify normalizer tests**

Run:

```powershell
flutter test test/tool/normalize_script_recast_ai_cache_test.dart
```

Expected: PASS.

## Task 6: Codex Offline Script Processing Tool

**Files:**
- Replace or modify: `tool/repair_script_recast_role_prompt_terms_20260627.mjs`
- Create: `tool/script_recast_complete_term_audit.mjs`
- Create: `tool/script_recast_codex_offline_repair_schema.md`
- Test: `test/tool/script_recast_complete_term_audit_test.dart`

**Interfaces:**
- Consumes: local source directory and active cache directory.
- Produces: audit report and optional repaired cache using the same contract as project AI, without project API use.

- [ ] **Step 1: Define offline input/output report schema**

Report must include:

- files scanned
- eligible caches
- complete source term count
- role terms proposed
- scene terms proposed
- translation suggestions
- classification suggestions
- preserved role mappings
- preserved scene mappings
- stale retained rules
- target regression misses

- [ ] **Step 2: Add dry-run-only fixture test**

Use a small fixture script where:

- base prompt contains a role term
- slot prompt contains `double bun`
- scene term is `bedroom`
- existing mapping has a selected target

Expected dry-run report:

- no API used
- role and scene terms proposed
- existing mapping marked preserved
- no write without `--apply`

- [ ] **Step 3: Convert old repair script behavior**

Remove local regex membership as the repair source of truth. The tool may still use local parsing and normalization to create complete evidence, but role/scene membership must come from Codex-generated schema output or existing AI output.

- [ ] **Step 4: Add apply mode with backup and merge**

Apply mode must:

- create a backup before editing
- preserve existing user mappings
- add missing role and scene terms
- add missing cache suggestions
- emit an audit report

- [ ] **Step 5: Verify offline tool tests**

Run:

```powershell
flutter test test/tool
node --check tool/script_recast_complete_term_audit.mjs
```

Expected: PASS for the relevant tests and syntax checks.

## Task 7: End-To-End Regression Sweep

**Files:**
- Modify tests across the files listed above.
- No production code changes unless a failing regression reveals a missing integration.

**Interfaces:**
- Consumes: implemented tasks.
- Produces: verified behavior across project AI and offline processing.

- [ ] **Step 1: Run focused regression tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart test/data/studio/services/script_ai_role_extraction_service_test.dart test/data/studio/services/script_ai_role_assembly_application_test.dart test/tool/normalize_script_recast_ai_cache_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run UI replacement tests**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart --plain-name "AI role extraction"
```

Expected: PASS or known unrelated timeout documented with focused passing tests.

- [ ] **Step 3: Run an offline dry-run against the target source root**

Run only dry-run unless the user explicitly asks to apply:

```powershell
node tool/script_recast_complete_term_audit.mjs --cache-dir "C:\Users\admin\AppData\Roaming\Novel Studio\Novel Studio\novel_studio\script_recast\cache" --source-root "E:\NAI的脚本群\作品集\带图精品" --report "build\script_recast_complete_term_audit_YYYYMMDD.json"
```

Expected:

- no API usage
- no cache write
- report lists role, scene, translation, classification, and preserved mapping counts

- [ ] **Step 4: Review audit with user before apply**

Do not apply broad cache edits until the user approves the audit report.

## Self-Review Checklist

- Every task has concrete files.
- Every task has a failing-test-first step.
- The plan keeps project AI and Codex offline handling on the same schema.
- The plan does not authorize API-backed offline repair.
- The plan preserves user mappings and manual cache entries.
- The plan treats scene terms as a separate replacement area.
- The plan removes local semantic filtering as replacement source of truth.

## Execution Choice

Plan complete. Recommended execution approach after user approval:

1. **Subagent-Driven** - one task per worker, with review after each task.
2. **Inline Execution** - execute tasks in this session with checkpoints.

Do not start execution until the user chooses an approach.
