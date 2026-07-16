import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  applyContextualMembershipDecisions,
  rebuildContextualPromptMappings,
} from '../../tool/script_recast_contextual_membership.mjs';
import { validateContextualMembership } from '../../tool/validate_script_recast_contextual_membership.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'contextual-membership-validator-'));
try {
  const baselineDir = path.join(root, 'baseline');
  const cacheDir = path.join(root, 'candidate');
  fs.mkdirSync(baselineDir);
  fs.mkdirSync(cacheDir);
  const fileName = 'script-fixture.json';
  const baseline = fixture();
  const decisions = [
    {
      candidate_id: 'remove-role-a',
      file_name: fileName,
      term: 'shared term',
      final_outcome: 'REMOVE_FROM_PENDING',
      current_pending_presence: true,
      inspection_scope: {
        current_role_label: 'role-a',
        current_category_label: 'upperBody',
      },
      current_pending_occurrences: [
        {
          structure: 'aiRoleExtraction',
          role_id: 'role-a',
          field: 'prompt_terms',
          prompt_term_id: 'role-a-upperBody-shared-term',
          category: 'upperBody',
        },
        {
          structure: 'aiRoleExtraction',
          role_id: 'role-b',
          field: 'prompt_terms',
          prompt_term_id: 'role-b-upperBody-shared-term',
          category: 'upperBody',
        },
      ],
    },
    {
      candidate_id: 'add-role-c',
      file_name: fileName,
      term: 'shared term',
      final_outcome: 'ADD_TO_PENDING',
      final_role: 'role-c',
      final_category: 'upperBody',
      final_stage_ids: [1],
      final_occurrences: [
        { frame_index: 3, source_location: 'slot-2 prompt' },
      ],
      current_pending_presence: false,
      current_pending_occurrences: [],
      raw_occurrence_summary: {
        representative_exact: [
          { frame_index: 3, source_location: 'slot-2 prompt', matched_atom: 'shared-term' },
        ],
        representative_containing: [],
      },
    },
  ];
  const candidate = applyContextualMembershipDecisions(baseline, decisions).cache;
  const decisionsFile = path.join(root, 'decisions.jsonl');
  fs.writeFileSync(path.join(baselineDir, fileName), `${JSON.stringify(fixture(), null, 2)}\n`);
  fs.writeFileSync(path.join(cacheDir, fileName), `${JSON.stringify(candidate, null, 2)}\n`);
  fs.writeFileSync(decisionsFile, `${decisions.map((row) => JSON.stringify(row)).join('\n')}\n`);

  const ok = validateContextualMembership({
    baselineDir,
    cacheDir,
    decisionsFile,
    expectedCount: 1,
  });
  assert.equal(ok.complete, true, JSON.stringify(ok.violations, null, 2));
  assert.equal(ok.violation_count, 0);

  const collateral = JSON.parse(JSON.stringify(candidate));
  collateral.aiRoleExtraction.roles[1].prompt_terms = [];
  rebuildContextualPromptMappings(collateral);
  fs.writeFileSync(path.join(cacheDir, fileName), `${JSON.stringify(collateral, null, 2)}\n`);
  const failed = validateContextualMembership({
    baselineDir,
    cacheDir,
    decisionsFile,
    expectedCount: 1,
  });
  assert.equal(failed.complete, false);
  assert.equal(failed.unexpected_membership_remove_count, 1);
  assert.ok(failed.violations.some((row) => row.kind === 'unexpected_membership_remove'));

  const wrongOccurrence = JSON.parse(JSON.stringify(candidate));
  const added = wrongOccurrence.aiRoleExtraction.roles[2].prompt_terms[0];
  added.source_occurrences = [
    { frame_index: 3, source_location: 'base prompt' },
  ];
  added.source_location = 'base prompt';
  added.frame_indexes = [3];
  rebuildContextualPromptMappings(wrongOccurrence);
  fs.writeFileSync(path.join(cacheDir, fileName), `${JSON.stringify(wrongOccurrence, null, 2)}\n`);
  const occurrenceFailed = validateContextualMembership({
    baselineDir,
    cacheDir,
    decisionsFile,
    expectedCount: 1,
  });
  assert.equal(occurrenceFailed.complete, false);
  assert.equal(occurrenceFailed.decision_occurrence_mismatch_count, 1);
  assert.ok(
    occurrenceFailed.violations.some((row) => row.kind === 'decision_occurrence_mismatch'),
  );
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

function fixture() {
  const cache = {
    scriptId: 'fixture',
    sourceRootPath: 'C:\\fixture',
    mapping: {
      id: 'mapping-fixture',
      scriptId: 'fixture',
      roleSwaps: [],
      roleAssemblies: [],
      rolePromptReplacements: [],
      scenePromptReplacements: [],
    },
    aiRoleExtraction: {
      schema_version: 1,
      status: 'ready',
      roles: [
        role('role-a', 0, 1, [promptTerm('role-a', 0, 1)]),
        role('role-b', 1, 2, [promptTerm('role-b', 1, 2)]),
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

function role(id, slot, frameIndex, terms) {
  return {
    source_role_id: id,
    display_name: id,
    frame_indexes: [frameIndex],
    appearances: [
      { source_id: `slot-${slot}`, source_kind: 'slot', frame_indexes: [frameIndex] },
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

function promptTerm(roleId, slot, frameIndex) {
  return {
    id: `${roleId}-upperBody-shared-term`,
    text: 'shared_term',
    category: 'upperBody',
    source_phrase: 'shared_term',
    source_location: `slot-${slot} prompt`,
    frame_indexes: [frameIndex],
    source_occurrences: [
      { frame_index: frameIndex, source_location: `slot-${slot} prompt` },
    ],
  };
}

process.stdout.write('contextual membership validator regression: ok\n');
