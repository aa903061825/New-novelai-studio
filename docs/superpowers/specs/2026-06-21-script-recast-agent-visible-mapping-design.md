# Script Recast Agent-Visible Mapping Design

## Goal

Codex-assisted Script Recast work must produce mappings that are visible and
editable in the existing Script Workbench UI. The agent must not create a
private mapping layer, hidden payload patch, or separate report that becomes the
real source of truth.

The user should be able to ask the agent to map a role, outfit, scene, or other
prompt material, then open Novel Studio, load the target script cache in Script
Workbench, and inspect the actual replacement rules directly.

## Current System

The current replacement model is the point-to-point mapping layer:

- `mapping.rolePromptReplacements`
- `mapping.scenePromptReplacements`
- `ScriptPromptReplacementRule`
- `ScriptPromptReplacementTerm`

Rules can contain multiple source terms, excluded source terms, target prompt
text, manual text, delete actions, match modes, anchor terms, frame scopes, and
target weight multipliers.

Legacy role assemblies and five-field role summaries may still exist in caches,
but they are not the primary agent-editing target. When role prompt replacement
groups exist, generation applies those replacement rules first and uses old role
assembly behavior only as a compatibility or source-location helper.

## Design

Agent edits should be mapping-only by default.

The agent may edit:

- `mapping.rolePromptReplacements`
- `mapping.scenePromptReplacements`

The agent should not edit by default:

- `aiRoleExtraction.roles[*].prompt_terms`
- `aiRoleExtraction.scene_terms`
- role stage/five-field compatibility summaries
- long-term `script_recast/knowledge.json`

This keeps AI/source extraction as the restore source and keeps the user's quick
restore workflow meaningful. If the user resets or regenerates from the UI, the
application can rebuild rules from the preserved extraction data.

The agent may edit AI extraction data only when the user explicitly asks for
cache repair, recognition repair, missing candidate/source terms, or a rebuild
of the extraction itself.

## Agent Workflow

For a requested mapping change:

1. Locate the target script cache and source frame evidence.
2. Back up the current cache before editing.
3. Build or update visible replacement rules in `mapping`.
4. Preserve existing user-authored rule state unless the request explicitly
   replaces it.
5. Run local preview or focused tests where practical to confirm rules affect
   generated payloads.
6. Launch Novel Studio and navigate to Script Workbench for the target script
   when the app workflow is available.
7. Tell the user which script/cache is open and where the backup was written.

The Script Workbench UI is the audit surface. The agent does not need to produce
a second detailed operation report unless the user asks for one.

## Rule Visibility Requirements

Every agent-created mapping must be inspectable in the UI as ordinary
replacement rules:

- role mappings appear under the role replacement section;
- scene mappings appear under the scene replacement section;
- merged source terms remain visible as source chips in the rule;
- target prompt terms remain visible as target chips;
- delete, weight, match-mode, and anchor settings must be stored in the rule
  fields that the existing UI can render or edit;
- frame-scoped terms must retain their `frameIndexes` so the effect can be
  reviewed against source frames.

The agent must not apply changes by directly mutating only final per-frame
payloads. Payload previews are verification output, not the persisted mapping.

## Restore Behavior

Quick restore should continue to work as the user expects:

- mapping-only agent edits are reversible by restoring or regenerating visible
  mapping rules from the preserved extraction layer;
- source extraction data remains available for the workbench's candidate area;
- backups provide a file-level rollback path if the user wants the exact prior
  cache state.

## Sending And Production

Mapping and production are separate actions.

Default behavior:

- write and verify visible mapping rules;
- optionally enqueue production only when the user asks;
- never call the user's Script AI API, translation API, NovelAI generation API,
  token, or proxy unless the current chat explicitly authorizes that action.

If generation is authorized, the production queue should still be built from the
visible mapping rules through `ScriptRecastEngine`, not from hidden agent-only
payload edits.

## Tests And Verification Targets

Implementation should include focused coverage for:

- a mapping-only patch persists to `RecastMapping` without mutating
  `aiRoleExtraction`;
- existing user target fields and rule settings survive agent rule updates;
- generated payloads reflect the edited visible rules;
- quick restore or re-application from AI extraction can replace mapping-only
  agent edits;
- UI tests can render agent-created role and scene rules in Script Workbench.
