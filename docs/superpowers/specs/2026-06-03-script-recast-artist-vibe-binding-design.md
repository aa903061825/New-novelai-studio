# Script Recast Artist Vibe Binding Design

## Goal

Script Recast should support two ways to pass Vibe references when replacing an artist chain:

- A reusable artist-chain default binding, so dragging a prepared artist chain into the script automatically carries its required Vibe references.
- A per-script manual addition, so a user can add Vibe references for the current recast even when the target artist chain has no defaults.

The user-facing flow is: replace source artist chain with target artist chain, see any Vibes that come with that target, optionally add more Vibes for this script, then send the script to production.

## Current State

The data and generation layers already have the two required sources:

- `ArtistChain.vibeRefs` stores default Vibe references on an artist chain.
- `RecastMapping.manualVibeRefs` stores manually selected Vibes for the current script mapping.
- `ScriptRecastEngine` resolves Vibes in this order: target artist-chain `vibeRefs`, then mapping `manualVibeRefs`, and writes them into `reference_image_multiple`, `reference_strength_multiple`, and `reference_information_extracted_multiple`.

The missing pieces are the UI entries and persistence workflow:

- The asset library does not expose a compact way to bind Vibes to an artist chain.
- The script page has a manual Vibe panel, but it is visually separate from the artist-chain replacement row and does not show target artist-chain defaults.

## UX

### Asset Library Artist Chain Detail

Artist-chain details get a compact `Default paired Vibe` section.

The section lists available Vibe V4 entries from the current payload/workbench Vibe list. Each row shows:

- Vibe name.
- Reference strength.
- Checkbox state showing whether the artist chain includes this Vibe.

Changing a checkbox updates that artist chain's `vibeRefs` and saves the artist-chain library. If no Vibe V4 entries are available, the section shows an empty hint telling the user to import Vibe V4 first.

This is a scoped editor for the default binding only. It is not a full artist-chain editor.

### Script Artist Mapping Row

Each artist mapping row shows three stacked areas:

- Source artist chain tags.
- Replacement artist chain tags.
- `Paired Vibe` compact slot.

The `Paired Vibe` slot contains:

- Read-only chips for Vibes inherited from the selected target artist chain, labeled `From artist chain`.
- Checkboxes or removable chips for manually selected Vibes, labeled `Added for this script`.
- An empty state when neither source has Vibes.

Dragging an artist-chain asset into the replacement target immediately refreshes inherited Vibe chips. The user does not need to separately select those defaults.

## Data Flow

Asset-library default binding:

1. Load available Vibes from the current payload Vibe V4 list.
2. User toggles default Vibes in the artist-chain detail drawer.
3. Update the selected `ArtistChain.vibeRefs`.
4. Persist through `WorkspaceService.saveArtistChains`.
5. Refresh the asset catalog snapshot and selected detail item.

Script manual addition:

1. Load available Vibes from the current payload Vibe V4 list.
2. User toggles manual Vibes in the artist mapping row.
3. Update `RecastMapping.manualVibeRefs`.
4. Refresh preview/diff.
5. `ScriptRecastEngine` combines selected artist-chain defaults and manual additions during payload resolution.

## Duplicate Handling

The engine keeps the existing encoding-level dedupe behavior. If an inherited Vibe and a manual Vibe have the same `vibeB64`, only the first one is emitted. The UI can still show both sources if they came from different selections, but payload output remains deduped.

## Error Handling

- Vibes with empty `vibeB64` are ignored for generation.
- If the selected target artist chain cannot be found, inherited Vibes are empty.
- If no Vibe V4 entries exist, both binding surfaces show an empty state rather than failing.
- Save failures in the asset-library default binding surface as a snack-bar error and leave the previous in-memory catalog unchanged.

## Testing

Add or update tests for:

- Artist-chain `vibeRefs` are shown in the script mapping row after selecting or dragging an artist chain.
- Manual Vibes can still be added when the artist chain has no defaults.
- Bound artist-chain Vibes and manual Vibes both appear in production payloads in the correct order.
- Duplicate encodings are emitted once.
- Asset-library artist-chain detail can toggle and persist default Vibe bindings.

## Out Of Scope

- Importing Vibe files directly from the script page.
- Editing Vibe strength inline in the script page.
- Full artist-chain editing beyond default Vibe binding.
- Binding NAI3 image-based Vibe entries to artist chains; this design uses Vibe V4 entries because the script page currently exposes Vibe V4 from the payload list.
