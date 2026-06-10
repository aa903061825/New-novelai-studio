# Structured Asset Capture And Asset Preview Generation Design

Date: 2026-06-04
Beads issue: `NAI_NEW-231z`

## Goal

Let the user save useful structured artist chains, characters, and outfits into
the asset library from wherever those structured objects appear, while keeping
preview-image generation inside the asset library.

The user-facing split is:

- `保存为素材`: a cross-page capture action for structured objects.
- `生成预览图`: an asset-library action for already saved assets.

These two actions must not collapse into one page-level feature. Saving a
material from inside the asset library itself is not the primary use case; the
main value is capturing good material while browsing or editing scripts,
gallery metadata, workbench results, or other structured surfaces.

## Current State

The project already has the core storage and generation pieces:

- `CharacterEntry` stores reusable characters.
- `WorkspaceOutfit` stores reusable outfits under characters.
- `ArtistChain` stores artist-chain prompts, structured artist entries,
  style tags, negatives, Vibe defaults, image references, translations, source,
  and notes.
- `WorkspaceService` can load and save characters and artist chains.
- `StudioAssetCatalogService` reads the real asset catalog and resolves
  `imageRefs` into preview paths.
- `AssetLibraryPage` already shows asset previews from `imageRefs`, sends
  assets to the workbench/script, favorites assets, and supports artist-chain
  Vibe binding.
- `ProductionNaiAdapterService` and `ProductionExecutorService` can request and
  save NAI images.
- `ProductionTask.manualSingleFrame` exists for non-script single-frame work.

The missing product surface is a shared, structured save flow and a reusable
asset-preview generation service.

## Scope

### In Scope

- Add a shared structured `保存为素材` action for pages that already know an
  object is a character, outfit, artist chain, or matching candidate.
- Add a thin confirmation bar before saving, allowing quick edits to name,
  target type, and note.
- Save captured data into the existing workspace models:
  - artist chains into `ArtistChain`,
  - characters into `CharacterEntry`,
  - outfits into `WorkspaceOutfit` under a target `CharacterEntry`.
- Use duplicate detection and merge by default instead of creating repeated
  assets.
- Preserve existing user-authored asset data during merge.
- Add asset-library preview generation for artist chains and characters.
- Immediately run one NAI request from the asset library when preview generation
  is clicked.
- Use model `nai-diffusion-4-5-full` for generated asset previews.
- Randomly choose one size from `832x1216`, `1024x1024`, and `1216x832`.
- Write successful preview image paths back into the target asset `imageRefs`.
- Refresh the asset card/detail preview after a successful generation.

### Out Of Scope

- Saving from unstructured raw prompt text.
- Creating a parallel character or artist-chain schema.
- Replacing the existing Prompt tag system. Any remaining raw prompt display
  should be treated as a tagging/structure coverage gap, not as a separate save
  path.
- Full asset editor forms.
- Batch generation for all missing previews.
- Outfit preview generation in the first slice.
- Silent overwrite of existing asset fields.

## Product Shape

### Cross-Page Save To Asset

Any page that already has a structured object may expose a small save icon
button with the tooltip `保存为素材`.

Examples include:

- Script workbench role recognition results.
- Script role field cards.
- Script artist-chain replacement rows.
- Outfit candidate rows.
- Script exhibition details when a frame exposes structured role or artist
  data.
- Gallery metadata details when parsed metadata exposes structured role, outfit,
  or artist-chain blocks.
- Workbench import or metadata-derived structured fragments.

Already saved assets should not show this as a normal save action. They should
show a settled state such as `已在素材库` or offer only edit/detail navigation.

Clicking the save icon opens a thin confirmation bar. The bar is lightweight
and should not become a full edit dialog. It shows:

- detected asset type,
- editable name,
- editable note,
- target type selector when more than one legal target exists,
- duplicate/merge status,
- confirm action,
- cancel action.

The bar's job is to avoid accidental saves while preserving the fast "capture
while browsing" rhythm.

### Asset-Library Preview Generation

Preview generation only appears in the asset library. It is available for:

- artist chains,
- characters.

The action appears on both the asset card and detail drawer. Clicking it starts
one immediate image request. While the request is running, the button is
disabled and the card/detail shows a generation-in-progress state. On success,
the image path is added to `imageRefs`, the catalog is refreshed, and the new
image becomes available as the asset preview. On failure, existing `imageRefs`
remain unchanged and the UI shows a retry action with a short error summary.

## Data Model

### Capture Draft

Introduce a UI-neutral draft model, tentatively:

```dart
class StudioAssetCaptureDraft {
  final StudioAssetCaptureKind kind;
  final String suggestedName;
  final String note;
  final Object structuredPayload;
  final StudioAssetCaptureSource source;
  final List<String> imageRefs;
}
```

The exact Dart shape can be adjusted during implementation, but the boundary is
important: pages create drafts; only the capture service writes the workspace.

`structuredPayload` should carry existing model data or model-specific draft
data, not flattened raw text when structured fields are available.

### Capture Source

Each saved asset should keep source context when available:

- source page/surface,
- source id,
- source path,
- source frame/task/gallery record when present.

This uses the existing `SourceRef` pattern where possible. Source information is
for traceability and duplicate detection; it should not expose internal
workspace plumbing to normal user flows.

## Services

### StudioAssetCaptureService

Add a shared service responsible for saving and merging structured drafts.

Responsibilities:

- Normalize draft data.
- Detect likely duplicates.
- Decide whether the default action is create or merge.
- Save confirmed drafts into `WorkspaceService`.
- Preserve existing asset fields during merge.
- Return a result with saved asset identity and merge status.

Pages should not directly call `WorkspaceService.saveCharacters` or
`WorkspaceService.saveArtistChains` for this feature.

### StudioAssetPreviewGenerationService

Add a service responsible for asset-preview generation.

Responsibilities:

- Build a preview payload from a saved asset.
- Force model `nai-diffusion-4-5-full`.
- Randomly choose one supported preview size.
- Call the existing NAI generation path.
- Save the output image.
- Append the saved image path to the target asset's `imageRefs`.
- Optionally write a gallery/provenance record for later review.

The asset-library UI should not manually assemble NAI payloads.

## Merge Behavior

### Artist Chains

Artist-chain duplicate detection should use a normalized combination of:

- structured `artists`,
- `artist:*` tags in prompt/tags/style tags,
- prompt fingerprint,
- aliases/translations when useful.

When merging:

- append missing `artists`,
- append missing `tags`,
- append missing `styleTags`,
- append missing `globalNegatives`,
- append missing `styleHintsWeighted`,
- append missing `vibeRefs`,
- append missing `imageRefs`,
- preserve existing prompt unless it is empty,
- preserve existing user notes and append new context as additional note text.

No existing user-authored content is silently removed.

### Characters

Character duplicate detection should use:

- stable id when present,
- normalized name,
- aliases,
- identity tags,
- prompt/field fingerprint when needed.

When merging:

- preserve existing character fields,
- fill empty structured fields from the draft,
- append missing aliases and image references,
- append non-conflicting notes/source context,
- keep the current `CharacterEntry` system as the only role storage model.

The existing role-field rules remain authoritative. Identity/body/clothing/
accessory/recast fields should not be collapsed into a new generic prompt blob.

### Outfits

Outfits save under a character. The confirmation bar should show or infer the
target character. Duplicate detection should happen inside that character's
outfit list using:

- outfit id,
- normalized outfit name,
- prompt/part-tags fingerprint.

When merging:

- preserve existing outfit fields,
- fill empty fields from the draft,
- append image references,
- append notes.

Outfit preview generation is not part of the first slice.

## Preview Prompt Rules

### Shared Rules

All asset previews use:

- model: `nai-diffusion-4-5-full`,
- one random size from:
  - `832x1216`,
  - `1024x1024`,
  - `1216x832`,
- one generated image per click,
- current local NAI token/proxy/output settings,
- standard quality terms required for useful preview images,
- existing generation error handling.

The preview generator does not mutate the current workbench prompt or model
selection.

### Artist Chain Preview

An artist-chain preview should test the style in a real-looking composition,
not on a blank background.

Payload construction:

1. Randomly select one character from the character library.
2. Build the character prompt from that character's existing structured fields.
3. Add the target artist chain prompt, artists, style tags, and weighted style
   hints.
4. Add a non-plain background/scene baseline.
5. Add quality terms.
6. Use the random preview size.

If the character library is empty, generation is blocked with a clear message
that at least one character asset is required for artist-chain previews.

### Character Preview

A character preview should behave like a simple character reference sheet.

Payload construction:

1. Build the character prompt from the existing `CharacterEntry` fields.
2. Use a plain white background.
3. Add quality terms.
4. Use the random preview size.

The character preview does not add scene/background prompts beyond the white
background requirement.

## UI States

### Save Confirmation Bar

States:

- draft ready,
- duplicate candidate found,
- multiple duplicate candidates found,
- saving,
- saved,
- failed.

If one duplicate candidate is found, the confirm action says
`合并到现有素材`. If multiple candidates are found, the bar shows a compact
target selector and defaults to the highest-confidence match. The user can
choose `另存为新素材`.

After success, show a toast such as `已保存到素材库` with an optional
`查看详情` action.

### Preview Generation

States:

- idle,
- generating,
- generated,
- failed.

During `generating`, the asset card and drawer should show the in-flight state
without shifting layout. On success, the preview image refreshes. On failure,
the card remains usable and exposes retry.

## Error Handling

- No open workspace: keep the draft and show a clear save error.
- Workspace write failure: keep the draft and allow retry.
- Incomplete structured data: allow saving but mark the confirmation bar with a
  compact warning.
- Duplicate conflict: merge only safe fields; preserve conflicting values and
  append context to notes.
- Empty character library for artist-chain preview: block generation and explain
  why.
- Missing NAI token, invalid proxy, network failure, or output path failure:
  surface the existing generation error; leave `imageRefs` unchanged.
- Preview image saved but catalog update fails: keep the image file path in the
  error message and allow retrying the catalog update if practical.

## Testing

### Data Tests

Add coverage for `StudioAssetCaptureService`:

- creates a new artist chain from a structured draft,
- creates a new character using the existing `CharacterEntry` fields,
- creates or merges an outfit under a target character,
- detects artist-chain duplicates through normalized artist tags,
- merges without overwriting existing user fields,
- dedupes `imageRefs` and `vibeRefs`,
- records source context where available.

Add coverage for `StudioAssetPreviewGenerationService`:

- artist-chain preview payload uses a random character and a non-plain scene,
- artist-chain preview blocks when there are no characters,
- character preview payload uses a white background,
- preview model is always `nai-diffusion-4-5-full`,
- preview size is always one of the three approved sizes,
- successful generation appends to `imageRefs`,
- failed generation leaves `imageRefs` unchanged.

### Widget Tests

Add or update UI tests for:

- structured save button opens the thin confirmation bar,
- duplicate detection changes confirm text to merge,
- multiple duplicate candidates show target selection,
- successful save shows a success toast,
- asset-library artist-chain preview button enters generating state,
- generated artist-chain preview refreshes the card image,
- character preview uses the same in-flight/failure behavior,
- existing asset-library search/favorite/send-to-workbench behavior remains
  intact.

### Regression Tests

Keep existing tests around:

- `AssetLibraryPage`,
- `StudioAssetCatalogService`,
- `WorkspaceService`,
- `ProductionExecutorService`,
- `ProductionNaiAdapterService`,
- Script Recast artist-chain replacement and Vibe binding.

## Acceptance Criteria

`NAI_NEW-231z` is complete when:

1. Structured artist chains, characters, and outfits can be saved from shared
   capture entry points without each page owning persistence logic.
2. The save confirmation bar allows name/type/note edits before save.
3. Duplicate assets merge by default and preserve existing user data.
4. Raw prompt text is not treated as a standalone save-to-asset source.
5. Asset-library artist-chain previews run immediately using a random character,
   a scene background, model `nai-diffusion-4-5-full`, and one of the three
   approved sizes.
6. Asset-library character previews run immediately using a white background,
   model `nai-diffusion-4-5-full`, and one of the three approved sizes.
7. Successful preview generation updates the target asset's `imageRefs` and the
   UI preview refreshes.
8. Failed preview generation leaves existing asset references intact and offers
   retry.
9. Focused service/widget tests and relevant regressions pass.
