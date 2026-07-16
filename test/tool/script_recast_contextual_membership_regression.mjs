import assert from 'node:assert/strict';
import {
  applyContextualMembershipDecisions,
  contextualDecisionTargetConflicts,
  rebuildContextualPromptMappings,
  validateContextualPromptParity,
} from '../../tool/script_recast_contextual_membership.mjs';

function role(id, slot, frameIndex, terms) {
  return {
    source_role_id: id,
    display_name: id,
    frame_indexes: [frameIndex],
    appearances: [
      {
        source_id: `slot-${slot}`,
        source_kind: 'slot',
        frame_indexes: [frameIndex],
      },
    ],
    stages: [
      {
        stage_id: 'stage-1',
        label: 'stage-1',
        frame_indexes: [frameIndex],
        identity: '',
        upper_body: '',
        lower_body: '',
        upper_clothing: '',
        lower_clothing: '',
        evidence_terms: [],
      },
    ],
    prompt_terms: terms,
  };
}

function promptTerm(roleId, category, frameIndex, slot) {
  return {
    id: `role-${roleId}-${category}-shared-term`,
    text: 'shared_term',
    category,
    source_phrase: 'shared_term',
    source_location: `slot-${slot} prompt`,
    frame_indexes: [frameIndex],
    source_occurrences: [
      { frame_index: frameIndex, source_location: `slot-${slot} prompt` },
    ],
  };
}

function fixture() {
  const cache = {
    scriptId: 'contextual-membership-regression',
    mapping: {
      id: 'mapping-contextual-membership-regression',
      scriptId: 'contextual-membership-regression',
      roleSwaps: [],
      roleAssemblies: [],
      rolePromptReplacements: [],
      scenePromptReplacements: [],
    },
    aiRoleExtraction: {
      roles: [
        role('role-a', 0, 1, [promptTerm('role-a', 'upperBody', 1, 0)]),
        role('role-b', 1, 2, [promptTerm('role-b', 'upperBody', 2, 1)]),
        role('role-c', 2, 3, []),
      ],
      scene_terms: [],
    },
    scriptSnapshot: {
      frames: [
        { index: 1, parsed: { baseCaption: '', charCaptions: ['shared_term', '', ''] } },
        { index: 2, parsed: { baseCaption: '', charCaptions: ['', 'shared term', ''] } },
        { index: 3, parsed: { baseCaption: '', charCaptions: ['', '', 'shared-term'] } },
      ],
    },
  };
  rebuildContextualPromptMappings(cache);
  return cache;
}

const removeResult = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'remove-role-a-only',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
  },
]);

assert.equal(removeResult.cache.aiRoleExtraction.roles[0].prompt_terms.length, 0);
assert.equal(removeResult.cache.aiRoleExtraction.roles[1].prompt_terms.length, 1);
assert.equal(
  removeResult.cache.aiRoleExtraction.roles[1].prompt_terms[0].category,
  'upperBody',
  'removing the term from role A must not remove the same normalized term from role B',
);

const aggregatedLegacyCandidate = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'aggregated-occurrences-still-respect-inspection-scope',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    inspection_scope: {
      current_role_label: 'role-a (Role A)',
      current_category_label: 'upperBody',
    },
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-b',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-b-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
  },
]);
assert.equal(aggregatedLegacyCandidate.cache.aiRoleExtraction.roles[0].prompt_terms.length, 0);
assert.equal(
  aggregatedLegacyCandidate.cache.aiRoleExtraction.roles[1].prompt_terms.length,
  1,
  'a role-scoped decision must ignore foreign-role occurrences bundled into the candidate',
);

const displayNameScopedCandidate = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'display-name-scope-resolves-legacy-role',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    inspection_scope: {
      current_role_label: 'Role A Display',
      current_category_label: 'upperBody',
    },
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        role_display_name: 'Role A Display / 角色 A',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-b',
        role_display_name: 'Role B Display / 角色 B',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-b-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
  },
]);
assert.equal(displayNameScopedCandidate.cache.aiRoleExtraction.roles[0].prompt_terms.length, 0);
assert.equal(displayNameScopedCandidate.cache.aiRoleExtraction.roles[1].prompt_terms.length, 1);

const missingTargetMove = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'missing-target-with-one-current-owner-can-move',
    term: 'shared term',
    final_outcome: 'MOVE_OWNER',
    final_role: 'role-c',
    final_category: 'upperBody',
    final_stage_ids: ['stage-1'],
    inspection_scope: {
      current_role_label: 'none/missing for role-c (Role C)',
      current_category_label: 'none',
    },
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
    raw_occurrence_summary: {
      representative_exact: [
        { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
      ],
      representative_containing: [],
    },
  },
]);
assert.equal(missingTargetMove.cache.aiRoleExtraction.roles[0].prompt_terms.length, 0);
assert.equal(missingTargetMove.cache.aiRoleExtraction.roles[1].prompt_terms.length, 1);
assert.equal(missingTargetMove.cache.aiRoleExtraction.roles[2].prompt_terms.length, 1);

assert.throws(
  () =>
    applyContextualMembershipDecisions(fixture(), [
      {
        candidate_id: 'missing-target-with-multiple-current-owners-fails-closed',
        term: 'shared term',
        final_outcome: 'MOVE_OWNER',
        final_role: 'role-c',
        final_category: 'upperBody',
        final_stage_ids: ['stage-1'],
        inspection_scope: {
          current_role_label: 'none/missing for role-c (Role C)',
          current_category_label: 'none',
        },
        current_pending_presence: true,
        current_pending_occurrences: [
          {
            structure: 'aiRoleExtraction',
            role_id: 'role-a',
            field: 'prompt_terms',
            prompt_term_id: 'role-role-a-upperBody-shared-term',
            category: 'upperBody',
          },
          {
            structure: 'aiRoleExtraction',
            role_id: 'role-b',
            field: 'prompt_terms',
            prompt_term_id: 'role-role-b-upperBody-shared-term',
            category: 'upperBody',
          },
        ],
        raw_occurrence_summary: {
          representative_exact: [
            { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
          ],
          representative_containing: [],
        },
      },
    ]),
  /current pending target was not removed/,
  'a missing target must not infer a removal source from multiple current owners',
);

const multipleCategorySource = fixture();
multipleCategorySource.aiRoleExtraction.roles[0].prompt_terms.push(
  promptTerm('role-a', 'accessory', 1, 0),
);
rebuildContextualPromptMappings(multipleCategorySource);
assert.throws(
  () =>
    applyContextualMembershipDecisions(multipleCategorySource, [
      {
        candidate_id: 'missing-target-with-multiple-source-categories-fails-closed',
        term: 'shared term',
        final_outcome: 'MOVE_OWNER',
        final_role: 'role-c',
        final_category: 'upperBody',
        final_stage_ids: ['stage-1'],
        inspection_scope: {
          current_role_label: 'none/missing for role-c (Role C)',
          current_category_label: 'none',
        },
        current_pending_presence: true,
        current_pending_occurrences: [
          {
            structure: 'aiRoleExtraction',
            role_id: 'role-a',
            field: 'prompt_terms',
            prompt_term_id: 'role-role-a-upperBody-shared-term',
            category: 'upperBody',
          },
          {
            structure: 'aiRoleExtraction',
            role_id: 'role-a',
            field: 'prompt_terms',
            prompt_term_id: 'role-role-a-accessory-shared-term',
            category: 'accessory',
          },
        ],
        raw_occurrence_summary: {
          representative_exact: [
            { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
          ],
          representative_containing: [],
        },
      },
    ]),
  /current pending target was not removed/,
  'a missing target must not infer one removal source across multiple categories',
);

assert.throws(
  () =>
    applyContextualMembershipDecisions(fixture(), [
      {
        candidate_id: 'unmatched-declared-scope-fails-closed',
        term: 'shared term',
        final_outcome: 'REMOVE_FROM_PENDING',
        inspection_scope: {
          current_role_label: 'role-does-not-exist',
          current_category_label: 'upperBody',
        },
        current_pending_presence: true,
        current_pending_occurrences: [
          {
            structure: 'aiRoleExtraction',
            role_id: 'role-a',
            field: 'prompt_terms',
            prompt_term_id: 'role-role-a-upperBody-shared-term',
            category: 'upperBody',
          },
        ],
      },
    ]),
  /current pending target was not removed/,
  'an unresolved declared role scope must not fall back to deleting foreign-role terms',
);

const changed = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'change-role-a-only',
    term: 'shared term',
    final_outcome: 'CHANGE_CATEGORY',
    final_role: 'role-a',
    final_category: 'accessory',
    final_stage_ids: ['stage-1'],
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
    raw_occurrence_summary: {
      representative_exact: [
        { frame_index: 1, source_location: 'slot-0 prompt', matched_atom: 'shared_term' },
      ],
      representative_containing: [],
    },
    final_evidence: [
      {
        frame_index: 1,
        source_location: 'slot-0 prompt',
        verbatim_prompt_excerpt: 'shared_term',
      },
    ],
  },
  {
    candidate_id: 'add-role-c-only',
    term: 'shared term',
    final_outcome: 'ADD_TO_PENDING',
    final_role: 'role-c',
    final_category: 'upperBody',
    final_stage_ids: ['stage-1'],
    current_pending_presence: false,
    current_pending_occurrences: [],
    raw_occurrence_summary: {
      representative_exact: [
        { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
      ],
      representative_containing: [],
    },
    final_evidence: [
      {
        frame_index: 3,
        source_location: 'slot-2 prompt',
        verbatim_prompt_excerpt: 'shared-term',
      },
    ],
  },
]);

const [roleA, roleB, roleC] = changed.cache.aiRoleExtraction.roles;
assert.deepEqual(roleA.prompt_terms.map((term) => term.category), ['accessory']);
assert.deepEqual(roleB.prompt_terms.map((term) => term.category), ['upperBody']);
assert.deepEqual(roleC.prompt_terms.map((term) => term.category), ['upperBody']);
assert.equal(
  roleB.prompt_terms[0].id,
  'role-role-b-upperBody-shared-term',
  'changing role A and adding role C must preserve role B byte-for-byte identity',
);
assert.equal(validateContextualPromptParity(changed.cache).ok, true);

const legacyShapeChanged = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'legacy-mapping-shape-change-role-a-only',
    term: 'shared term',
    final_outcome: 'CHANGE_CATEGORY',
    final_role: 'role-a',
    final_category: 'accessory',
    final_stage_ids: ['stage-1'],
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        surface: 'mapping_role_pending',
        owner: 'role-a',
        category: 'upperBody',
        text: 'shared_term',
      },
    ],
    raw_occurrence_summary: {
      representative_exact: [
        { frame_index: 1, source_location: 'slot-0 prompt', matched_atom: 'shared_term' },
      ],
      representative_containing: [],
    },
    final_evidence: [
      {
        frame_index: 1,
        source_location: 'slot-0 prompt',
        verbatim_prompt_excerpt: 'shared_term',
      },
    ],
  },
]);
assert.deepEqual(
  legacyShapeChanged.cache.aiRoleExtraction.roles[0].prompt_terms.map((term) => term.category),
  ['accessory'],
  'legacy mapping_role_pending rows must resolve owner as the contextual role id',
);
assert.deepEqual(
  legacyShapeChanged.cache.aiRoleExtraction.roles[1].prompt_terms.map((term) => term.category),
  ['upperBody'],
);

const duplicateShapesRemoved = applyContextualMembershipDecisions(fixture(), [
  {
    candidate_id: 'structured-remove-role-a',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        structure: 'aiRoleExtraction',
        role_id: 'role-a',
        field: 'prompt_terms',
        prompt_term_id: 'role-role-a-upperBody-shared-term',
        category: 'upperBody',
      },
    ],
  },
  {
    candidate_id: 'legacy-remove-same-role-a',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    current_pending_presence: true,
    current_pending_occurrences: [
      {
        surface: 'mapping_role_pending',
        owner: 'role-a',
        category: 'upperBody',
        text: 'shared_term',
      },
    ],
  },
]);
assert.equal(duplicateShapesRemoved.cache.aiRoleExtraction.roles[0].prompt_terms.length, 0);
assert.equal(duplicateShapesRemoved.cache.aiRoleExtraction.roles[1].prompt_terms.length, 1);

const stageScoped = fixture();
stageScoped.aiRoleExtraction.roles[2].frame_indexes = [3, 4];
stageScoped.aiRoleExtraction.roles[2].appearances[0].frame_indexes = [3, 4];
stageScoped.aiRoleExtraction.roles[2].stages.push({
  ...stageScoped.aiRoleExtraction.roles[2].stages[0],
  stage_id: 'stage-2',
  label: 'stage-2',
  frame_indexes: [4],
});
stageScoped.scriptSnapshot.frames.push({
  index: 4,
  parsed: { baseCaption: '', charCaptions: ['', '', 'shared-term'] },
});

const numericStage = applyContextualMembershipDecisions(stageScoped, [
  {
    candidate_id: 'numeric-stage-id-is-canonicalized',
    term: 'shared term',
    final_outcome: 'ADD_TO_PENDING',
    final_role: 'role-c',
    final_category: 'upperBody',
    final_stage_ids: [1],
    current_pending_presence: false,
    current_pending_occurrences: [],
    raw_occurrence_summary: {
      representative_exact: [
        { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
        { frame_index: 4, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
      ],
      representative_containing: [],
    },
  },
]);
assert.deepEqual(
  numericStage.cache.aiRoleExtraction.roles[2].prompt_terms[0].frame_indexes,
  [3],
  'numeric reviewer stage ids must resolve to stage-N without leaking into other stages',
);

const exactSourceSplit = fixture();
exactSourceSplit.scriptSnapshot.frames[2].parsed.baseCaption = 'shared-term';
const exactScene = applyContextualMembershipDecisions(exactSourceSplit, [
  {
    candidate_id: 'scene-final-occurrence-is-source-exact',
    term: 'shared term',
    final_outcome: 'ADD_TO_PENDING',
    final_role: 'scene',
    final_category: 'scene',
    final_stage_ids: [],
    final_occurrences: [
      { frame_index: 3, source_location: 'base prompt' },
    ],
    current_pending_presence: false,
    current_pending_occurrences: [],
  },
]);
assert.deepEqual(
  exactScene.cache.aiRoleExtraction.scene_terms[0].source_occurrences,
  [{ frame_index: 3, source_location: 'base prompt' }],
  'an exact scene occurrence must not absorb the same term from a role slot',
);

assert.throws(
  () =>
    applyContextualMembershipDecisions(exactSourceSplit, [
      {
        candidate_id: 'unbound-final-occurrence-fails-closed',
        term: 'shared term',
        final_outcome: 'ADD_TO_PENDING',
        final_role: 'scene',
        final_category: 'scene',
        final_stage_ids: [],
        final_occurrences: [
          { frame_index: 1, source_location: 'slot-1 prompt' },
        ],
        current_pending_presence: false,
        current_pending_occurrences: [],
      },
    ]),
  /requested final occurrence is not physically bound/,
  'an exact occurrence allowlist must fail when the cited source does not contain the term',
);

assert.throws(
  () =>
    applyContextualMembershipDecisions(stageScoped, [
      {
        candidate_id: 'unknown-stage-id-fails-closed',
        term: 'shared term',
        final_outcome: 'ADD_TO_PENDING',
        final_role: 'role-c',
        final_category: 'upperBody',
        final_stage_ids: ['stage-99'],
        current_pending_presence: false,
        current_pending_occurrences: [],
        raw_occurrence_summary: {
          representative_exact: [
            { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
          ],
          representative_containing: [],
        },
      },
    ]),
  /addition has no role-scoped physical occurrence/,
  'unknown stage ids must not silently fall back to every role frame',
);

const targetConflicts = contextualDecisionTargetConflicts([
  {
    candidate_id: 'remove-role-a-shared',
    file_name: 'script-fixture.json',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    current_pending_occurrences: [
      { owner: 'role-a', category: 'upperBody', surface: 'mapping_role_pending' },
    ],
  },
  {
    candidate_id: 'split-role-a-shared',
    file_name: 'script-fixture.json',
    term: 'shared term',
    final_outcome: 'SPLIT_BY_STAGE',
    final_role: 'role-a',
    final_category: 'upperBody',
    final_stage_ids: ['stage-1'],
  },
]);
assert.deepEqual(
  targetConflicts.map((row) => row.kind),
  ['remove_add_same_target'],
  'a removal must not silently delete a membership that another decision keeps or splits',
);

const scopedTargetConflicts = contextualDecisionTargetConflicts([
  {
    candidate_id: 'remove-role-b-from-aggregated-evidence',
    file_name: 'script-fixture.json',
    term: 'shared term',
    final_outcome: 'REMOVE_FROM_PENDING',
    inspection_scope: {
      current_role_label: 'role-b (Role B)',
      current_category_label: 'upperBody',
    },
    current_pending_occurrences: [
      { owner: 'role-a', category: 'upperBody', surface: 'mapping_role_pending' },
      { owner: 'role-b', category: 'upperBody', surface: 'mapping_role_pending' },
    ],
  },
  {
    candidate_id: 'split-role-a-from-separate-scope',
    file_name: 'script-fixture.json',
    term: 'shared term',
    final_outcome: 'SPLIT_BY_STAGE',
    final_role: 'role-a',
    final_category: 'upperBody',
    final_stage_ids: ['stage-1'],
  },
]);
assert.deepEqual(
  scopedTargetConflicts,
  [],
  'foreign-role occurrences bundled into one candidate must not create false target conflicts',
);

process.stdout.write('contextual membership regression: ok\n');
