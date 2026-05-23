# Novel Studio Editable Workbench Design

Date: 2026-05-22
Beads issue: `NAI_NEW-nt1`

## Goal

Rebuild the Novel Studio workbench as a real three-column single-image creation surface while preserving the existing generation path.

This slice must let a user:

- pick available workbench assets from the left rail,
- assemble and edit prompt blocks in the center,
- preview the prompt payload as blocks change,
- keep using the current generation parameters, reference controls, generate action, and result flow on the right.

The workbench should feel ready for future KAMIA prompt composition work without taking on the full KAMIA 8-block system in this issue.

## Scope

### In Scope

- Replace the current workbench outer composition with a three-column Studio layout.
- Use `StudioWorkbenchAssetService.fragments` as the asset-to-workbench input surface.
- Represent selected assets in the workbench as editable prompt blocks.
- Allow prompt blocks to be added, edited, reordered, and removed.
- Keep block edits local to the active workbench by default.
- Provide an explicit save-back action when a supported edited block should update its source asset in the library.
- Recompute the positive and negative prompt preview from workbench blocks and manual prompt input.
- Feed generation through existing `PayloadConfig`, `GenerationPageViewmodel`, and current reference/parameter/result behavior.

### Out of Scope

- Full KAMIA 8-block composer parity, relation semantics, cart semantics, assembly presets, or draft history.
- Full three-source asset consolidation beyond the fragments already exposed to the workbench.
- Batch pipeline redesign.
- New secret, proxy, token, or output-directory transfer behavior.
- Replacing the existing generation view model or payload generation use cases.

## Product Shape

The workbench becomes the main single-image production surface.

### Left: Asset Drawer

The left column exposes assets that are already eligible for workbench use. It should be optimized for selecting material into the current prompt composition rather than editing the whole library.

Initial behavior:

- show the available fragment groups supplied by the workbench asset service,
- let the user add a fragment to the prompt stack,
- make the selection action obvious without turning this drawer into a second asset library page.

### Center: Prompt Composition

The center column is the editing heart of this slice.

It contains:

- a stack of prompt blocks created from selected workbench assets,
- inline editing for each block's prompt text,
- block order controls,
- block removal,
- manual positive and negative prompt input,
- a live prompt preview that reflects blocks plus manual input.

The first version uses editable workbench blocks as a pragmatic bridge:

- a block must retain enough source identity to support explicit save-back when its source type allows it,
- the edited text in the stack is workbench-local until the user explicitly saves it,
- the UI shape should leave room for future richer KAMIA block kinds without forcing those rules into this issue.

### Right: Generation and Results

The right column keeps the existing real generation loop visible beside composition.

It should continue to expose the existing generation controls that already matter for a single image:

- generation parameters,
- reference and control inputs already supported by the current generation surface,
- generate and stop actions,
- generation result preview/cards and current failure/status behavior.

The new workbench must compose around this path instead of introducing a static preview shell or a parallel generation stack.

## Data Flow

### Asset To Block

`StudioWorkbenchAssetService.fragments` remains the first input boundary for the left drawer.

When the user adds an asset:

1. the selected fragment is copied into an active workbench block,
2. the block carries editable prompt content plus the source reference needed for save-back when supported,
3. block state becomes part of the current workbench composition, not a direct mutable view of library state.

### Block To Preview

The center composer derives prompt preview from:

- ordered workbench blocks,
- manual positive prompt input,
- manual negative prompt input,
- the positive or negative contribution carried by each block.

Preview updates whenever a block is added, edited, reordered, removed, or when manual prompt input changes.

### Preview To Generation

Generation remains rooted in the existing generation state.

The composer should update the workbench payload path that already feeds `PayloadConfig` and `GenerationPageViewmodel`, so the prompt preview and the actual generated request do not drift apart. The issue should not create a second prompt compiler that only paints the UI.

### Save Back

Editing a block does not automatically mutate the library.

Save-back is explicit:

- the user invokes a save action on a supported edited block,
- the workbench calls the asset editing path that owns persistence for that source type,
- success keeps the current block content and refreshes source-facing state where the existing architecture expects it,
- unsupported fragment kinds show no misleading save-back affordance.

This preserves fast throwaway prompt editing while still allowing a good block edit to become reusable material.

## State And Boundaries

The implementation should keep three responsibilities separate:

1. asset discovery for the left drawer,
2. active prompt composition state for blocks and manual input,
3. generation execution state owned by the current generation view model.

The workbench composer may adapt existing payload state, but it should not become the owner of network generation, gallery persistence, secret settings, or batch execution.

## Error Handling

The UI should preserve current generation errors and statuses from the existing generation flow.

For new workbench behavior:

- loading an empty asset list should leave the composer usable with manual prompt input,
- adding a fragment should not mutate source asset state before save-back,
- save-back failures should keep the edited workbench block intact and surface a clear failure state,
- unsupported save-back sources should be treated as non-editable persistence targets, not as corrupted blocks.

## Testing

This slice needs focused coverage around the behavioral seam it changes.

### Widget Coverage

- three-column workbench renders the asset drawer, composer, and generation/result surface together,
- selecting a workbench fragment creates an editable prompt block,
- editing, reordering, and removing blocks updates the prompt preview,
- manual prompt input remains available alongside block content,
- supported block save-back is explicit and visible only where persistence is available.

### View Model And Service Coverage

- active composition state clones fragment input rather than mutating source state directly,
- ordered block content is reflected in the payload path used for generation,
- save-back success and save-back failure leave workbench state coherent.

### Regression Coverage

- existing generation path still reaches `GenerationPageViewmodel`,
- current parameter/reference controls remain connected,
- workbench transfer and gallery/result behavior keep their existing contracts.

## Acceptance Criteria

`NAI_NEW-nt1` is complete when:

1. the workbench visibly uses a three-column Studio layout,
2. left-column fragments can create editable prompt blocks in the center,
3. blocks can be edited, reordered, and removed with live positive/negative prompt preview updates,
4. default block edits stay local to the workbench,
5. supported blocks can be explicitly saved back to their source asset while unsupported ones avoid false save affordances,
6. right-column generation still uses the current real generation flow with current controls and result handling,
7. tests cover the new composition behavior and protect the reused generation path.
