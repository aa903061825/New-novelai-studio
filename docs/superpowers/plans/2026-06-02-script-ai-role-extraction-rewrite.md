# Script AI Role Extraction Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new evidence-first Script AI role extraction workflow that derives actual roles, five-field role parts, outfit stages, artist-chain terms, and mosaic/censor strong-filter terms from raw script tags.

**Architecture:** Do not extend the old asset-matching `ScriptAiRecastPlan` semantics. Create a new role-extraction model/service/client/builder stack, then wire the Script page to use the new stack. Existing Script Recast parsing, preview, cache, filter-rule saving, and final `RoleAssemblyStage.manualParts` output are reused only as integration points.

**Tech Stack:** Flutter/Dart, existing Script Recast domain models, existing OpenAI-compatible request infrastructure, existing `PromptTagProcessor`, existing strong filter rules helper, `flutter_test`, Beads. Git operations are intentionally omitted because this project is in stealth mode.

---

## Direction

The previous AI auto-plan direction is no longer the target. Do not continue designing around candidate character matching, candidate outfit matching, artist-chain IDs, vibes, or asset catalog selection.

The new workflow is:

```text
raw script prompt/tag evidence
  -> AI infers actual role count
  -> AI creates slot-* and/or global-* roles
  -> AI fills identity / upper_body / lower_body / upper_clothing / lower_clothing
  -> AI groups meaningful outfit stage changes
  -> AI extracts artist-chain evidence, including official art/style terms
  -> AI extracts mosaic/censor terms for strong filter keywords
  -> app applies only high-confidence five-field stages and filter terms
```

The AI should not handle action, pose, expression, camera, background, lighting, composition, quality tags, vibe references, or local asset matching.

## New Files And Responsibilities

- Create `lib/data/studio/models/script_ai_role_extraction.dart`
  - New schema and data classes for the new workflow.
  - No dependency on old `ScriptAiRecastPlan` names.

- Create `lib/data/studio/services/script_ai_role_evidence_builder.dart`
  - Builds raw evidence chunks from parsed script frames.
  - Sends no candidate characters, outfits, artist chain assets, or vibes.

- Create `lib/data/studio/services/script_ai_role_extraction_parser.dart`
  - Tolerantly recovers strict JSON object responses.
  - Converts invalid responses into failed extraction objects with raw response.

- Create `lib/data/studio/services/script_ai_role_extraction_client.dart`
  - Sends OpenAI-compatible chat completion requests with the prompt in this plan.

- Create `lib/data/studio/services/script_ai_role_extraction_merger.dart`
  - Deterministically merges chunk-level extraction outputs.

- Create `lib/data/studio/services/script_ai_role_extraction_service.dart`
  - Orchestrates chunk building, AI calls, parsing, and merging.

- Modify `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Add new extraction state and actions.
  - Apply high-confidence extracted roles/stages to `RoleAssemblyStage.manualParts`.
  - Append mosaic/censor terms to strong filter keywords.

- Modify `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Replace the old AI plan panel/actions with role-extraction copy and display.

- Modify `lib/main.dart`
  - Register the new default role-extraction service.
  - Stop wiring the Script page to the old plan service.

- Modify `lib/data/studio/models/script_recast_knowledge.dart`
  - Persist the new extraction draft in script cache.
  - Keep old cache fields readable only if needed for backward compatibility.

Old `script_ai_plan_*` files may remain temporarily if deleting them creates churn, but the new workflow must not call them. If the final analyzer shows they are unused but harmless, leave them for a later cleanup unless the implementing agent chooses to remove all references and tests cleanly.

---

## Complete AI System Prompt

Use this exact system prompt in `OpenAiCompatibleScriptAiRoleExtractionClient`.

```text
You are a Script AI role extraction engine for Script Recast.

Return strict JSON only. Do not include Markdown, comments, prose, explanations, or code fences.

You receive raw script tag evidence. Your job is to infer the actual roles and fill only the five Script Recast fields:

1. identity
2. upper_body
3. lower_body
4. upper_clothing
5. lower_clothing

You also extract:

1. meaningful outfit stage changes for each role
2. artist-chain evidence terms
3. mosaic/censor terms for strong filter keywords
4. warnings and unassigned terms

You do not manage action, pose, expression, camera, background, lighting, composition, quality tags, vibe references, or local asset matching.

Input can contain:
- slotted character captions
- base/global prompt tags
- negative prompt tags
- raw tag frequency and frame evidence

Role inference rules:
- If evidence has source_id like slot-0, reuse it exactly as source_role_id.
- If base/global prompt evidence clearly contains characters without slot IDs, create global roles: global-0, global-1, global-2, etc.
- You may infer multiple global roles from one mixed base prompt if the evidence supports it.
- Every role must include evidence_terms and frame_indexes.
- Do not invent tags. Every term in identity, upper_body, lower_body, upper_clothing, lower_clothing, artist_chains, strong_filter_keywords, and unassigned_terms must come from input evidence or an exact normalized spelling variant of input evidence.
- If role separation is uncertain, keep confidence below 0.75 and add warnings such as ambiguous_global_roles or cannot_assign_terms_to_role.
- If terms cannot be safely assigned to one role, put them in unassigned_terms.

Five-field classification rules:
- identity: character name, source identity, species, stable defining identity tags.
- upper_body: hair, eyes, arms, hands, chest, upper torso body traits. Exclude expressions and poses.
- lower_body: legs, feet, tail, lower torso body traits. Exclude actions and poses.
- upper_clothing: shirt, blouse, jacket, coat, robe top, armor top, uniform upper part, gloves when they are outfit pieces.
- lower_clothing: skirt, pants, shorts, legwear, socks, thighhighs, shoes, boots, armor lower part, dress lower part.
- Missing fields are valid. Do not invent upper_clothing or lower_clothing to fill blanks.
- If a stage has no upper_clothing, add missing_upper_clothing to missing_fields.
- If a stage has no lower_clothing, add missing_lower_clothing to missing_fields.
- If a full outfit cannot be split into upper/lower fields, put it in the most appropriate field and add warning full_outfit_unsplit.

Outfit stage rules:
- Create separate stages only for meaningful outfit or clothing changes.
- Do not split stages for action, pose, expression, camera, damage, wetness, stains, lighting, background, or temporary quality noise.
- Stable identity and body fields can repeat across stages.
- Stage frame_indexes must describe where the stage appears according to evidence.

Artist-chain rules:
- Extract artist-chain evidence from tags such as artist:NAME, official art, official style, official_art_style, official art style, official_style, and close official-style variants present in input.
- Treat official art/style terms as artist-chain evidence, not ordinary style tags.
- Do not select or invent artist-chain asset IDs.

Strong filter rules:
- Extract mosaic/censor terms only when they appear in input evidence.
- Examples include mosaic, mosaic censoring, censored, censor, bar censor, censor bar, pixelated censor, censorship, mosaic censorship, mosaic censor, 马赛克, 审查.
- Return these terms in strong_filter_keywords.
- Do not invent related safety terms that were not present or directly normalized from present input.

If request_kind is chunk_extract:
- Return one chunk-local extraction object.
- Include chunk_id from input.

If request_kind is merge_extractions:
- Merge chunk extraction objects into one final script-level extraction.
- Merge roles by exact slot-* source_role_id.
- Merge global roles only when identity/body/clothing evidence clearly refers to the same character.
- Keep global roles separate when evidence conflicts.
- De-duplicate artist-chain terms and strong_filter_keywords.
- Preserve unresolved conflicts in attention_items and unassigned_terms.

Output JSON shape:
{
  "schema_version": 1,
  "status": "ready",
  "chunk_id": "optional chunk id",
  "confidence": 0.0,
  "roles": [
    {
      "source_role_id": "slot-0 or global-0",
      "source_kind": "slot or global",
      "display_name": "short human readable name",
      "confidence": 0.0,
      "frame_indexes": [1, 2],
      "evidence_terms": ["raw evidence terms"],
      "warnings": [],
      "stages": [
        {
          "stage_id": "stable id",
          "label": "short outfit label",
          "confidence": 0.0,
          "frame_indexes": [1, 2],
          "identity": "comma separated raw tags",
          "upper_body": "comma separated raw tags",
          "lower_body": "comma separated raw tags",
          "upper_clothing": "comma separated raw tags",
          "lower_clothing": "comma separated raw tags",
          "evidence_terms": ["raw evidence terms"],
          "missing_fields": [],
          "warnings": []
        }
      ],
      "unassigned_terms": [
        {
          "term": "raw term",
          "frame_indexes": [1],
          "reason": "why not assigned"
        }
      ]
    }
  ],
  "artist_chains": [
    {
      "label": "official art or artist group",
      "terms": ["artist:example", "official art"],
      "frame_indexes": [1],
      "confidence": 0.0,
      "evidence_terms": ["artist:example", "official art"]
    }
  ],
  "strong_filter_keywords": [
    {
      "term": "mosaic censoring",
      "frame_indexes": [12],
      "reason": "mosaic/censor term found in script evidence"
    }
  ],
  "attention_items": [
    {
      "id": "stable id",
      "kind": "low_confidence or ambiguous_global_roles or missing_field or parse_failure",
      "message": "short explanation",
      "source_role_id": "optional role id",
      "frame_indexes": [],
      "blocking": false
    }
  ],
  "unassigned_terms": [
    {
      "term": "raw term",
      "frame_indexes": [1],
      "reason": "why not assigned"
    }
  ]
}
```

---

## Task 1: New Role Extraction Model

**Files:**
- Create: `lib/data/studio/models/script_ai_role_extraction.dart`
- Test: `test/data/studio/models/script_ai_role_extraction_test.dart`

- [ ] **Step 1: Write failing tests**

Create tests for:

- ready extraction parses `global-0`,
- stage preserves empty `upper_clothing`,
- missing fields parse,
- artist-chain official art parses,
- mosaic strong filter keyword parses,
- failure object stores raw response.

Expected assertions:

```dart
expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
expect(extraction.roles.single.sourceRoleId, 'global-0');
expect(extraction.roles.single.stages.single.upperClothing, '');
expect(extraction.roles.single.stages.single.missingFields, contains('missing_upper_clothing'));
expect(extraction.artistChains.single.terms, contains('official art'));
expect(extraction.strongFilterKeywords.single.term, 'mosaic censoring');
expect(extraction.toJson()['roles'], isA<List>());
```

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart
```

Expected: FAIL because model does not exist.

- [ ] **Step 3: Implement model**

Define:

- `ScriptAiRoleExtractionStatus { idle, ready, failed }`
- `ScriptAiRoleExtraction`
- `ScriptAiExtractedRole`
- `ScriptAiExtractedStage`
- `ScriptAiArtistChainEvidence`
- `ScriptAiStrongFilterKeyword`
- `ScriptAiExtractionAttentionItem`
- `ScriptAiUnassignedTerm`

All classes need `fromJson` and `toJson`. Use defensive parsing for missing lists/maps. Keep strings raw; do not translate or normalize display values in the model.

- [ ] **Step 4: Run tests**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart
```

Expected: PASS.

## Task 2: Raw Evidence Builder

**Files:**
- Create: `lib/data/studio/services/script_ai_role_evidence_builder.dart`
- Test: `test/data/studio/services/script_ai_role_evidence_builder_test.dart`

- [ ] **Step 1: Write failing tests**

Cover:

- slotted char captions create `source_kind: "slot"`;
- base prompt tags create `source_kind: "base"`;
- negative prompt tags create `source_kind: "negative"`;
- action/camera tags are preserved in evidence;
- `official art` and `mosaic censoring` are preserved;
- no `asset_catalog`, `characters`, `outfits`, or `vibes` keys exist.

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart
```

Expected: FAIL because builder does not exist.

- [ ] **Step 3: Implement builder**

Create:

```dart
class ScriptAiRoleEvidenceBuilder {
  final int maxFramesPerChunk;
  final int maxFrameIndexesPerTag;
  final int maxSamplesPerTag;

  const ScriptAiRoleEvidenceBuilder({
    this.maxFramesPerChunk = 80,
    this.maxFrameIndexesPerTag = 24,
    this.maxSamplesPerTag = 3,
  });

  List<Map<String, dynamic>> buildChunks({required Script script});
}
```

Each chunk returns:

```json
{
  "schema_version": 1,
  "request_kind": "chunk_extract",
  "chunk_id": "chunk-1",
  "script": {"id": "...", "name": "...", "detected_schema": "...", "frame_count": 400},
  "chunk": {"start_frame_index": 1, "end_frame_index": 80, "frame_count": 80},
  "sources": [
    {
      "source_id": "slot-0",
      "source_kind": "slot",
      "tag_evidence": [
        {"tag": "white shirt", "count": 5, "frame_indexes": [1, 2], "samples": ["raw caption"]}
      ]
    }
  ]
}
```

Use existing prompt tag splitting utilities. Preserve all raw tags; do not pre-filter action/pose/camera.

- [ ] **Step 4: Run tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_evidence_builder_test.dart
```

Expected: PASS.

## Task 3: Parser And Client

**Files:**
- Create: `lib/data/studio/services/script_ai_role_extraction_parser.dart`
- Create: `lib/data/studio/services/script_ai_role_extraction_client.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_parser_test.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_client_test.dart`

- [ ] **Step 1: Add parser tests**

Parser must recover:

- plain JSON object,
- fenced JSON object,
- double-encoded JSON object,
- noisy response with earlier decoy object and later full extraction object.

Invalid response returns `ScriptAiRoleExtraction.failure(...)`.

- [ ] **Step 2: Add client tests**

Client test should assert:

- endpoint joins `/v1/chat/completions`,
- payload uses `response_format: {"type":"json_object"}`,
- system prompt contains `Script AI role extraction engine`,
- system prompt contains `strong_filter_keywords`,
- system prompt contains `official art`,
- system prompt does not contain `asset catalog`.

- [ ] **Step 3: Implement parser and client**

Use the tolerant extraction strategy from the old parser if useful, but create new file and new public names.

Client public names:

- `ScriptAiRoleExtractionClient`
- `ScriptAiRoleExtractionClientRequest`
- `ScriptAiRoleExtractionClientResult`
- `OpenAiCompatibleScriptAiRoleExtractionClient`

- [ ] **Step 4: Run tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_parser_test.dart test/data/studio/services/script_ai_role_extraction_client_test.dart
```

Expected: PASS.

## Task 4: Merger And Service

**Files:**
- Create: `lib/data/studio/services/script_ai_role_extraction_merger.dart`
- Create: `lib/data/studio/services/script_ai_role_extraction_service.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_merger_test.dart`
- Test: `test/data/studio/services/script_ai_role_extraction_service_test.dart`

- [ ] **Step 1: Add merger tests**

Verify:

- same `slot-0` merges across chunks,
- different confident globals stay separate,
- duplicate stage IDs become unique,
- `official art` artist terms de-duplicate,
- `mosaic censoring` strong filter terms de-duplicate,
- attention and unassigned terms are preserved.

- [ ] **Step 2: Implement deterministic merger**

Create:

```dart
class ScriptAiRoleExtractionMerger {
  const ScriptAiRoleExtractionMerger();

  ScriptAiRoleExtraction merge(List<ScriptAiRoleExtraction> extractions);
}
```

Use normalized tag keys for de-duplication.

- [ ] **Step 3: Add service tests**

Verify:

- short script sends one `chunk_extract`,
- long script sends multiple `chunk_extract` requests,
- multiple chunks trigger one `merge_extractions` request,
- failed merge request falls back to deterministic merger,
- client failure returns failed extraction with request preview retained.

- [ ] **Step 4: Implement service**

Create:

- `ScriptAiRoleExtractionServiceRequest`
- `ScriptAiRoleExtractionServiceResult`
- `ScriptAiRoleExtractionService`
- `DefaultScriptAiRoleExtractionService`

The service uses builder, client, parser, and merger. It accepts only AI connection settings and `Script`; it does not accept asset catalog lists.

- [ ] **Step 5: Run tests**

Run:

```powershell
flutter test test/data/studio/services/script_ai_role_extraction_merger_test.dart test/data/studio/services/script_ai_role_extraction_service_test.dart
```

Expected: PASS.

## Task 5: ViewModel Integration And Cache

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Modify: `lib/data/studio/models/script_recast_knowledge.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`
- Test: `test/data/studio/models/script_recast_knowledge_test.dart`

- [ ] **Step 1: Add failing tests**

Cover:

- `generateAiRoleExtraction()` stores draft without mutating preview,
- applying high-confidence slot stage writes five fields,
- empty upper/lower clothing fields are preserved,
- high-confidence `global-0` creates a role assembly,
- low-confidence global role remains draft-only,
- mosaic/censor terms append to strong filter keywords,
- extraction draft persists in `RecastScriptCache`.

- [ ] **Step 2: Implement ViewModel state**

Add:

- `ScriptAiRoleExtractionService? scriptAiRoleExtractionService`
- `bool isExtractingAiRoleEvidence`
- `ScriptAiRoleExtraction aiRoleExtraction`
- `Map<String, dynamic> aiRoleExtractionRequestPreview`
- `Future<void> generateAiRoleExtraction()`
- `Future<void> applyHighConfidenceAiRoleExtraction()`

Keep old field-level Script AI as fallback. Stop using old plan-service state from the visible new action.

- [ ] **Step 3: Implement apply behavior**

Rules:

- threshold: role confidence and stage confidence must be at least `0.75`;
- `slot-*` applies to existing assembly;
- `global-*` creates new assembly when confidence is high;
- empty fields are valid;
- missing fields become warnings, not blockers;
- stage IDs must be unique;
- append `strongFilterKeywords.map((e) => e.term)` to `PromptTagFilterRuleTarget.strongFilterKeywords`.

- [ ] **Step 4: Run tests**

Run:

```powershell
flutter test test/data/studio/models/script_recast_knowledge_test.dart test/ui/studio_script/studio_script_page_test.dart
```

Expected: PASS.

## Task 6: UI And App Wiring

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Add failing UI tests**

Verify:

- button label is `AI 整理角色字段`,
- apply label is `应用高置信字段`,
- panel title is `AI 角色字段草稿`,
- panel shows five fields,
- panel shows artist-chain terms,
- panel shows strong-filter terms,
- panel shows missing-field warnings,
- long labels are bounded with tooltip.

- [ ] **Step 2: Update UI**

Replace old visible AI auto-plan copy with new role-extraction copy. Preserve failed raw response excerpt display.

- [ ] **Step 3: Wire app**

In `lib/main.dart`, import and register:

```dart
scriptAiRoleExtractionService: DefaultScriptAiRoleExtractionService(
  client: OpenAiCompatibleScriptAiRoleExtractionClient(),
),
```

Use existing Script AI base URL, token, model, and proxy providers.

- [ ] **Step 4: Run UI tests and analyzer**

Run:

```powershell
flutter test test/ui/studio_script/studio_script_page_test.dart
dart analyze lib/main.dart lib/ui/studio_script/widgets/studio_script_page.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart
```

Expected: PASS.

## Task 7: Final Verification And Beads Update

**Files:**
- No production edits unless verification reveals a real issue.

- [ ] **Step 1: Run new model/service tests**

Run:

```powershell
flutter test test/data/studio/models/script_ai_role_extraction_test.dart test/data/studio/services/script_ai_role_evidence_builder_test.dart test/data/studio/services/script_ai_role_extraction_parser_test.dart test/data/studio/services/script_ai_role_extraction_client_test.dart test/data/studio/services/script_ai_role_extraction_merger_test.dart test/data/studio/services/script_ai_role_extraction_service_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run cache and page tests**

Run:

```powershell
flutter test test/data/studio/models/script_recast_knowledge_test.dart test/ui/studio_script/studio_script_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run acceptance**

Run:

```powershell
flutter test test/integration/script_recast_acceptance_test.dart
```

Expected: PASS.

- [ ] **Step 4: Analyze touched files**

Run:

```powershell
dart analyze lib/main.dart lib/data/studio/models/script_ai_role_extraction.dart lib/data/studio/models/script_recast_knowledge.dart lib/data/studio/services/script_ai_role_evidence_builder.dart lib/data/studio/services/script_ai_role_extraction_parser.dart lib/data/studio/services/script_ai_role_extraction_client.dart lib/data/studio/services/script_ai_role_extraction_merger.dart lib/data/studio/services/script_ai_role_extraction_service.dart lib/ui/studio_script/view_models/studio_script_viewmodel.dart lib/ui/studio_script/widgets/studio_script_page.dart
```

Expected: PASS.

- [ ] **Step 5: Update Beads**

Run:

```powershell
bd update NAI_NEW-3y1l --notes="Implemented new evidence-first Script AI role extraction workflow. Old asset-matching plan semantics are no longer the active path. New workflow sends raw script tag evidence, infers slot/global roles, fills identity/upper_body/lower_body/upper_clothing/lower_clothing, extracts artist-chain terms including official art/style, and appends mosaic/censor terms to strong filter keywords."
```

Do not close the issue until the user has tried the workflow or explicitly asks to mark it complete.

---

## New Session Prompt

Paste this into a new Codex session:

```text
继续在 `C:\Users\admin\Downloads\NAI_NEW` 项目里做 Script AI 优化。

请先遵守 AGENTS.md：本项目使用 Beads；先运行 `bd prime`，查看/更新 `NAI_NEW-3y1l`。项目处于 stealth mode，不要执行任何 git add/commit/branch/push/reset/checkout 操作。

我要你按 Subagent-Driven Development 执行这个新计划：

`docs/superpowers/plans/2026-06-02-script-ai-role-extraction-rewrite.md`

重要：之前那套 AI RecastPlan / 候选素材库匹配方向已经没用了。不要继续基于“候选角色、候选服装、artist chain ID、vibe、asset_catalog”做方案。要写新的 evidence-first 角色字段提取流程。

核心目标：
- 新建 `script_ai_role_extraction` 模型、builder、parser、client、merger、service。
- 本地只保留和压缩原始 script tag 证据，不提前筛掉动作/镜头/姿势等词，避免漏词。
- 不把候选角色、候选服装、vibe、素材库发给 AI。
- AI 自行根据 slotted caption 和 base/global prompt 证据析出实际有多少角色。
- 有 slot 的角色复用 `slot-*`；没有 slot 但 base prompt 里有角色时，AI 可以创建 `global-0/global-1/...`。
- 每个角色服装阶段输出 Script Recast 当前需要填的五字段：`identity`、`upper_body`、`lower_body`、`upper_clothing`、`lower_clothing`。
- 缺上装、缺下装、只有身体特征等情况是合法结果，保留空字段并输出 `missing_fields` / warning，不要胡编。
- `artist:*`、`official art`、`official style`、`official_art_style` 等官方艺术风格词都算入画师串证据。
- `mosaic`、`mosaic censoring`、`censored`、`censor`、`bar censor`、`pixelated censor`、`马赛克`、`审查` 等马赛克/审查相关词，如果出现在原始证据中，自动加入 strong filter keywords。
- AI 不负责动作、姿势、镜头、表情、背景、vibe，也不负责匹配素材库角色/服装 ID。

执行方式：
1. 使用 `superpowers:subagent-driven-development`。
2. 每个任务派一个 fresh worker subagent。
3. 每个任务完成后做两轮 review：先 spec compliance，再 code quality。
4. 有问题就让 worker 修复，再复核。
5. 不要问我是否继续；除非遇到真正 blocker，否则按计划一直做到 Task 7 验证完成。
6. 最终运行计划里的 focused verification，并更新 Beads notes。

请从读取计划文件开始执行。
```

