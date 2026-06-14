# NAI_NEW Script Recast Cache Contract

## Synthetic Clean Example

This section is fictional. It is not a historical task, does not describe a real
source directory, and must never be copied into live cache JSON. Use it only to
understand the expected cache shape and final audit bar.

Synthetic source root:

`E:/codeximage/example-story-cache-source`

Synthetic ready cache examples:

- `script-example-clean-001`: 24 frames, 2 roles.
- `script-example-clean-002`: 36 frames, 3 roles.

Synthetic role outline for `script-example-clean-001`:

- `role-aria`: appears in `slot-0` on frames 1-12 and 17-24.
  - stage `aria-default`: frames 1-12, `identity="aria example, girl"`,
    `upper_body="blue eyes, long hair"`,
    `upper_clothing="white blouse, blue jacket"`,
    `lower_clothing="black skirt"`.
  - stage `aria-raincoat`: frames 17-24, `identity="aria example, girl"`,
    `upper_body="blue eyes, long hair"`,
    `upper_clothing="yellow raincoat"`,
    `lower_clothing="black skirt, rain boots"`.
- `role-bren`: appears in `slot-1` on frames 5-16.
  - stage `bren-casual`: frames 5-16, `identity="bren example, boy"`,
    `upper_body="short brown hair"`,
    `upper_clothing="gray hoodie"`,
    `lower_clothing="blue jeans, sneakers"`.

Synthetic final reports should have zero source, slot, role, classification,
missing, extra, and incomplete issues. Long-term `script_recast/knowledge.json`
should stay unchanged unless the user explicitly asks to write confirmed
knowledge.

## Cache Shape

Each cache JSON is a `RecastScriptCache`:

- `scriptId`, `scriptName`, `sourceRootPath`, `sourceFingerprint`,
  `sourceContentFingerprint`, `updatedAt`.
- `scriptSnapshot.frames[*]` contains parsed frame evidence:
  `index`, `sourcePath`, `sourceImagePath`, `rawJson`, `parsed.baseCaption`,
  `parsed.charCaptions`, `parsed.negativeBase`,
  `parsed.negativeCharCaptions`, `parsed.coords`, `parsed.sourcePayload`.
- `aiRoleExtraction.status` must be `ready` for completed AI/cache drafts.
- `aiRoleExtraction.roles[*]` is the durable role extraction draft.
- `mapping.roleAssemblies[*].stages[*].sourceParts` mirrors visible source
  fields in the Script Workbench.

Role object essentials:

- `source_role_id`: stable role id. Slot ids may be reused only when the role is
  truly the slot role; use explicit ids for derived or conservative roles.
- `source_kind`: usually `slot` or another project-supported source kind.
- `display_name`, `canonical_name`, `franchise`.
  - `display_name` must be human-facing and must provide a Chinese UI
    translation for every real role. Prefer `original tag / Chinese name` when
    both are useful for recognition.
  - `canonical_name` and `franchise` stay source-faithful and normalized for
    identity matching; do not replace them with translated text.
- `frame_indexes`: union of all appearance/stage frames for that role.
- `appearances[*]`: `{ source_id: "slot-N", source_kind: "slot",
  frame_indexes: [...] }`. Only include a frame if that slot exists and has a
  non-empty caption in that frame.
- `stages[*]`: outfit/appearance phases with the five fields below.
  Stages are replacement-relevant appearance groups, not necessarily contiguous
  story ranges. Merge equivalent states such as the same nude state or the same
  primary upper garment into one stage with non-contiguous `frame_indexes`
  instead of creating duplicate tabs for each scene beat.
- Within one role, duplicate UI stage labels are invalid unless source evidence
  proves the labels are replacement-different appearances. The normal outcome
  for repeated "nude", "swimsuit", "school uniform", "tank top", or similar
  states is one stage whose `frame_indexes` may be non-contiguous.

Stage five fields:

- `identity`: character/source identity plus generic demographic identity only.
- `upper_body`: upper-body traits and accessories such as hair, eyes, ears,
  horns, halo, headwear, collar/choker, upper tattoos, upper body shape.
- `lower_body`: lower-body traits and accessories such as tail, legs, feet,
  ankle items, lower-body marks.
- `upper_clothing`: worn upper/full garments and upper accessories treated as
  garments, such as shirt, jacket, dress, uniform, bra, gloves, sleeves, armor.
- `lower_clothing`: pants, skirt, underwear, legwear, socks, shoes, boots,
  sandals, lower swimwear, garters, footwear.

Display metadata:

- Role-name translation is mandatory for UI review. It is display metadata, not
  prompt replacement evidence.
- `stages[*].label` must be Chinese. When source frames provide stable context,
  prefer context-aware outfit labels such as "浴室裸体", "车间工装", "校园校服",
  or "街头休闲服" instead of generic labels like "裸体" or "工装".
- Context-aware labels may use scene/location/work-context evidence for UI
  recognition, but those context words must not be copied into `identity`,
  `upper_body`, `lower_body`, `upper_clothing`, or `lower_clothing` unless the
  original tag is valid role-field evidence by the five-field rules.

## Evidence Rules

- A term may appear in a role/stage only if it appears in that role/stage's
  source frames. Search `parsed`, selected safe `rawJson`, and copied metadata.
- A term appearing in a different role, different slot, or different stage is
  not evidence for this stage.
- Stable missing fields stay empty. Do not use known character defaults to fill
  a frame/stage.
- Correct obvious typos only when the source evidence and project convention are
  unambiguous, then report the correction.
- Keep prompt tokens in their original language/form where possible. Do not
  translate English/Japanese tag tokens into prettier display text inside role
  fields.
- Translations required for role display names and stage labels are the only
  allowed translation layer. Keep them separate from prompt fields and include
  changed display text in reports when repairing live caches.
- `evidence_terms` should be exactly the stable five-field terms after routing
  and de-duplication.

## Forbidden Error Classes

- Slot mix: role appearance references a `slot-N` frame where that frame has no
  non-empty `charCaptions[N]`.
- Frame drift: `role.frame_indexes`, `appearances.frame_indexes`, and
  `stages.frame_indexes` disagree or reference missing frames.
- Field mix: body trait in `upper_clothing`/`lower_clothing`, or garment in
  `upper_body`/`lower_body`.
- Classification leak: action, pose, scene, camera, expression, mood, temporary
  state, warning, review note, or abstract explanation in any role field.
- Hallucination: any term that is not present in the source evidence for that
  role/stage.
- Silent rewrite: changed tags without a before/after report.
- Non-role materialization: `non_role`, `unassigned_terms`, raw model warnings,
  or diagnostics copied into the role-field output.
- Duplicate stage tabs: the same role has multiple stages with the same
  UI-facing outfit/body-state label even though they should be one replacement
  target.

## Large Batch Subagents

Use subagents when either condition is true:

- more than 6 target script caches;
- more than 600 parsed frames or enough roles that manual proofreading is likely
  to lose coverage.

Split by script id first. Only split by frame ranges when a single script is
very large and stages are easy to merge. Each subagent must:

- use this skill/contract only;
- inspect source evidence directly;
- return a JSON or markdown report with role ids, slot coverage, frame coverage,
  field-routing issues, and proposed exact cache edits;
- avoid applying live changes unless explicitly assigned a write task.

Run a final parent-agent reconciliation pass after subagents finish.

## Audit Commands

Use the active workspace path unless the user names a different cache directory.
Set a source root matching the requested script set. Use an ASCII junction such
as `E:/codeximage/<slug>` when shell tools corrupt non-ASCII paths.

```powershell
node tool/audit_script_recast_cache_integrity.mjs `
  --cache-dir "C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio/script_recast/cache" `
  --source-root "E:/NAI的脚本群/作品集" `
  --report-path "build/<slug>_cache_integrity_final.json"
```

Expected final summary:

- `source_frame_mismatch_count: 0`
- `slot_coverage_issue_count: 0`
- `role_identity_issue_count: 0`
- `role_frame_reference_issue_count: 0`
- `classification_issue_count: 0`
- `issue_cache_count: 0`

```powershell
node tool/audit_script_recast_ai_cache_frames.mjs `
  --cache-dir "C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio/script_recast/cache" `
  --report-path "build/<slug>_ai_cache_frames_final.json"
```

Expected final summary:

- `missing_frame_count: 0`
- `extra_frame_count: 0`
- `incomplete_cache_count: 0`

```powershell
node tool/audit_script_recast_stage_duplicates.mjs `
  --cache-dir "C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio/script_recast/cache" `
  --report-path "build/<slug>_stage_duplicates_final.json"
```

Expected final summary:

- `duplicate_stage_label_group_count: 0`
- `issue_cache_count: 0`

```powershell
node tool/repair_script_recast_role_field_proofread_20260610.mjs `
  --cache-dir "C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio/script_recast/cache" `
  --report "build/<slug>_role_field_proofread_dry_run.json"
```

Expected final summary:

- `files_changed: 0`
- no removed/moved/no-source/transient terms.

If a custom repair script is created for a batch, keep it under `tool/`, support
dry-run by default, require `--apply` for writes, and rerun it without `--apply`
after final application expecting zero changes.

## Reporting Template

Final cache-work summary should include:

- source root and cache directory;
- target script ids, frame counts, role counts;
- backup directory;
- scripts/tools run and reports written;
- field-proofread result;
- role display translation status;
- stage label context status;
- remaining blanks that are intentionally empty due to missing evidence;
- confirmation that `script_recast/knowledge.json` was or was not changed.
