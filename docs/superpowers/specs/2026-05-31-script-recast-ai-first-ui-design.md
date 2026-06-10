# Script Recast AI-First Workflow and UI Design

## Goal

Make the Script Recast feature feel like an AI-assisted workflow instead of a raw candidate review queue. Local analysis should parse, deduplicate, batch, and compress script content for AI. AI should return a structured Recast plan. The user should review the plan, handle exceptions, preview keyframe diffs, and send the result to the batch production pipeline.

Existing detailed tools must not disappear. Candidate evidence, rename, reject, merge, cache details, and batch retry remain available, but they move out of the default path.

## Current Problem

The current flow starts with local role analysis and immediately exposes many candidates for manual handling. On large scripts this creates dozens of rows with confirm, reject, rename, merge, mapping, evidence, and cache controls. This is visually noisy and weakens the value of AI because the user is asked to clean up machine guesses before AI has produced a full interpretation.

The intended flow is different:

1. Import script.
2. Locally parse and deduplicate.
3. Send deduplicated batches to AI.
4. Receive a structured role, clothing, artist-chain, and risk plan.
5. Let the user process the AI result.

## Non-Goals

- Do not remove existing candidate management features.
- Do not rewrite the left asset drawer in this pass.
- Do not rewrite the top AI progress panel in this pass.
- Do not make AI output write long-term knowledge without user confirmation.
- Do not default to exporting new JSON folders. The primary destination remains the batch production pipeline.

## Product Principles

### AI-First, Not Candidate-First

Local analysis is a preprocessing layer. It may identify frames, slots, repeated tag groups, likely duplicate descriptions, and stable AI batches. It should not make the page ask the user to confirm every local candidate before AI analysis.

### Human Reviews Exceptions and Final Plans

High-confidence AI or cache results can be pre-applied to the current working plan. The user should be interrupted for:

- low-confidence recognition,
- duplicate or conflicting character identities,
- asset-library match conflicts,
- AI batch failures,
- changes that affect many frames,
- writes to long-term knowledge.

### Preserve Functionality Through Layering

The UI should expose three layers:

- **Main plan**: the AI-generated Recast plan and production-ready controls.
- **Needs attention**: low-confidence, conflicts, duplicates, failed batches, and risky changes.
- **Details**: raw candidates, evidence tags, per-frame hits, cache source, retry state, rename, reject, and merge tools.

## Revised Workflow

1. **Import Script Directory**
   - Read `nai_*.json` from the selected directory.
   - Keep source files read-only.
   - Detect schema and frame count.

2. **Local Preprocessing**
   - Parse base prompt, character captions, negative prompt, coordinates, and generation parameters.
   - Normalize weight syntax and tag spelling where possible.
   - Deduplicate repeated or near-identical frame/slot material.
   - Build AI batches from compressed source evidence.
   - Record enough evidence to explain each AI result later.

3. **AI Recognition**
   - Submit deduplicated batches to the configured Script AI.
   - Use global AI cache before network calls.
   - Return structured suggestions for:
     - role identity,
     - protagonist/supporting/temporary importance,
     - body parts,
     - upper clothing,
     - lower clothing,
     - outfit or stage label,
     - artist chain,
     - evidence and confidence,
     - asset-library hints,
     - warnings or unresolved ambiguity.

4. **Plan Assembly**
   - Convert AI/cache suggestions into an editable Recast plan.
   - High-confidence results enter the plan as pending applied suggestions.
   - Low-confidence or conflicting results enter the Needs Attention queue.
   - Existing candidate tools remain available from detail panels.

5. **User Review**
   - The user primarily edits the assembled plan, not raw candidates.
   - Character cards, outfit cards, and artist-chain cards can be dragged onto matching plan targets.
   - Replacements remain editable after drop.
   - Applying a change to all matching recognized items should be the default fast path.

6. **Keyframe Preview**
   - Show representative frames such as first, middle, last, and frames with risk markers.
   - Display source words directly.
   - Add labels and translations on top of source words.
   - Use color to distinguish categories.
   - Use stronger visual emphasis for AI recognized, cache hit, user-confirmed, or replacement-affected tokens.

7. **Send to Production**
   - After review, send the plan directly to the batch production pipeline.
   - The production task inherits per-frame source parameters unless the Recast plan explicitly overrides them.

## UI Scope

### Keep

The current left asset drawer can stay. It already supports browsing and dragging asset records.

The top AI progress area can stay. It should continue showing analysis stages, failures, retry state, and cache-only operation.

### Redesign Main Workspace

The main workspace should be rebuilt around an AI Recast plan.

Recommended structure:

- **AI Recast Plan**
  - role slots,
  - detected source identity,
  - target character card,
  - upper body,
  - lower body,
  - upper clothing,
  - lower clothing,
  - outfit stages,
  - artist-chain replacement,
  - preserve/follow/override strategy.

- **Needs Attention**
  - low-confidence recognitions,
  - possible duplicate roles,
  - cache conflicts,
  - asset-library match conflicts,
  - AI batch failures,
  - high-impact replacements.

- **Details Drawer**
  - raw local candidates,
  - evidence tags,
  - per-frame hit lists,
  - cache source and status,
  - rename/reject/merge,
  - retry failed AI batches.

## Keyframe Review Design

The keyframe review area should sit below the main plan. It should show the source prompt in a readable, color-coded form.

### Positive Prompt Column

Positive prompt tokens remain visible as source words. Each token can show:

- source text,
- translated label,
- category,
- recognition source,
- replacement status.

Categories use different colors:

- character,
- upper body,
- lower body,
- upper clothing,
- lower clothing,
- action,
- scene,
- camera/composition,
- artist chain,
- style bias,
- quality.

AI/cache/user-confirmed/replacement-affected tokens use stronger borders or backgrounds. Ordinary classified tokens use lighter color treatment.

### Negative Prompt Column

Negative prompt tokens must be separated into their own column. They should not be mixed with positive role, clothing, scene, or artist tokens.

Negative tokens can still be categorized and colored, for example:

- negative quality,
- negative body/anatomy,
- negative artist/style,
- negative scene/content.

The negative column supports separate preserve/follow/override strategy because negative prompts often need different handling than positive prompt replacements.

## Confirmation Defaults

These defaults are starting points, not hidden permanent rules. The UI should make it clear which items were auto-adopted, which items require attention, and which details were collapsed. Anything moved out of the main screen must remain reachable, and the user should be able to promote a collapsed category back into the main review path if it proves important.

Default adopt:

- high-confidence role classification,
- high-confidence clothing/body stage grouping,
- exact cache hits with no conflict,
- duplicate local candidates merged by stable AI-recognized identity.

Require user confirmation:

- protagonist mapping,
- artist-chain replacement,
- low-confidence recognition,
- duplicate role conflicts,
- long-term knowledge writes,
- any change marked high-impact across many frames,
- final send to production.

Default collapsed:

- raw candidates,
- per-frame evidence lists,
- cache internals,
- successful AI batch details,
- ordinary classified tokens in keyframe review.

## Error Handling

If AI is unavailable, the page should show that local preprocessing completed but the Recast plan is not AI-backed. The user can then:

- retry AI,
- use cache-only suggestions,
- inspect local details,
- proceed manually from the details layer.

AI failures should appear in the top progress area and in the Needs Attention queue, not mixed into every candidate row.

## Testing Strategy

- View model tests verify local preprocessing does not force raw candidate review before AI results.
- AI recognition tests verify deduplicated batches are sent and cache hits are converted into plan entries.
- UI tests verify the main workspace renders plan sections rather than raw candidate rows by default.
- UI tests verify raw candidate controls remain reachable from details.
- Keyframe review tests verify positive and negative columns render separately.
- Keyframe review tests verify category colors are present and AI/cache/user-confirmed states receive stronger emphasis.
- Production tests verify sending uses the reviewed plan and keeps source files read-only.

## Open Questions

- Exact confidence thresholds for automatic adoption should be tuned with real scripts.
- The first implementation can use a fixed set of category colors; later versions may allow user customization.
- The first keyframe set can use first, middle, last, and risky frames; later versions may add user-pinned frames.
