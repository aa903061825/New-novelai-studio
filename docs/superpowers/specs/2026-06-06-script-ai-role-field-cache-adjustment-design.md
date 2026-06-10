# Script AI Role Field Cache Adjustment Design

Date: 2026-06-06
Beads issue: `NAI_NEW-pu5r`

## Goal

Let the user correct AI role-extraction field grouping directly in the visible
draft UI, then reuse those tag-level corrections after future AI extraction.

The feature adds a visible per-stage `Non-role` prompt pool beside the existing
AI role fields, supports drag and drop between all fields, stores manual tag
classification in the existing prompt classification cache, highlights future
cache hits, and adds an `Apply cache adjustment` action that rearranges the AI
draft without confirming or applying role mappings.

## Current State

The Script AI role extraction draft already shows editable per-stage fields:

- identity,
- upper body,
- lower body,
- upper clothing,
- lower clothing.

Each field uses `PromptTagEditor`, which already supports tag chips, selection,
and drag/drop between editors. Editing these fields records manual
classification overrides in `PromptTagClassificationCache` using sources such
as `manual-role-field` and `manual-role-omit`.

The current gap is product-facing:

- Unassigned or non-role terms are only shown in processing details, not beside
  the role fields where the user can act on them.
- The user cannot treat the visible AI draft as a complete WYSIWYG staging
  surface because non-role terms are not part of the same editable model.
- Cached manual classifications can be replayed internally, but there is no
  explicit visible `Apply cache adjustment` action before applying mappings.
- Cache hits are not visibly called out in the AI draft.

## Scope

### In Scope

- Add a sixth editable field to every AI role-extraction stage:
  `Non-role`.
- Populate `Non-role` from all prompt tags that appeared in the frames covered
  by that outfit stage and are not currently visible in the five role fields.
- Deduplicate `Non-role` tags by normalized prompt-tag key.
- Let users drag tags between identity, body, clothing, and non-role fields.
- Persist manual tag-level classification decisions in the existing
  `PromptTagClassificationCache`.
- Add a visible cache-hit treatment for tags whose current placement is backed
  by a manual role classification cache entry.
- Add `Apply cache adjustment` next to the current high-confidence apply action.
- Make `Apply cache adjustment` rearrange only the AI draft, without applying
  or confirming role mappings.
- Do not automatically rearrange the AI draft from manual role cache when AI
  extraction finishes. Extraction completion should mark cache hits; the user
  explicitly clicks `Apply cache adjustment` to move them.
- Preserve prompt weights and normalized tag display behavior already used by
  the current role-extraction flow.

### Out Of Scope

- Role- or stage-specific cache placement. The cache is only tag-level field
  classification.
- Auto-confirming role mappings after cache adjustment.
- Writing AI-only suggestions to long-term knowledge without user confirmation.
- Hidden recovery from raw source prompts after the user has manually adjusted
  the visible AI draft.
- Replacing `PromptTagEditor` with a new drag/drop system.

## Product Rules

### WYSIWYG Is Mandatory

The visible AI draft is the source of truth.

After the draft is shown, downstream actions must read the current visible
fields. They must not silently recover removed tags from the original AI
response, raw source prompts, or cache data. If the user moves a tag to
`Non-role`, that tag is no longer part of the role fields until the user moves
it back or explicitly runs `Apply cache adjustment`. If the user removes a tag
from `Non-role`, it must not silently reappear from stage-frame evidence in the
same reviewed draft.

This keeps the behavior aligned with the existing Script Recast rule: production
and mapping should use the visible reviewed state, not a hidden alternative
state.

### Non-role Pool

For each role stage, initially compute the `Non-role` pool from that stage's
covered frames:

1. Read all positive prompt tags from the frames listed in the stage's
   `frameIndexes`.
2. Normalize tags with the same prompt-tag cleaning and match-key logic used by
   the rest of Script Recast.
3. Build the set of tags currently visible in:
   - identity,
   - upper body,
   - lower body,
   - upper clothing,
   - lower clothing.
4. Put every stage-frame tag that is not present in those visible fields into
   `Non-role`.
5. Deduplicate by normalized key while preserving the first useful display form
   and prompt weight.

`Non-role` is therefore a visible remainder pool for the selected outfit stage.
It is not limited to AI `unassigned_terms`.

Once a draft has a persisted or user-edited non-role field, that visible field
takes precedence. Stage-frame evidence is used to materialize the first draft
or to support the explicit `Apply cache adjustment` action; it is not a hidden
background refill after user review.

### Drag Behavior

All six fields are editable `PromptTagEditor` surfaces:

- dragging from role/body/clothing to `Non-role` removes the tag from the source
  field and adds it to `Non-role`;
- dragging from `Non-role` to a role/body/clothing field removes the tag from
  `Non-role` and adds it to the target field;
- dragging between role/body/clothing fields moves the tag to the target field;
- manual text edits also update the visible draft.

The result after any drag or edit is saved into the script cache as the current
AI role extraction draft.

### Cache Classification

Manual placement writes tag-level cache entries:

- identity -> `PromptTagCategory.character`
- upper body -> `PromptTagCategory.upperBody`
- lower body -> `PromptTagCategory.lowerBody`
- upper clothing -> `PromptTagCategory.upperClothing`
- lower clothing -> `PromptTagCategory.lowerClothing`
- non-role -> `PromptTagCategory.other`

Manual role-field placements should continue using a `manual-role-*` source so
the replay logic can distinguish confirmed user corrections from ordinary rule
or AI classification cache entries.

Upper and lower clothing remain separate categories. They are still part of the
broader clothing concept, but the cache should keep enough information to
return a tag to the specific upper/lower clothing field the user chose.

## Apply Cache Adjustment

Add an `Apply cache adjustment` action in the AI role-extraction draft header,
to the left of the existing high-confidence apply action.

Behavior:

1. It is enabled only when the AI role extraction draft is ready and at least
   one visible draft tag or stage-frame non-role tag has a manual role
   classification cache entry.
2. It reads the current visible draft plus stage-frame tags not represented in
   any of the six visible fields.
3. It routes each cached tag to the cached target field.
4. Tags cached as `other` move to `Non-role`.
5. Tags without manual role cache entries keep their current visible placement.
6. The adjusted draft remains open for review.
7. It does not call the existing mapping apply/confirm path.
8. It saves the adjusted draft into the script cache.

The action is explicit because the user asked for cache help, not automatic
confirmation.

## Cache-hit Visuals

Any tag with a manual role classification cache entry should be visibly marked
after AI extraction, before cache-based repositioning happens. The mark should
be compact and not dominate the field.

Recommended treatment:

- keep the normal category color stripe;
- add a stronger border or small cache badge for `manual-role-*` entries;
- show a tooltip with the cached target field, such as `Cached: upper clothing`;
- use the same treatment in `Non-role` for tags cached as `other`.

This treatment should apply before and after `Apply cache adjustment`, so the
user can see which tags are affected. The visual mark is the only automatic
cache effect after a fresh AI extraction; placement changes wait for the button.

## Data Model

### Extend AI Stage Draft State

Add a non-role field to the local AI role-extraction draft model used by the UI.
This can be implemented either by extending `ScriptAiExtractedStage` with a
`nonRole` string or by adding a UI-adjacent draft wrapper if backward
compatibility makes direct model changes noisy.

The persisted script cache must round-trip the non-role state once the user has
interacted with it. Old cache JSON without this field remains readable and
recomputes non-role from stage frames.

### Stage-frame Tag Source

The view model needs a helper that can build all prompt tags for a role stage's
covered frames. It should reuse existing parsed `Script` frame data and
`PromptTagProcessor` utilities. It should not infer target role identity from
hidden source prompts after the user has reviewed the draft.

### Existing Classification Cache

Keep using `PromptTagClassificationCache`; do not introduce a second cache file
for this feature.

## Services And ViewModel

### StudioScriptViewModel

Add responsibilities:

- compute non-role pool for every ready AI extraction stage;
- expose whether the draft has applicable manual role cache hits;
- apply manual cache routing to the visible AI draft;
- update manual role classification cache when any of the six fields changes;
- save script cache after draft edits and cache adjustment;
- preserve current artist-chain and strong-filter behavior.

### PromptTagEditor / PromptTagDisplay

Prefer small additive support for cache-hit visuals instead of forking the chip
widgets. The implementation can pass a cache-highlight predicate or visual
metadata into `PromptTagEditor` if the existing classification color alone is
not enough.

## Error Handling

- Missing parsed frames: show an empty `Non-role` field with the existing empty
  text; do not block field editing.
- Duplicate tags across fields: prefer the current visible field and avoid
  duplicating the same normalized tag in `Non-role`.
- Cache category cannot map to a role part: leave the tag where it is.
- Cache save fails: keep the in-memory visible draft and surface the same
  best-effort cache behavior already used for manual classification changes.
- Old script cache lacks non-role data: recompute from stage frames.

## Testing

### Model Tests

- `ScriptAiRoleExtraction` or the chosen draft wrapper round-trips non-role
  stage terms.
- Old role extraction cache JSON without non-role remains readable.

### ViewModel Tests

- Non-role pool is built from all frames covered by the selected AI outfit
  stage.
- Non-role pool excludes tags visible in identity/body/clothing fields.
- Non-role pool deduplicates equivalent prompt tags by normalized key.
- Drag/editing a tag into `Non-role` records `PromptTagCategory.other` with a
  manual role source.
- Drag/editing a tag into upper/lower clothing records the specific upper/lower
  clothing category.
- Applying cache adjustment moves cached tags into their cached fields and
  leaves uncached tags where the user currently sees them.
- Applying cache adjustment does not call or mutate confirmed role mappings.
- Applying high-confidence fields after manual adjustments uses the visible
  adjusted draft.

### Widget Tests

- AI role draft renders the `Non-role` field under each stage.
- The existing drag/drop editor behavior works between role fields and
  `Non-role`.
- Cached tags have the special visual treatment.
- `Apply cache adjustment` appears to the left of the existing apply action and
  does not collapse or confirm the draft.

## Acceptance Criteria

`NAI_NEW-pu5r` is complete when:

1. Every ready AI role-extraction stage shows a visible `Non-role` prompt field.
2. `Non-role` contains all deduped prompt tags from that stage's covered frames
   that are not visible in the five role fields.
3. Users can drag tags between role, body, clothing, and non-role fields.
4. The visible draft is the only source used by later apply/production paths.
5. Manual placements are written to the existing prompt classification cache.
6. Future AI extraction visibly marks tags with manual role cache hits.
7. `Apply cache adjustment` rearranges the visible AI draft from cache without
   confirming or applying role mappings.
8. Fresh AI extraction does not silently replay manual role cache placement
   before the user clicks `Apply cache adjustment`.
9. Old script caches remain readable.
10. Focused model, view model, and widget tests cover the WYSIWYG and cache
   adjustment behavior.
