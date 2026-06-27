# Script Recast Complete AI Term Contract Design

## Purpose

Script Recast role extraction must stop depending on local semantic filters to decide which source prompt terms are replacement-relevant. The project AI and Codex offline repair workflows should share one contract: local code prepares complete, deduplicated source evidence with cache context; AI decides role terms, scene terms, excluded terms, classifications, and translation suggestions.

This design covers the formal project AI path and the Codex offline script-processing path. It does not authorize any API-backed cache rebuild during Codex offline work.

## Problem

The current cache repair and normalization path can derive replacement terms from local regular expressions. That makes the replacement table depend on a fixed local whitelist. Terms such as hair buns, wings, gyaru, or demon girl can be missed when the local list is incomplete, even when the original frame prompt contains them.

The existing project AI prompt already states the intended architecture: do not hard-filter role-scoped source prompt tags; use `roles[].prompt_terms` for role replacement terms; use top-level `scene_terms` for scene replacement terms; use `other` for role-scoped terms that do not fit the five stage fields. The implementation needs to make that contract durable and remove older fallback behavior.

## Goals

- Send complete positive source prompt evidence to AI, including slot captions, base captions, and base-only/global prompts.
- Preserve source attribution for every term: source id, source kind, frame indexes, original source phrase, polarity, and cache hits.
- Let AI decide whether a term belongs in a role replacement area, scene replacement area, cache suggestion, or no replacement area.
- Keep scene terms as a first-class replacement area through `scene_terms`.
- Let AI provide missing translation and classification suggestions while reusing existing cache entries.
- Merge new AI/Codex results with existing user-confirmed mappings so users do not remap scripts after cache rebuilds.
- Update Codex offline script handling to use the same contract without calling user API credentials.

## Non-Goals

- Do not use local semantic rules as a substitute for AI role/scene judgment.
- Do not clear existing role or scene replacement mappings during rebuild.
- Do not overwrite manual or user-confirmed translation/classification cache entries without an explicit user action.
- Do not call project-configured API, NAI token, proxy, or OpenAI-compatible endpoint from Codex offline repair.
- Do not redesign the whole Script Recast UI; this work only changes the data contract and write/merge paths needed by replacement areas.

## Data Flow

1. Local code reads source frames.
2. Local code splits prompt text into minimal prompt terms, deduplicates by normalized key, and records all sources.
3. Local code checks translation and classification caches for each term.
4. Local code sends the complete evidence set to AI, including cached values and missing-cache flags.
5. AI returns:
   - role records with `prompt_terms`
   - top-level `scene_terms`
   - optional excluded/audit terms
   - missing translation suggestions
   - missing classification suggestions
6. Local code validates that output terms exist in the source evidence or are exact normalized variants.
7. Local code merges the new structure with existing mapping and cache data.
8. UI reads role replacement terms from `mapping.rolePromptReplacements` and scene replacement terms from the existing scene replacement path backed by `scene_terms`.

## Input Contract

The AI request must include a complete term evidence table. Terms must not be omitted because they look like action, pose, scene, camera, quality, clothing action, body state, or style terms.

Each source term entry should carry:

```json
{
  "text": "holding skirt",
  "normalized": "holding skirt",
  "source_id": "slot-0",
  "source_kind": "slot",
  "polarity": "positive",
  "frame_indexes": [1, 2],
  "source_phrase": "girl, holding skirt, white shirt",
  "cached_translation": "",
  "cached_category": "",
  "needs_translation": true,
  "needs_category": true
}
```

`source_kind` must distinguish at least:

- `slot`
- `base`
- `negative`

Negative terms can be included for context and safety/filter extraction, but role and scene replacement candidates come from positive sources unless the AI output field explicitly handles negative content.

Base/global prompts are not treated as scene-only evidence. If a base caption contains role identity, body, outfit, or character-state terms, AI can create a `global-*` or `base` appearance role. If the same character also appears in slots, AI can merge them using appearances.

## Output Contract

The existing `ScriptAiRoleExtraction` structure remains the main output. It should be extended or consistently populated with:

- `roles[].prompt_terms`: role replacement source terms.
- `scene_terms`: scene replacement source terms.
- `term_cache_suggestions`: translation/classification suggestions for missing cache entries.
- `excluded_terms` or `attention_items`: optional audit information for terms AI intentionally did not put in replacement areas.

Allowed role prompt term categories:

- `character`
- `upperBody`
- `lowerBody`
- `upperClothing`
- `lowerClothing`
- `accessory`
- `clothingState`
- `other`

Allowed scene term category:

- `scene`

AI should use `other` only for role-scoped replacement terms that do not fit the literal category contract below. Pure action, pose, expression, camera, quality, and background terms should be excluded or audited instead of being forced into `other`.

## Role Prompt Term Category Contract

The replacement area should be readable when many terms are present. Categories must therefore be semantic and UI-facing, not only coarse storage aliases.

AI must classify every role `prompt_terms` entry using these literal meanings:

- `character`: role identity and persona tags, including named characters, species/persona identity such as demon girl, devil girl, succubus, gyaru, kogal, schoolgirl, idol, nurse, and other identity-like role descriptors.
- `upperBody`: head, hair, face, eyes, ears, horns, halo, wings attached to the upper body, torso, chest, breasts, nipples, areola, shoulders, arms, upper-body skin marks, and stable upper-body anatomy or appearance traits. Examples: hair bun, double bun, twintails, horns, wings, large breasts, small breasts, inverted nipples, flat chest, cleavage.
- `lowerBody`: waist, hips, tail, legs, thighs, knees, feet, toes, lower-body skin marks, and stable lower-body anatomy or appearance traits. Examples: demon tail, thick thighs, bare legs, animal tail.
- `upperClothing`: worn upper garments and garment-like covers. Examples: shirt, jacket, bikini top, bra, dress bodice, towel covering upper body.
- `lowerClothing`: worn lower garments and footwear. Examples: skirt, shorts, pants, panties, stockings, socks, boots, shoes.
- `accessory`: detachable or decorative items that are not the garment itself. Examples: collar, choker, necklace, earrings, hair ornament, hairclip, headband, crown, bracelet, anklet, glasses.
- `clothingState`: clothing manipulation, exposure state, absence state, and garment-position states that the user may replace or delete independently. This includes both action-like clothing changes and static exposure states. Examples: pulling down panties, pulling aside bikini, shirt lift, dress tug, strap slip, open clothes, taking off top, partially undressed, no panties, topless, bottomless, completely nude, nude.
- `other`: rare role-scoped replacement terms that are neither identity/body/clothing/accessory/state nor scene.

Important boundaries:

- Body traits such as `inverted nipples`, `large breasts`, `small breasts`, `covered nipples`, and `cleavage` are `upperBody`, not `clothingState`.
- `no panties`, `topless`, `bottomless`, `completely nude`, and `nude` are `clothingState`, even though they are not active motions.
- Clothing manipulation terms such as `pulling down panties`, `shirt lift`, `strap slip`, and `taking off top` are `clothingState`, not pure `action`.
- Pure pose/action/expression terms such as standing, sitting, looking at viewer, smile, blush, kneeling, grabbing, holding, camera angles, and background/location terms should not enter role replacement terms unless they directly describe a replacement-relevant clothing/body exposure state.
- Terms can be present in `prompt_terms` without being placed into the five stage fields. Stage fields remain compatibility summaries; `prompt_terms` are the fine-grained replacement table.

## UI Grouping Contract

The role replacement UI should group terms in this order:

1. 角色身份: `character`
2. 上身: `upperBody`
3. 下身: `lowerBody`
4. 上装: `upperClothing`
5. 下装: `lowerClothing`
6. 饰品: `accessory`
7. 服装状态/动作: `clothingState`
8. 其它角色词: `other`

Scene replacement terms stay in the separate scene replacement area and are grouped separately from role replacement terms.

The old mixed group label `服装状态/饰品` must be split. Accessories such as `animal collar` and state/action terms such as `no panties` or `strap slip` must not be shown in the same category solely because they share a legacy storage value.

## Compatibility Rules

Existing caches and older AI outputs can contain category strings from earlier contracts. They must be parsed as follows:

- `identity` -> `character`
- `body` -> `upperBody`
- `clothing_state` or `clothingState` -> `clothingState`
- `accessory` -> `accessory`
- `clothing` -> `upperClothing` only when migration context proves the term is a worn upper garment; otherwise keep it as a legacy-compatible value until AI/Codex reclassifies it.

Manual or user-confirmed mappings must be preserved during migration. If an existing replacement rule matches a newly classified term by normalized text but category changes from a legacy alias to a more precise category, keep the target prompt/action/match mode and refresh only source term metadata.

## Replacement Areas

### Role Replacement Area

Role replacement area is built from `roles[].prompt_terms`, then merged into `mapping.rolePromptReplacements`.

Merge behavior:

- New AI/Codex processing result is the latest structural baseline.
- Existing user-confirmed mappings and replacement rules are preserved.
- Existing `targetCharacterId`, `targetIdentityPrompt`, user-edited target prompt parts, rule actions, match modes, and manually added terms are retained when their source role/rule can be matched.
- Existing rule is reused when a new source term matches an existing rule by normalized term and category.
- New source terms become new rules.
- Existing rules not present in the new AI output are kept as user data, but can be marked stale in an audit report when source evidence no longer contains the term.

This preserves user work so reopening a rebuilt script does not require remapping.

### Scene Replacement Area

Scene replacement area is built from top-level `scene_terms`.

Scene terms must support the same cache and merge principles:

- New scene terms are appended or refreshed from AI/Codex output.
- Existing scene replacement mappings, user targets, manual rules, and selections are preserved.
- A scene term is not discarded just because it is not role-scoped.

If the current model or mapping layer lacks a durable scene replacement mapping equivalent to `rolePromptReplacements`, add one instead of forcing scene terms into role replacement structures.

## Translation And Classification Cache Policy

Local code may look up translation and classification caches before calling AI, but cache hits must not remove source terms from AI input.

Cache behavior:

- Existing cached translation/classification is sent as context.
- Missing entries are marked `needs_translation` or `needs_category`.
- AI/Codex only needs to suggest missing entries.
- New AI/Codex result has priority as the latest machine suggestion, but manual/user-confirmed entries are preserved.
- Machine entries can be refreshed when the new result has a stronger source or newer contract version, with old value and source recorded in the audit report.
- Writes must be additive by default and must not erase unrelated cache entries.

Recommended source labels:

- `manual`
- `ai_extraction`
- `codex_offline_repair`
- `local_rules`

`manual` entries win unless the user explicitly requests replacement.

## Codex Offline Script Handling

When asked to process scripts directly, Codex should:

1. Read local source prompts and existing active cache.
2. Build the same complete term evidence table used by project AI.
3. Read existing translation and classification caches.
4. Use Codex reasoning, not project API credentials, to produce:
   - role prompt terms
   - scene terms
   - translation suggestions for missing entries
   - classification suggestions for missing entries
   - audit rows for excluded or uncertain terms
5. Merge with existing role and scene replacement mappings.
6. Back up edited cache files.
7. Write an audit report with counts, changed files, preserved mappings, added terms, and stale retained rules.

Codex offline processing must not invoke project-configured API endpoints, NAI token, proxy, or stored credentials.

## Deprecated Behavior

The following behavior should be removed or made audit-only:

- Local prompt term whitelist deciding which role source terms enter `prompt_terms`.
- Local scene/action filters deciding which role-scoped source terms are dropped before AI.
- Offline scripts that create replacement terms solely from fixed regex lists.
- Cache normalizers that synthesize new replacement tables without preserving user mappings.

Local rules may still be used for presentation hints, lint warnings, cache lookup keys, or audit reports. They must not be the source of truth for role/scene replacement membership.

## Validation

Regression fixtures must cover:

- Role terms inside `char_captions`.
- Role terms mixed into `base_caption`.
- Base-only frames with no character slots.
- Scene terms that must enter `scene_terms`.
- Clothing-related actions and exposure states that AI may keep as `clothingState` or exclude.
- Pure action terms that AI can exclude.
- Terms with existing translation/classification cache hits.
- Terms missing translation/classification cache entries.
- Existing role replacement mappings with selected target characters.
- Existing scene replacement mappings with selected targets.

Named regression terms:

- hair bun
- double bun
- twintails
- wings
- inverted nipples
- large breasts
- small breasts
- gyaru
- kogal
- demon girl
- devil girl
- clothingState examples such as shirt lift, panties aside, clothes pull, strap slip, no panties, completely nude
- pure action examples such as looking, standing, grabbing, holding

## Acceptance Criteria

- AI request preview includes complete positive source terms from slot and base sources.
- No local semantic filter can remove source terms before AI sees them.
- Role replacement area is sourced from `roles[].prompt_terms`.
- Scene replacement area is sourced from `scene_terms`.
- Translation/classification cache hits are passed as context; misses are requested as suggestions.
- Existing user mappings survive rebuild and are merged with new AI/Codex output.
- Role replacement UI groups are split into character, upperBody, lowerBody, upperClothing, lowerClothing, accessory, clothingState, and other.
- `inverted nipples` and `large breasts` are classified as `upperBody`; `no panties`, `strap slip`, and `completely nude` are classified as `clothingState`.
- Codex offline repair follows the same schema and does not use user/project API credentials.
