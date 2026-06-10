# Script Recast Role Assembly Design

## Goal

Turn Script Recast role mapping from a slot-to-character dropdown into a card-based role assembly editor. The editor must support automatically detected outfit stages, manual prompt editing for body and clothing parts, future AI stage recognition, and separate AI settings for script analysis and translation.

## Product Requirements

- Replace user-facing `slot-0` / `slot-1` labels with `角色 1` / `角色 2`.
- Render each role mapping as a clear card, following the Workbench character-card style rather than the current compact form rows.
- Keep artist-chain mapping as a separate card or section; it must not be visually mixed into role cards.
- For each role, show detected outfit stages as `服装 1`, `服装 2`, `服装 3` chips or tabs on the role card.
- Each role/outfit stage exposes editable prompt fields:
  - `角色身份`
  - `上身`
  - `下身`
  - `上装`
  - `下装`
- Choosing a target `CharacterEntry` fills identity/body fields from the character.
- Choosing a target `WorkspaceOutfit` fills upper/lower clothing fields from the outfit.
- Users can manually edit any filled field after mapping; the final payload uses edited field text.
- Mapping can assemble multiple components, such as target character identity plus one outfit's upper clothing plus another outfit's lower clothing plus manual edits.
- Same-script same-role multiple outfits are detected automatically first; the UI presents the result for confirmation and edits.
- Future AI recognition should plug into the detector layer without changing the UI or final Recast payload model.
- Settings must contain separate AI credentials:
  - `剧本 AI`: base URL and token for script role/outfit analysis.
  - `翻译 AI`: base URL and token for translation features.

## Current Gaps

`RoleSwap` currently stores only `sourceRoleId`, `targetCharacterId`, and `targetOutfitId`. `ScriptRecastEngine` uses those fields to build one char caption for the whole source role slot. This cannot represent per-stage clothing, manual body/clothing edits, mixed outfit parts, or multiple outfit stages for the same script role.

The Script page currently displays role mapping rows with source IDs such as `slot-0`, and the artist chain appears beside the role mapping in a way that visually competes with it.

## Proposed Data Model

Add role assembly types under `lib/data/studio/models/script_recast.dart`:

- `RecastPromptParts`
  - `identity`
  - `upperBody`
  - `lowerBody`
  - `upperClothing`
  - `lowerClothing`
- `RolePartSource`
  - `characterId`
  - `outfitId`
  - `part`
- `RoleAssemblyStage`
  - `id`
  - `label`
  - `frameIndexes`
  - `sourceSummary`
  - `targetCharacterId`
  - `targetUpperOutfitId`
  - `targetLowerOutfitId`
  - `manualParts`
- `RoleAssembly`
  - `sourceRoleId`
  - `displayLabel`
  - `sourceName`
  - `stages`

Extend `RecastMapping` with `roleAssemblies`. Existing `roleSwaps` remains readable for backward compatibility, and the engine should prefer `roleAssemblies` when present.

## Stage Detection

Introduce a detector boundary:

- `RecastRoleStageDetector` interface returns role assemblies from a parsed `Script`.
- `LocalHeuristicRoleStageDetector` is the first implementation. It groups captions per role and clusters clothing/body prompt parts into stages by normalized clothing signature.
- A future `AiRoleStageDetector` can call configured `剧本 AI` and return the same role assembly structure.

The local detector should produce stable labels (`服装 1`, `服装 2`, `服装 3`) and frame index lists. It should not write to long-term knowledge automatically.

## Recast Engine Behavior

For each parsed frame and role:

1. Pick the stage whose `frameIndexes` contains the frame index. If none matches, use the first stage.
2. Resolve prompt parts from the selected target character and target outfit IDs.
3. Overlay manual edits from `manualParts`.
4. Join non-empty parts in this order: `identity`, `upperBody`, `lowerBody`, `upperClothing`, `lowerClothing`, preserved source action/expression tail.
5. Deduplicate tags using the existing prompt tag normalization.

Manual edits are final. Selecting a new character or outfit may fill empty fields, but should not overwrite manually changed fields unless the user explicitly refreshes from the selected asset.

## UI Design

Role mapping becomes a vertical list of cards:

- Card header: `角色 1`, detected/custom source name, target character summary, and stage chips.
- Stage chips: `服装 1`, `服装 2`, `服装 3`, each showing frame ranges such as `1-18`.
- Card body for selected stage:
  - target character picker
  - upper outfit picker
  - lower outfit picker
  - editable fields for identity/body/clothing prompt parts
  - short source evidence preview
- Dragging a character asset onto the card fills character fields.
- Dragging an outfit asset onto a stage fills both upper and lower clothing by default.
- Later UI can add per-part drag targets, but V1 can use picker controls and editable fields.

Artist mapping remains a separate panel below or beside the role cards, titled `画师串`.

## Settings Design

Extend `Settings` with:

- `scriptAiBaseUrl`
- `scriptAiToken`
- `translationAiBaseUrl`
- `translationAiToken`

Settings page renders these in a dedicated AI section with two cards: `剧本 AI` and `翻译 AI`. Tokens should be editable but not shown elsewhere.

## Testing Strategy

- Model tests verify `RecastPromptParts`, `RoleAssemblyStage`, `RoleAssembly`, and `RecastMapping.roleAssemblies` round trip.
- Detector tests verify one role with multiple clothing signatures becomes multiple stages with stable labels and frame indexes.
- Engine tests verify role assembly output uses selected/manual parts and preserves action/expression tail.
- UI ViewModel tests verify role cards expose user labels, no `slot-0` text, outfit stage labels, and field edits refresh preview payloads.
- Settings tests verify script AI and translation AI credentials round trip and render in the Settings page.

## Non-Goals

- Full AI provider implementation is not required in this pass.
- Automatic long-term knowledge writes are not included.
- Per-word visual diff editing is not included.
