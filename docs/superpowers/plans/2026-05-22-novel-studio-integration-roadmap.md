# Novel Studio Integration Roadmap

## Why This Is Split

`docs/novel-studio-integrated-prd.md` covers several independent product areas:

1. Internal three-source asset mapping.
2. Workbench transfer, Prompt composition, generation controls, and presets.
3. Library browsing and editing.
4. Gallery metadata round-tripping.
5. Batch production.
6. Prompt cleanup tools from Artist Chain Studio.
7. Navigation and visual redesign.

One implementation plan for all of that would become too large to execute or review safely. The work should move through independently testable slices that keep existing CasRand generation usable while Novel Studio takes shape.

## Non-Negotiable Product Constraints

- Do not expose `Workspace`, source migration, Health, or data-loader concepts in the user-facing product.
- Do not recreate a static Novel Studio shell without a working data flow behind it.
- Keep CasRand generation behavior, batch behavior, prompt rules, I2I/Vibe/Precise Reference, metadata behavior, and settings working while the UI is reorganized.
- Treat KAMIA and Artist Chain Studio data as internal sources for the asset catalog, not as user-facing import wizards.
- User-facing file exchange belongs on the workbench as workbench-scheme import/export.

## Planned Implementation Slices

### Slice 1: Workbench Transfer Foundation

Detailed plan:

`docs/superpowers/plans/2026-05-22-novel-studio-workbench-transfer-foundation.md`

Outcome:

- Internal Novel Studio data storage is initialized automatically.
- A workbench document format exports only creative state, not local secrets or machine-specific settings.
- Legacy CasRand config JSON can be restored through the workbench transfer path.
- Import/export actions move from Settings to the current workbench surface.

### Slice 2: Studio Shell and Asset Catalog

Planned outcome:

- Replace the current three-item CasRand navigation with the six product destinations from the PRD.
- Keep each exposed destination useful: Workbench and Batch reuse real existing generation/config surfaces first; Library reads the internal asset catalog instead of showing placeholder cards.
- Register an internal asset catalog service that can merge KAMIA recipes/tags/characters and Artist Chain artists/characters/filter rules without a user-facing import flow.
- Keep Health and diagnostics off normal navigation.

### Slice 3: Workbench Composer and Single-Image Loop

Planned outcome:

- Add the desktop workbench layout: asset drawer, Prompt stacks, processed Prompt preview, parameter/reference panel, generation result area.
- Convert selected Character, Outfit, Artist Chain, Recipe, Tag, hand-written Prompt, replace rules, and filter rules into the generation payload path.
- Keep current NAI generation controls, I2I, Vibe, Vibe V4, Precise Reference, metadata settings, and prompt preview behavior accessible.

### Slice 4: Gallery Metadata Round-Trip

Planned outcome:

- Persist generated-result records alongside image output.
- Build gallery browsing, filtering, detail metadata, and “send back to workbench”.
- Preserve degraded behavior for missing metadata or broken image/reference files.

### Slice 5: Batch Production Integration

Planned outcome:

- Reframe CasRand Config tree editing and execution under Batch Production.
- Let a saved workbench preset seed a batch configuration without weakening CasRand random/sequential/probability semantics.
- Keep pause/resume, retry, jitter, finite counts, batch-resolution modes, and saved plans test-covered.

### Slice 6: Material Tools and Asset Enrichment

Planned outcome:

- Integrate Artist Chain Studio translation, AI classification, tag-board splitting, filter rules, metadata sorter, single-file preview, and folder batch processing as secondary asset tools.
- Preserve presets and local-rule fallback when online translation or AI classification is unavailable.
- Add KAMIA-adjacent inspiration, LoRA metadata, and workflow asset surfaces where their source data is already mapped.

### Slice 7: Visual Finish and Regression Pass

Planned outcome:

- Replace the Playful Geometric product styling in the new Novel Studio surfaces with a restrained desktop creative-tool design.
- Verify responsive desktop/window behavior, text fit, empty/error states, and high-frequency flows.
- Run broad regression coverage over existing CasRand generation plus new Novel Studio slices.

## Coverage Map

| PRD Area | Roadmap Slice |
|----------|---------------|
| Workbench scheme import/export | Slice 1 |
| Internal three-source mapping | Slices 1-2 |
| Six-area navigation | Slice 2 |
| Library assets and filters | Slices 2 and 6 |
| Workbench Prompt composer | Slice 3 |
| Single-image NAI generation | Slice 3 |
| Gallery metadata loop | Slice 4 |
| Batch production | Slice 5 |
| Translation/classification/sorter tools | Slice 6 |
| Final UI cleanup and regression | Slice 7 |

