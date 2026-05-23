# Novel Studio Waterfall Asset Library Design

Date: 2026-05-22
Beads issue: `NAI_NEW-c8d`

## Goal

Rebuild the Novel Studio asset library as a Studio-style waterfall browsing surface with a detail drawer, while preserving the real `StudioAssetCatalogService` index and the existing "send to workbench" flow.

This slice should make the library feel like a creative material board rather than a grouped card dump. The visual direction stays the current native Studio UI; this issue changes page structure, density, and interaction.

## Scope

### In Scope

- Replace the current sectioned grid/card layout in `AssetLibraryPage` with a waterfall asset board.
- Keep the current Studio theme, Studio tokens, and native Flutter widgets.
- Flatten catalog assets into one searchable/filterable list of asset cards.
- Preserve existing asset types:
  - Character
  - Outfit
  - Artist Chain
  - Recipe
  - Tag
- Keep `StudioAssetCatalogService.loadSnapshot()` as the real data source.
- Keep `StudioWorkbenchAssetService` as the only "send to workbench" action path.
- Add a right-side detail drawer on wide screens.
- Show the detail drawer below the board on compact screens.
- Show source identity, type, block/category, prompt/tag text, note/source fields, and reference status where available.
- Show a warning marker when an asset has reference paths that cannot currently be verified by this slice.
- Keep assets visible even when they have warning markers.

### Out of Scope

- Full edit/save forms for all asset types.
- New asset creation.
- Clone/duplicate asset actions.
- Adding KAMIA non-basic assets such as inspirations, LoRA, workflows, or batch plans.
- Running filesystem validation for every image reference.
- Changing workspace schema or importers.
- Changing workbench prompt composition behavior.
- Changing generation behavior.

## Product Shape

The asset library becomes a two-zone page:

1. a top command band for searching, filtering, counts, and refresh,
2. a waterfall board plus detail drawer for browsing and sending assets to the workbench.

### Top Command Band

The command band remains compact and operational.

It contains:

- page title `素材库`,
- total asset count,
- search input,
- type chips for `全部 / 角色 / Outfit / 画师串 / 配方 / Tag`,
- block chips derived from recipe and tag blocks when available,
- a refresh icon button.

The command band should not become a hero section. It is a work surface control strip.

### Waterfall Board

The board renders all matching assets in a `WaterfallFlow`.

Cards vary naturally by content length:

- short tags stay compact,
- recipes and artist chains can show more prompt text,
- characters and outfits can show traits/outfit summaries,
- notes and reference warnings increase card height only when present.

Every card shows:

- type chip,
- asset title,
- primary prompt/tag summary,
- secondary metadata such as block, category, parent character, or source type,
- warning chip when references need attention,
- one send-to-workbench icon button.

Clicking the body of a card selects it and opens the detail drawer. Sending to the workbench should work from both the card and drawer.

### Detail Drawer

The detail drawer is read-only in this slice.

It shows:

- title and type,
- stable ID,
- block/category/group when present,
- parent character for outfits,
- source type/id/path when present,
- primary prompt/tag body,
- variants or aliases when present,
- image reference paths when present,
- note when present,
- send-to-workbench action.

When no asset is selected, the drawer shows a small empty state explaining that selecting a card will show details.

### Compact Layout

On narrow screens, the command band remains at top, then the waterfall board, then the selected detail panel below it.

The compact layout should stay usable without horizontal scrolling.

## Data Flow

### Snapshot To Display Assets

`AssetLibraryPage` loads `StudioAssetCatalogSnapshot` once per refresh and maps it to internal display rows.

Each display asset carries:

- `id`,
- `type`,
- `title`,
- `summary`,
- `metadata`,
- `searchText`,
- `block`,
- `warningText`,
- `detail sections`,
- `sendToWorkbench` callback.

The mapping is UI-local. It should not mutate catalog entities.

### Filtering

Filtering happens after flattening:

1. apply type filter,
2. apply block filter for recipes and tags,
3. apply normalized search text across title, prompt/tag body, metadata, aliases, variants, note, and source fields.

When no result matches, keep the control band visible and show a clear empty result state.

### Sending To Workbench

Send actions call the existing service methods:

- character -> `appendCharacter(character)`,
- outfit -> `appendOutfit(character, outfit)`,
- artist chain -> `appendArtistChain(artistChain)`,
- recipe -> `appendRecipe(recipe)`,
- tag -> `appendTag(tag)`.

After a successful send, show `已发送到工作台`.

### Reference Warnings

This slice does not perform expensive filesystem existence checks.

If an entity has non-empty `imageRefs`, the UI shows a neutral warning/status chip such as `引用待检查`. This prepares the visible warning surface required by the PRD without hiding the asset or inventing validation results.

Future validation work can replace the generic warning with concrete `缺失引用` data.

## Error Handling

- Loading error: keep current retry behavior and show the error message.
- Loading state: show `正在整理素材索引...`.
- Empty catalog: show PRD copy `素材库还是空的，新建第一条素材，或把工作台结果沉淀进来。`.
- Empty filtered result: show `没有匹配的素材`.
- Send action: if the service call completes, show the existing success snackbar.

## Testing

### Widget Coverage

- The page renders a waterfall board with concrete reusable assets.
- Search filters waterfall cards across title, prompt text, and aliases/metadata.
- Type chips filter the board.
- Block chips filter recipe/tag assets.
- Tapping a card opens the detail drawer with ID, type, body text, and metadata.
- Sending from a card appends to the workbench service and shows the success snackbar.
- Sending from the detail drawer appends to the workbench service.
- Assets with `imageRefs` remain visible and show a reference warning marker.

### Regression Coverage

- Existing catalog service tests keep proving the real snapshot includes characters, outfits, artist chains, recipes, and tags.
- Existing studio shell navigation continues to route to `AssetLibraryPage`.
- Workbench drawer remains independent and does not depend on the full asset library page.

## Acceptance Criteria

`NAI_NEW-c8d` is complete when:

1. `AssetLibraryPage` uses the current Studio visual language and a waterfall board layout.
2. The page still reads real assets through `StudioAssetCatalogService.loadSnapshot()`.
3. Search, type filtering, and block filtering work on the flattened board.
4. Selecting a card opens a detail drawer with readable asset metadata and prompt/tag content.
5. Card and drawer send actions both feed `StudioWorkbenchAssetService`.
6. Reference warnings are visible without hiding affected assets.
7. Focused widget tests, catalog service tests, analyzer, and full Flutter tests pass.
