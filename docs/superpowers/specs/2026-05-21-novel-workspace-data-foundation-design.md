# Novel Workspace Data Foundation Design

## Goal

Merge the current Flutter CasRand project, KAMIA Prompt Studio, and Artist Chain Studio into one Novel Studio data foundation. The first milestone is a visible, versioned workspace directory that can import and validate data from all three sources while keeping the existing Flutter generation flow usable.

## Decisions

- Use the current Flutter project as the host application.
- Use a visible workspace directory as the source of truth for long-lived data.
- Keep Hive only for local app state such as recent workspace path, window/UI preferences, and transient runtime state.
- Store secrets outside the visible workspace by default. The workspace may store `secretRef` values, but not API tokens, proxy credentials, AI keys, or private prompt blocks.
- Preserve the existing CasRand `PromptConfig` cascade model instead of forcing it into KAMIA recipes.
- Preserve KAMIA's 8-block prompt model and 8-view character/outfit variants as first-class schema concepts.
- Store image references as file paths under `assets/` instead of embedding base64 in JSON.

## Workspace Layout

```text
novel_workspace/
  studio_manifest.json
  library/
    recipes/
      style.json
      sub_style.json
      character.json
      clothing.json
      action.json
      expression.json
      scene.json
      camera.json
    tags/
      style.json
      sub_style.json
      character.json
      clothing.json
      action.json
      expression.json
      scene.json
      camera.json
    characters.json
    artist_chains.json
    inspirations.json
    loras.json
  configs/
    prompt_configs/
    generation_profiles/
    prompt_replace_rules.json
    filter_rules.json
  production/
    batch_plans/
    assembly_presets/
    workflows/
  assets/
    images/
    thumbnails/
    references/
  imports/
    kamia/
    casrand/
    artist_studio/
  output/
    nai/
    comfyui/
```

`studio_manifest.json` is the workspace entry point. It records schema version, workspace name, migration history, the current prompt config ID, and index metadata needed to open the workspace quickly.

`library/` contains reusable creative assets and knowledge. `configs/` contains generation configuration and text-processing rules. `production/` contains assembly presets, batch plans, and workflow templates. `assets/` contains reusable image files and thumbnails. `imports/` keeps original import snapshots for rollback and later remigration. `output/` stores generated files and should be safe to ignore from backups or Git.

## Core Entities

### Recipe

Represents a KAMIA-style prompt recipe.

Fields:

- `id`
- `name`
- `block`
- `category`
- `group`
- `tags`
- `variants`
- `imageRefs`
- `source`
- `note`

Valid blocks follow KAMIA order:

```text
style -> sub_style -> character -> clothing -> action -> expression -> scene -> camera
```

`variants` stores perspective and composition variants for recipes that need them, especially clothing.

### TagEntry

Represents a dictionary entry for a danbooru tag or prompt fragment.

Fields:

- `id`
- `tag`
- `zh`
- `block`
- `category`
- `aliases`
- `imageRefs`
- `source`
- `note`

### Character

Represents a reusable character plus outfits.

Fields:

- `id`
- `name`
- `traits`
- `outfits`
- `defaultOutfitId`
- `imageRefs`
- `source`
- `note`

`traits` and outfit tags use 8-view text variants:

```text
front_full
front_cowboy
front_upper
front_lower
back_full
back_cowboy
back_upper
back_lower
```

`front_full` is the baseline. Missing variants fall back in this order:

```text
back_X -> back_full -> front_X -> front_full
```

### ArtistChain

Represents Artist Chain Studio's artist/style prompt assets.

Fields:

- `id`
- `name`
- `tags`
- `prompt`
- `styleTags`
- `imageRefs`
- `translations`
- `source`
- `note`

Artist Chain Studio `artists` import into this entity. Artist Chain Studio `characters` import into `Character`.

### PromptConfig

Represents a CasRand cascade prompt configuration.

Fields:

- `id`
- `name`
- `rootConfig`
- `savedBlocks`
- `replaceRuleIds`
- `generationProfileId`

`rootConfig` preserves the existing CasRand `PromptConfig` tree semantics: selection method, probability, count, shuffle behavior, random bracket bounds, string leaves, nested config leaves, variable replacement, and sequential state reset behavior.

### GenerationProfile

Represents a reusable NAI generation parameter profile.

Fields:

- `id`
- `name`
- `params`
- `negativePrompt`
- `vibeRefs`
- `preciseReferenceRefs`
- `batchDefaults`

This is the workspace-level equivalent of the current `ParamConfig`, global generation params, Vibe settings, Precise Reference settings, and batch defaults.

### BatchPlan

Represents a saved production queue.

Fields:

- `id`
- `name`
- `items`
- `statusSnapshot`
- `createdAt`
- `updatedAt`

KAMIA NAI queue data imports here. Runtime-only progress can be stored in `statusSnapshot`, but the app should tolerate stale or missing status.

## Architecture

### WorkspaceService

`WorkspaceService` is the only component that reads or writes workspace files directly.

Responsibilities:

- Open an existing workspace.
- Create a new workspace with the expected directory layout.
- Read and write JSON files with schema version checks.
- Resolve asset references.
- Persist the active workspace path into local app state.
- Expose repository-style accessors for recipes, tags, characters, artist chains, prompt configs, profiles, and batch plans.

Flutter screens should depend on workspace repositories or view models, not raw file paths.

### Legacy Adapters

Existing CasRand models stay alive during the first migration phase.

Adapters:

- `CasRandImporter`: exported CasRand config JSON or current Hive data to workspace `PromptConfig` and `GenerationProfile`.
- `CasRandExporter`: workspace `PromptConfig` and `GenerationProfile` back into existing `PayloadConfig` when the current generation page needs to run.
- `KamiaImporter`: KAMIA `data/` to recipes, tags, characters, LoRA metadata, assembly presets, workflows, and batch plans.
- `ArtistStudioImporter`: Artist Chain Studio data directory to artist chains, characters, translation cache, and filter rules.

### Validation

`WorkspaceValidator` runs after import and before important writes.

Validation rules:

- JSON files parse successfully.
- Schema version is supported.
- IDs are unique within each entity type.
- Blocks are one of the 8 valid block names.
- Entity references resolve.
- Image references point to existing files or are marked missing without crashing the app.
- Character and outfit variants have at least `front_full`.
- Prompt configs preserve required cascade fields.
- Generation profiles do not contain raw secrets.
- Private blocks and token-like values are not written into public workspace JSON.

### Secrets

Secrets are local app data, not workspace data.

Examples:

- NovelAI API token
- HTTP proxy credentials
- AI translation API key
- private prompt block contents

Workspace files may store stable references such as:

```json
{ "secretRef": "default_nai_token" }
```

The app resolves `secretRef` through local storage. A later encrypted export feature can package secrets explicitly, but that is not part of the first milestone.

## Data Flow

### New Workspace

1. User creates or selects a workspace directory.
2. `WorkspaceService` creates the directory layout.
3. `studio_manifest.json` is written with the current schema version.
4. Default empty JSON arrays or objects are created for required files.
5. The selected workspace path is stored locally.

### Import

1. User chooses one of the three source types.
2. The matching importer copies a source snapshot into `imports/`.
3. The importer maps source objects into workspace entities.
4. Assets are copied into `assets/` and referenced by relative paths.
5. The validator runs and reports warnings/errors.
6. Valid objects are committed to workspace JSON files.
7. The manifest records source path, import time, importer version, and counts.

### Generate

1. User selects a workspace `PromptConfig` and `GenerationProfile`.
2. `CasRandExporter` converts them to current `PayloadConfig` shape.
3. Existing Dart payload generation builds the NAI request.
4. Outputs are saved under `output/nai/` and optional reusable thumbnails are copied into `assets/thumbnails/`.

## Error Handling

- If a workspace file is missing, recreate empty defaults when safe and report a warning.
- If a workspace file is malformed, do not overwrite it automatically. Move the bad file aside only after explicit user approval.
- If an import produces duplicate IDs, generate new IDs and keep source IDs in `source`.
- If images are missing, keep the entity and mark the image reference missing.
- If a secret is found in public workspace JSON, block the write and show a clear validation error.
- If a schema version is newer than the app supports, open the workspace read-only.

## First Milestone Scope

In scope:

- Workspace directory creation/opening.
- `WorkspaceService` read/write foundation.
- Core entity models.
- CasRand/KAMIA/Artist Studio importers.
- Validation and import summary.
- A read-only workspace browser or data health page in Flutter.
- Conversion from workspace prompt config/profile into current generation flow.

Out of scope for the first milestone:

- Full UI rewrite of KAMIA panels.
- Full UI rewrite of Artist Chain Studio panels.
- ComfyUI production execution.
- Encrypted workspace export.
- Multi-user sync.
- Database storage.

## Testing

- Unit tests for each entity JSON round trip.
- Unit tests for schema validation failures and warnings.
- Unit tests for KAMIA recipe/tag/character import mapping.
- Unit tests for Artist Studio artist/character/filter-rule import mapping.
- Unit tests for CasRand config import/export preserving prompt tree semantics.
- Widget test for workspace browser counts and validation status.
- Integration-style test using small fixture workspaces for create, import, validate, reopen.

## Rollout Plan

1. Add workspace models and JSON fixtures.
2. Add `WorkspaceService` and validator.
3. Add importer fixtures and import summaries.
4. Add a Flutter data health page.
5. Bridge workspace prompt config/profile to existing generation flow.
6. Use the bridge to migrate one real config and verify generated payload parity with the legacy path.

## Open Implementation Notes

- The current working directory is not a git repository, so this spec cannot be committed from here.
- The first implementation plan should avoid moving existing generation logic until workspace import/export parity is covered by tests.
- Existing exported CasRand configs must remain importable after the workspace migration.
