# Script Exhibition Image Organization Design

## Goal

Script Exhibition image storage should be deterministic and safe to clean.

The current source-folder cleanup model is wrong for the user's real data: one
script's images can be mixed across default generated folders and batch output
folders, while one physical folder can contain images from multiple scripts.
Cleanup must therefore stop treating a single script source folder as the
ownership boundary.

The new workflow should let the user click one "organize script images" action
from Script Exhibition and get this result:

- generated images for the selected script are moved into a script/version/frame
  folder structure;
- file names are readable and frame-based;
- persisted references are updated so the app keeps showing the same images;
- unrelated images are not deleted merely because they are in the same folder;
- global cleanup deletes only generated image files that are not referenced by
  any gallery record, any Script Exhibition item, or any production queue task.

## User Decisions

The design follows these confirmed decisions:

- Delete boundary: delete only globally unreferenced generated images.
- Future output root: if the batch production page has an output directory, use
  it as the root; otherwise use the default `Documents/nai-generated` root.
- Duplicate frame naming: first image for a frame uses `001.png`; later images
  use `001-2.png`, `001-3.png`, and so on.
- Original script source images are not moved.
- Gallery has a dedicated localized gallery folder for gallery-only images, but
  if a gallery record already belongs to a script image, the gallery record
  should point to the script-organized image instead of creating a second
  gallery copy.

## Current System

Script Exhibition builds its item list from several persisted sources:

- tokenizer scripts and script recast caches for source/original frames;
- production plans and completed `ProductionTask.outputImagePath` values;
- gallery records and recast provenance;
- user-added image attachments.

The existing source-folder cleanup action scans only
`ScriptExhibitionScript.sourceFolder` and deletes image files inside that folder
that are not referenced by the current script. This is unsafe for mixed
generated output folders and too narrow for the user's intended cleanup.

Future production output currently goes through `ProductionNaiAdapterService`:

- `savePlanImage(bytes, fileName, productionPlanId, outputDirectoryOverride)`
- when no output directory is selected, it scopes files under the production
  plan id;
- when an output directory is selected, it writes under that directory using
  the provided file name.

That means old and future generated images do not yet share the desired
`script/version/frame` layout.

## Path Model

Introduce one shared organizer path model for script-generated images:

```text
<output-root>/<safe-script-name>/<safe-version-name>/<frame-file-name>.png
```

Where:

- `output-root` is the selected batch output directory, or the default
  `Documents/nai-generated` directory when the selected output directory is
  empty.
- `safe-script-name` is derived from the script title/name. It is sanitized for
  Windows file names and deduplicated when needed.
- `safe-version-name` is derived from the Script Exhibition version label.
  Production plan versions use the plan name. Gallery-only versions use the
  localized gallery folder label only when the image is not already
  script-owned.
- `frame-file-name` is derived from `frameIndex`, padded to at least three
  digits. If `frameIndex` is unavailable, use a sanitized source file stem or
  task id.
- Same-frame variants are assigned deterministic suffixes in visible order:
  `001.png`, `001-2.png`, `001-3.png`.

The same naming code must be used by both the manual organize action and future
production output.

## Organize Current Script

Replace the current source-folder cleanup action with "organize script images".

The action runs in two phases.

### Preview

The preview phase loads enough detail for the selected script and computes:

- movable generated images;
- already-correct images;
- skipped original source images;
- references that would be updated;
- destination collisions and suffix assignments;
- global orphan images that would be deleted.

The dialog must show counts and sample paths before making changes. No file move
or delete happens during preview.

### Apply

After confirmation, the apply phase:

1. Creates destination script/version folders.
2. Moves each selected script-generated image to the computed destination.
3. Updates every affected persisted reference.
4. Saves updated production plans, script/image attachment records, and gallery
   records.
5. Deletes only global orphan generated images after references are saved.
6. Refreshes Script Exhibition so the displayed cards point at the new files.

If any move fails, the operation should keep going for independent files and
report failures. It must not delete orphan files when reference updates fail.

## Reference Updates

The organizer must update all references that point to moved files:

- `ProductionTask.outputImagePath`;
- gallery record `imagePath`;
- gallery recast provenance `outputImagePath`;
- Script Exhibition imported image attachments;
- any direct script exhibition item backing record that stores the moved path.

Original source paths are retained and not moved:

- tokenizer source file paths;
- script frame `sourcePath`;
- script frame `sourceImagePath`;
- recast cache source roots.

When a gallery record belongs to a script-owned image, it should reference the
script-organized image. It should not create a duplicate copy under the gallery
folder.

## Global Orphan Cleanup

Global orphan cleanup is limited to generated-image roots:

- the default generated image root;
- output directories recorded on production plan execution settings;
- directories that contain known production output paths.

An image is eligible for deletion only when all of these are true:

- it is under one of the generated-image roots;
- it has an image extension;
- it is not referenced by any loaded production plan task;
- it is not referenced by any gallery record;
- it is not referenced by any Script Exhibition script item, version, or image
  attachment;
- it is not one of the files just moved or newly written by the organizer.

The cleanup deletes image files only. It does not delete JSON, prompt files,
metadata files, or directories in the first implementation.

## Future Generation

Future script recast generation should call the same path model before saving
images.

For `ProductionTaskType.scriptRecastFrame`:

- choose the root from `ProductionPlanExecutionSettings.outputDirectory`, or the
  default generated root when empty;
- derive script folder from `task.source.scriptName`;
- derive version folder from `ProductionPlan.name`;
- derive frame file name from `task.source.frameIndex`;
- add `-2`, `-3`, etc. when a file for the same frame already exists.

Manual single-image generation keeps the current behavior unless it later gains
script identity.

## UI Changes

In Script Exhibition detail header:

- remove or rename the old source-folder cleanup action;
- add an organize-script-images action;
- keep the open-source-folder action as a separate convenience when a source
  folder exists;
- use an explicit confirmation dialog with move/update/delete counts;
- show a SnackBar summary after completion.

The old source-folder cleanup method should not remain reachable from the UI.
It can be removed or kept private only if tests still need migration coverage.

## Error Handling

The operation should be conservative:

- dry-run first;
- never delete before reference saves succeed;
- never move original source images;
- skip missing files and report them;
- skip destination paths that cannot be safely created;
- use collision suffixes rather than overwriting files;
- record failed move/delete paths in the result summary.

If the organizer cannot load all required references, it should refuse to delete
orphans and tell the user that cleanup was skipped.

## Testing

Focused tests should cover:

- organizing one script with completed production tasks moves generated files to
  `script/version/frame` paths and updates `ProductionTask.outputImagePath`;
- same-frame reruns become `001.png`, `001-2.png`, `001-3.png`;
- original source images are not moved;
- gallery records for script-owned images update to the script destination
  without duplicate gallery copies;
- global orphan cleanup deletes only unreferenced generated images and preserves
  images referenced by any script, gallery record, or production task;
- future `savePlanImage` for script recast tasks writes to the same layout;
- UI preview shows counts before applying.

## Non-Goals

This design does not:

- reorganize non-script manual single-image outputs;
- migrate every gallery-only image into the gallery folder in the first pass;
- delete empty directories;
- rewrite original script cache source paths;
- call any image generation API or translation API.
