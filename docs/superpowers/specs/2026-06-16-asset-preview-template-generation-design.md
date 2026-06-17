# Asset Preview Template Generation Design

Date: 2026-06-16
Beads issue: `NAI_NEW-431f`

## Goal

Improve asset-library preview generation so previews are driven by explicit
templates instead of a single hard-coded prompt shape.

The target workflows are:

- Artist-chain preview: test the selected artist chain against a random saved
  character card and a random scene-only codex prompt.
- Character-card preview: generate a clean character preview with a chosen
  artist chain, or a random artist chain when none is chosen.
- Both workflows allow a custom prompt to be appended to the template or used as
  a full prompt replacement.

## Current State

`StudioAssetPreviewGenerationService` currently builds prompts internally:

- Artist-chain previews use the selected `ArtistChain` plus a fixed Suzuran
  character anchor and portrait terms.
- Character previews use the current character terms, pure white background,
  and character-reference-sheet terms.
- Outfit previews use current character and outfit terms.
- The UI immediately starts generation after clicking the preview button and
  then asks whether to keep the returned image.

This works, but the prompt behavior is hidden and too rigid for evaluating
artist chains or tuning character-card previews.

## Scope

### In Scope

- Add a generation-options step before starting preview generation.
- Keep support limited to existing preview-capable asset kinds:
  `character`, `outfit`, and `artistChain`.
- Add options for character previews:
  - selected artist-chain id,
  - random artist chain when no explicit chain is selected,
  - solid/simple background template,
  - fixed subject-count terms `1girl, solo`,
  - custom prompt text,
  - custom prompt mode: append or replace.
- Add options for artist-chain previews:
  - random saved character card,
  - random scene entry from legacy/codex inspirations filtered to scene only,
  - selected artist chain remains the style under test,
  - custom prompt text,
  - custom prompt mode: append or replace.
- Preserve current image-request and save behavior:
  model `nai-diffusion-4-5-full`, one generated image, saved to the configured
  output folder, then appended to the target asset `imageRefs` if kept.
- Use deterministic dependency injection in tests for random choices.

### Out Of Scope

- A persistent template editor.
- Saving named prompt templates.
- Batch preview generation.
- Changing global generation settings.
- Replacing outfit preview behavior beyond accepting the same custom prompt
  options if the UI passes them through.

## Product Behavior

### Character Preview

When generating a character preview, the dialog exposes an artist-chain selector
and custom prompt controls.

If the user selects an artist chain, that chain's prompt, tags, style tags, and
Vibe references are included. If no chain is selected, the service chooses one
random artist chain from the workspace. If no artist chains exist, generation
still proceeds with the character-only template.

The generated base prompt is composed from:

1. selected or random artist-chain prompt parts,
2. quality terms,
3. the character name and identity/trait terms,
4. `1girl, solo`,
5. solid/simple background terms,
6. clean readable character-card terms,
7. optional custom prompt text.

The character template must not add `single character`.

### Artist-Chain Preview

When generating an artist-chain preview, the selected chain is still the target
asset whose preview will be updated. The service selects a random character card
from saved characters and a random scene prompt from codex entries classified as
scene by `StudioLegacyCodexCategories.scene`.

The generated base prompt is composed from:

1. selected artist-chain prompt parts,
2. quality terms,
3. random character identity/trait terms,
4. `1girl, solo`,
5. random scene prompt terms,
6. clean readable preview composition terms,
7. optional custom prompt text.

If no character card exists, the service falls back to the existing neutral
preview character terms rather than failing. If no scene codex entry exists, it
uses a simple background fallback.

### Custom Prompt Mode

The dialog supports two modes:

- Append: use the generated template and append the custom prompt text.
- Replace: use only the custom prompt text as the positive prompt.

Replace mode still uses the same model parameters, negative prompt defaults,
Vibe references, saving, and keep/discard flow.

## Data Flow

The UI should pass a small immutable options object to
`StudioAssetPreviewGenerationService` rather than constructing prompts in the
widget. The service remains responsible for loading current workspace assets and
writing back `imageRefs` after the image is saved.

Scene codex selection can be implemented inside the service by loading
`workspaceService.loadInspirations()` plus bundled legacy codex entries if an
existing catalog helper is exposed. The first implementation may use workspace
codex entries and the bundled codex loader path already used by
`StudioAssetCatalogService`, but the filtering rule must stay shared with
`StudioLegacyCodexCategories.scene`.

## Error Handling

- Missing selected artist-chain id should produce a clear generation exception.
- Empty custom prompt in replace mode should fall back to append-mode template
  behavior instead of sending an empty prompt.
- If random pools are empty, use explicit safe fallbacks and continue.
- Existing concurrent-save protection remains: after image generation, reload
  the latest asset list before appending the new image path.

## Testing

Service tests should cover:

- character preview uses a selected artist chain,
- character preview chooses a random artist chain when none is selected,
- character preview includes `1girl, solo` and does not include
  `single character`,
- artist-chain preview uses a random character and scene-only codex prompt,
- custom prompt append mode preserves template text,
- custom prompt replace mode uses only the custom positive prompt,
- keep/discard behavior continues to update or remove `imageRefs`.

Widget tests should cover:

- the generation dialog appears before the loading dialog,
- custom prompt mode is passed to the service,
- artist-chain and character buttons still route to the correct service calls,
- unsupported asset kinds still do not show preview generation controls.
