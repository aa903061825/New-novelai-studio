# Script Exhibition Room IA Design

Date: 2026-06-03

## Decision

Add a standalone `剧本展览室` page to the Studio shell. Keep the existing script editing flow as `剧本工作台`.

Final primary navigation order:

`主页 / 工作台 / 素材库 / 剧本工作台 / 批量产线 / 剧本展览室 / 画廊 / 设置`

Move the current `知识库 / 工具` navigation surface into `设置` instead of keeping it as a primary navigation item.

## Page Responsibilities

### 工作台

Single-image generation core page. This remains the second primary entry.

### 素材库

Long-lived prompt assets: characters, outfits, artist chains, recipes, tags, references, and reusable assets.

### 剧本工作台

Script import, recognition, editing, recast preparation, role evidence, character/outfit/artist replacement, single-frame rerun, and send-to-batch work.

### 批量产线

Queue and execute deterministic production tasks, including script recast batches.

### 剧本展览室

Read-first browsing and archive surface for script assets:

- category shelves
- script cards
- original script frames
- batch-generated results
- single-frame rerun results
- version or batch switching
- full-screen image browsing
- status markers such as needs review, confirmed, archived
- `发送到剧本工作台` action on script cards and script detail

The exhibition room does not own editing or recast controls. It sends a selected `scriptId` to `剧本工作台` for editing.

### 设置

System and maintenance area. Add a `知识库` section or tab here for:

- script role knowledge
- user-confirmed character, outfit, and relationship memories
- AI recognition caches
- translation caches
- prompt classification and tag caches
- cache cleanup, export, import, and index rebuild actions

## Data Strategy

Do not duplicate image files for the exhibition room. Build an aggregate index from existing sources:

- `TokenizerScript` for imported scripts, source frames, roles, and review status.
- `ProductionTask` and `ProductionPlan` for queued/completed script recast output.
- `StudioGalleryRecord.provenance` for generated results already written to the gallery.

Add a lightweight exhibition sidecar for user-facing organization:

`script_exhibition/index.json`

This sidecar stores category definitions, script-to-category mapping, ordering, cover overrides, pinned scripts, and display labels. It does not replace source script data.

## Implementation Notes

- Add `StudioShellSection.scriptExhibition`.
- Rename the visible label for the existing `StudioShellSection.script` entry to `剧本工作台`.
- Reorder Studio navigation to the final approved order.
- Build `ScriptExhibitionPage` and `ScriptExhibitionService`.
- Add a `sendToScriptWorkbench(scriptId)` path from exhibition cards and details.
- Keep the exhibition image viewer as full-screen overlay behavior, not a permanent right-side image inspector.
- Avoid visible default horizontal scrollbars in category shelves; prefer wheel/trackpad horizontal scrolling, arrow buttons, or a styled hidden-scrollbar shelf.

## First Slice

Implement the read-only exhibition room first:

1. Navigation entry and empty page shell.
2. Aggregate scripts from `TokenizerScript`.
3. Category sidecar with default categories and manual assignment.
4. Script cards and script detail with original frames.
5. Add generated results by joining `ProductionTask`/gallery provenance.
6. Add `发送到剧本工作台`.

Editing, recast, and batch controls remain in `剧本工作台`.
