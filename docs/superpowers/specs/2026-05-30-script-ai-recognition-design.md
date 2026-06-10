# Script AI Recognition Pipeline Design

## Goal

Add an AI-assisted recognition pipeline to Script Recast that can analyze long scripts without sending the whole script in one request. The pipeline should normalize and deduplicate source prompt material, reuse an application-wide cache, call a configured OpenAI-compatible Script AI only for cache misses, stream suggestions back into the Script page as they arrive, and let the user preview, edit, confirm, reject, or retry each suggestion.

AI output is advisory. It must not directly rewrite final prompts, write to the asset library, or enter long-term knowledge until the user confirms it.

## Current State

Script Recast already has a local role assembly path:

- `ScriptRecastAnalysisService.analyzeRoles` creates role candidates from parsed script frames.
- `LocalHeuristicRoleStageDetector` creates local outfit stages.
- `RoleAssemblyStage.manualParts` can hold editable prompt parts:
  - `identity`
  - `upperBody`
  - `lowerBody`
  - `upperClothing`
  - `lowerClothing`
- Settings already store Script AI and Translation AI base URL/token fields.

The missing piece is the actual AI recognition flow. Current analysis remains local heuristic logic.

## Product Requirements

- Support the full AI scope:
  - role identity
  - protagonist/supporting/temporary importance
  - upper body
  - lower body
  - upper clothing
  - lower clothing
  - outfit or stage label
  - evidence and confidence
  - suggested `CharacterEntry`, `WorkspaceOutfit`, and `ArtistChain` matches when available
- Normalize source prompt text before dedupe so weights do not create false differences.
- Avoid one huge AI call for a long script.
- Prefer cached recognition results before making AI calls.
- Return and fill suggestions incrementally as each request finishes.
- Allow users to preview and confirm suggestions one role at a time.
- Allow users to store or reuse cache suggestions without treating them as confirmed knowledge.
- Reuse confirmed cache entries globally across workspaces.
- Keep rejected or negatively rated cache entries from being auto-applied again.
- Support both slotted scripts and pure prompt scripts.
- Support multi-role batches. If three known source roles are sent in one batch, AI should return three aligned roles.
- Support pure prompt mode where AI decides how many roles are present.

## Non-Goals

- Do not let AI directly edit production payloads.
- Do not let unconfirmed AI output write to the asset library or long-term knowledge.
- Do not build model-list discovery in the first version.
- Do not require AI to translate tags; Translation AI remains separate.
- Do not replace local heuristic detection. Local results remain the fallback/reference layer.

## Settings

Extend Script AI settings to a three-field OpenAI-compatible configuration:

- `scriptAiBaseUrl`
- `scriptAiToken`
- `scriptAiModel`

The default client calls:

```text
POST {scriptAiBaseUrl}/v1/chat/completions
Authorization: Bearer {scriptAiToken}
```

The request body uses `scriptAiModel` as `model` and asks for JSON object output in the prompt. The business logic depends on a `ScriptAiClient` interface. The OpenAI-compatible adapter is one implementation, and tests use a fake client.

## Pipeline Overview

The pipeline has five layers:

1. **Local Candidate Layer**
   - Parse frames through the existing Script Recast parser.
   - Normalize source text by removing weights, cleaning brackets, normalizing whitespace/underscores, and producing stable keys.
   - For scripts with `char_captions`, group by source role slot and outfit/stage evidence.
   - For pure prompt scripts, preserve both raw prompt and normalized prompt and create inline prompt candidates.
   - Build batches and cache keys. This layer does not make final identity decisions.

2. **Global Cache Layer**
   - Look up application-wide AI recognition cache entries before any network request.
   - Cache key for slotted material: normalized role identity plus normalized part/outfit fragment.
   - Cache key for pure prompt material: normalized prompt.
   - If multiple entries match, prefer user-confirmed results, then the newest AI suggestion.
   - Cache hits fill the UI as `缓存建议`, but remain pending confirmation.

3. **AI Request Layer**
   - Send only cache misses to Script AI.
   - Slotted scripts use multi-role batches that preserve roles that appear together in the same scene/frame context.
   - Initial batching limits are four source roles or twelve role-stage fragments per request. If a scene exceeds those limits, split by stage window while keeping the same source-role set together when possible.
   - Pure prompt scripts send raw prompt plus normalized prompt and let AI decide how many roles exist.
   - Every request asks for strict JSON.

4. **Suggestion Layer**
   - Convert AI JSON or cache entries into `ScriptAiSuggestion` records.
   - Suggestions fill role cards and manual prompt fields, but do not apply as final confirmed mappings.
   - Suggestions carry source metadata: `local`, `ai`, `cache`, `needsReview`, or `failed`.

5. **Confirmation Layer**
   - Users confirm by role.
   - Fields remain editable before confirmation.
   - Confirmed suggestions can update current `RoleAssemblyStage.manualParts`, target asset choices, script cache, and long-term knowledge.
   - Rejected suggestions record negative feedback in the global cache.

## Request Units

### Slotted Scripts

Use `ScriptAiRecognitionBatch` as the request unit. A batch can contain multiple source roles:

```json
{
  "candidate_id": "scene-batch-001",
  "source_kind": "slotted",
  "frame_indexes": [1, 2, 3],
  "roles": [
    {
      "source_role_id": "slot-0",
      "display_label": "角色 1",
      "raw_captions": ["alice_(series), torn armor, black thighhighs"],
      "normalized_key": "alice series|armor thighhighs",
      "local_summary": "alice_(series), torn armor, black thighhighs"
    },
    {
      "source_role_id": "slot-1",
      "display_label": "角色 2",
      "raw_captions": ["bob_(series), school uniform, black pants"],
      "normalized_key": "bob series|school uniform black pants",
      "local_summary": "bob_(series), school uniform, black pants"
    }
  ]
}
```

If the batch includes three known source roles, the response must include those three `source_role_id` values. Quantity or ID mismatch marks the batch `needsReview`.

### Pure Prompt Scripts

When no role slots exist, send the raw prompt and normalized prompt:

```json
{
  "candidate_id": "inline-prompt-001",
  "source_kind": "inline_prompt",
  "frame_indexes": [1],
  "raw_prompt": "artist:x, alice_(series), bob_(series), school rooftop...",
  "normalized_prompt": "artist x alice series bob series school rooftop"
}
```

AI decides how many roles exist. Returned roles become `inline-*` suggestions and are confirmed one role at a time.

## AI Response Schema

The first schema version should be strict and small:

```json
{
  "schema_version": 1,
  "items": [
    {
      "candidate_id": "scene-batch-001",
      "roles": [
        {
          "source_role_id": "slot-0",
          "display_name": "alice_(series)",
          "importance": "protagonist",
          "confidence": 0.86,
          "identity": "alice_(series), blue eyes",
          "upper_body": "long hair",
          "lower_body": "black thighhighs",
          "upper_clothing": "torn armor",
          "lower_clothing": "torn skirt, black boots",
          "stage_label": "battle damaged armor",
          "target_character_hint": "alice",
          "target_upper_outfit_hint": "armor",
          "target_lower_outfit_hint": "armor",
          "target_artist_chain_hint": "source unchanged",
          "evidence": ["alice_(series)", "torn armor", "black thighhighs"],
          "warnings": []
        }
      ]
    }
  ]
}
```

Rules:

- `schema_version` must match the current parser.
- Slotted batches must return `source_role_id`.
- Pure prompt roles may omit `source_role_id`; the app assigns stable `inline-*` IDs.
- Unknown enum values become warnings, not crashes.
- Missing optional fields are allowed.
- Missing required alignment fields in slotted mode marks the batch `needsReview`.

## Data Model Additions

Add models under the Script Recast domain:

- `ScriptAiRecognitionBatch`
  - `id`
  - `sourceKind`
  - `frameIndexes`
  - `roles`
  - `rawPrompt`
  - `normalizedPrompt`
  - `normalizedBatchKey`

- `ScriptAiRecognitionRoleInput`
  - `sourceRoleId`
  - `displayLabel`
  - `rawCaptions`
  - `normalizedKey`
  - `roleIdentityKey`
  - `partKey`
  - `localSummary`
  - `evidenceTags`
  - `cacheKey`

- `ScriptAiSuggestion`
  - `id`
  - `batchId`
  - `sourceRoleId`
  - `cacheKey`
  - `source`
  - `status`
  - `confidence`
  - `displayName`
  - `importance`
  - `parts`
  - `stageLabel`
  - `targetCharacterHint`
  - `targetUpperOutfitHint`
  - `targetLowerOutfitHint`
  - `targetArtistChainHint`
  - `evidence`
  - `warnings`
  - `rawResponse`

- `ScriptAiGlobalCacheEntry`
  - `cacheKey`
  - `schemaVersion`
  - `promptSchemaVersion`
  - `model`
  - `sourceKind`
  - `normalizedRoleIdentity`
  - `normalizedPartKey`
  - `suggestion`
  - `status`: `suggested`, `confirmed`, `rejected`
  - `negativeFeedbackCount`
  - `createdAt`
  - `updatedAt`
  - `confirmedAt`
  - `rejectedAt`

The current script cache should also store in-progress AI queue state, failed batches, review batches, and confirmed/rejected suggestion IDs so the user can resume.

Application-global cache entries must not store workspace-specific asset IDs as reusable facts. They may store textual hints such as normalized character names, outfit names, artist names, and prompt parts. When a cache entry fills a workspace, asset ID matching is resolved against the current workspace asset library at that time.

## Cache Policy

Cache scope is application-wide.

Selection order for matching cache entries:

1. Confirmed result.
2. Newest suggested result.
3. Rejected results are ignored for auto-fill.

Cache hit behavior:

- Fill role cards as `缓存建议`.
- Keep status pending.
- Do not write long-term knowledge until user confirmation.

Rejection behavior:

- Mark the cache entry `rejected`.
- Increase `negativeFeedbackCount`.
- Suppress auto-fill for rejected entries and for entries with `negativeFeedbackCount >= 1`.

## UI Design

Add an AI suggestion layer to the existing Script page role mapping area.

Top-level actions:

- `AI 分析剧本`
- `继续未完成分析`
- `只使用缓存建议`
- `重试失败项`

Each role card should show:

- source: `本地规则`, `AI 建议`, `缓存建议`, `需人工审查`, or `AI 失败`
- confidence
- frame indexes and evidence tags
- role fields:
  - `角色身份`
  - `上身`
  - `下身`
  - `上装`
  - `下装`
- target asset hints
- controls:
  - `确认此角色`
  - `拒绝建议`
  - `重试 AI`
  - editable field inputs

Multi-role slotted batches:

- Normal responses fill each matching role card by `source_role_id`.
- Quantity or ID mismatch displays a `需人工审查` panel with request roles and raw AI roles.
- The panel can retry the batch or let the user manually assign returned roles.

Pure prompt responses:

- Render under `Inline Prompt 分析结果`.
- Show one card per AI-returned role.
- Confirm role by role.
- Confirmed inline roles generate stable `inline-*` mappings used by preview and payload assembly.

## Error Handling

- Missing base URL/token/model: show configuration error before queue start.
- 401/403: stop new network calls and show credential error.
- 429: mark batch failed with retry option.
- Timeout/network failure: mark batch failed; keep cached/local suggestions visible.
- JSON parse failure: mark batch `failed`, store raw response.
- Slotted response count or ID mismatch: mark batch `needsReview`, store raw response.
- Partial JSON with useful fields: preserve fields and add warnings.

Local heuristic output remains visible as reference, but never impersonates AI output.

## Testing Strategy

Unit tests:

- normalization removes weights and creates stable cache keys
- slotted multi-role batches preserve source role IDs
- pure prompt candidates use normalized prompt cache keys
- cache selection prefers confirmed entries, then newest suggested entry
- rejected cache entries do not auto-fill
- OpenAI-compatible client parses valid JSON
- invalid JSON creates failed batch state
- slotted ID mismatch creates `needsReview`

ViewModel tests:

- `AI 分析剧本` fills cache hits without network calls
- cache suggestions remain pending
- cache misses are queued and filled incrementally
- failed batch can retry independently
- confirming a role writes manual parts into the current mapping
- rejecting a suggestion records negative feedback
- pure prompt mode creates multiple inline role cards

Widget tests:

- role cards display AI/cache/failed/review states
- multi-role review panel shows raw AI output and source roles
- inline prompt analysis results can be confirmed by role

Integration tests:

- fake `ScriptAiClient` processes a long script in multiple batches
- mixed cache hits and AI misses fill UI in deterministic order
- app-global cache persists and is reused across workspaces

## Acceptance Criteria

- A long slotted script can be analyzed without a single whole-script AI request.
- Multi-role batches send and receive multiple roles aligned by `source_role_id`.
- Pure prompt scripts can be sent to AI as prompt text and return multiple roles.
- Cache hits fill as `缓存建议` and remain pending confirmation.
- Confirmed cache entries are preferred over newer unconfirmed suggestions.
- Rejected cache entries are not auto-applied.
- AI failures do not block already completed or cached suggestions.
- Users can preview, edit, confirm, reject, and retry suggestions role by role.
- No unconfirmed AI output enters long-term knowledge or the asset library.
