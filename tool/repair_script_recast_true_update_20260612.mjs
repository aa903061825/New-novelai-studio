import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',\n  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const backupDir = path.join(
  process.cwd(),
  'build',
  'script_recast_true_update_backup_apply_20260612',
);

const roleFieldNames = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

const mappingPartNames = [
  'identity',
  'upperBody',
  'lowerBody',
  'upperClothing',
  'lowerClothing',
];

const transientTerms = new Set([
  'arms under breasts',
  'assertive female',
  'breast sucking',
  'breast_sucking',
  'breasts apart',
  'breasts squeezed together',
  'broken hypnosis',
  'broken_hypnosis',
  'ceiling light',
  'ceiling_light',
  'choke hold',
  'choke_hold',
  'clenched teeth male',
  'dashed eyes',
  'emphasis lines',
  'emphasis_lines',
  'eye contact',
  'faceless female',
  'faceless male',
  'full mouth',
  'full_mouth',
  "hand on girls's head",
  "head on another's feet",
  'hip lock',
  'holind another\'s leg',
  'kimono pull',
  'legs over head',
  'licking ears',
  'licking face',
  'licking girl ear',
  'messy hair',
  'panties pull',
  'pinning down girl',
  'pinnging down girl',
  'pressing girl',
  'reverse spitroast',
  'reverse_spitroast',
  'reverse suspended congress',
  'reverse_suspended_congress',
  'shouting with hands',
  'shouting_with_hands',
  'single bare shoulder',
  'skin fang',
  'sparkling eyes',
  'strap slip',
  'suspended congress',
  'suspended_congress',
  'tearing clothes',
  'tip inside',
  'unaligned breasts',
  'uneven eyes',
  'upturned eyes',
  'vigorous anal thrusting',
  'whispering in ear',
  'whispering_in_ear',
]);

const pendingStateTerms = new Set([
  'no bra',
  'no cap',
  'no gloves',
  'no hat',
  'no jacket',
  'no pants',
  'no panties',
  'no shoes',
  'no skirt',
  'no tail',
]);

const roleMergePlans = {
  'script-5-083e590fd5ca8453.json': [
    { from: 'role-emphasis-lines', to: 'role-musclar-male' },
    { from: 'role-reverse-suspended-congress', to: 'role-musclar-male' },
    { from: 'role-faceless-male-2', to: 'role-musclar-male-3' },
    { from: 'role-faceless-male-3', to: 'role-musclar-male-2' },
  ],
  'script-2-c5e66635f1f2b1d4.json': [
    { from: 'role-reverse-spitroast', to: 'role-muscular-male-3' },
    { from: 'role-faceless-male-2', to: 'role-muscular-male-2' },
  ],
  'script-2-5d755746f12798ed.json': [
    {
      from: 'role-suspended-congress',
      splitBySource: {
        'slot-1': 'role-dark-skinned-male',
        'slot-3': 'role-dark-skinned-male-2',
      },
    },
  ],
  'script-1-fdc34df71c7933c2.json': [
    { from: 'role-tip-inside', to: 'role-source-slot-2' },
    { from: 'role-pinning-down-girl', to: 'role-source-slot-1' },
    { from: 'role-pinnging-down-girl', to: 'role-source-slot-1' },
    { from: 'role-pressing-girl', to: 'role-source-slot-1' },
  ],
  'script-6f722bc858b8a1d6.json': [
    {
      from: 'role-chiara-black-survival',
      to: 'role-source-slot-0',
      moveStages: true,
    },
    {
      from: 'role-chiara-eternal-return',
      to: 'role-source-slot-0',
      moveStages: true,
    },
  ],
  'script-3b7e10afef83c670.json': [
    { from: 'role-source-slot-1-girl', to: 'role-source-slot-0-girl' },
    { from: 'role-faceless-female', to: 'role-source-slot-0-girl' },
    { from: 'role-fat-man-2', to: 'role-fat-man' },
  ],
  'script-for-the-abydos-2-e1716ab4ff3992e2.json': [
    { from: 'role-source-slot-1-girl', to: 'role-source-slot-0-girl' },
  ],
  'script-7c60c4eb98635e13.json': [
    { from: 'role-fat-man-2', to: 'role-fat-man', moveStages: true },
    { from: 'role-faceless-male', to: 'role-source-slot-1-boy' },
  ],
};

const extraRepairs = {
  'script-6f722bc858b8a1d6.json': [
    removeChiaraNonSlotZeroAppearances,
    coverChiaraDetachedSlotEvidence,
  ],
  'script-8ec34e70cc47b935.json': [removeFundoshiLeakFromSlotOneBoy],
};

const targetFiles = uniqueStrings([
  ...Object.keys(roleMergePlans),
  ...Object.keys(extraRepairs),
  'script-2-e82b45f1e2585914.json',
  'script-2-c680f5361d3aff84.json',
  'script-c3a056e39f6b049e.json',
  'script-e3ec3c3cc696513f.json',
  'script-2-925a4ceea200a732.json',
  'script-9471750e51f7f911.json',
]);

const report = {
  apply: options.apply,
  cache_dir: cacheDir,
  backup_dir: options.apply ? backupDir : null,
  files: [],
  totals: {
    files_scanned: 0,
    files_changed: 0,
    roles_removed: 0,
    roles_merged: 0,
    stages_merged: 0,
    terms_removed: 0,
    pending_terms_added: 0,
  },
};

for (const fileName of targetFiles) {
  repairFile(fileName);
}

if (options.reportPath) {
  fs.mkdirSync(path.dirname(options.reportPath), { recursive: true });
  fs.writeFileSync(options.reportPath, `${JSON.stringify(report, null, 2)}\n`);
}
console.log(JSON.stringify(report, null, 2));

function repairFile(fileName) {
  const filePath = path.join(cacheDir, fileName);
  if (!fs.existsSync(filePath)) {
    report.files.push({ file_name: fileName, changed: false, missing: true });
    return;
  }

  report.totals.files_scanned += 1;
  const originalText = fs.readFileSync(filePath, 'utf8');
  const cache = JSON.parse(originalText);
  const fileReport = {
    file_name: fileName,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    changed: false,
    roles_removed: [],
    role_merges: [],
    stages_merged: [],
    terms_removed: [],
    pending_terms_added: [],
    notes: [],
  };

  sanitizeCacheFields(cache, fileReport);
  for (const repair of extraRepairs[fileName] ?? []) {
    repair(cache, fileReport);
  }
  for (const plan of roleMergePlans[fileName] ?? []) {
    mergeRoleByPlan(cache, plan, fileReport);
  }
  collapseAllEquivalentStages(cache, fileReport);
  normalizeAllRoleFrameIndexes(cache);

  const nextText = `${JSON.stringify(cache, null, 2)}\n`;
  fileReport.changed = nextText !== originalText;
  if (fileReport.changed) {
    report.totals.files_changed += 1;
    if (options.apply) {
      fs.mkdirSync(backupDir, { recursive: true });
      const backupPath = path.join(backupDir, fileName);
      if (!fs.existsSync(backupPath)) {
        fs.copyFileSync(filePath, backupPath);
      }
      fs.writeFileSync(filePath, nextText, 'utf8');
    }
  }
  report.files.push(fileReport);
}

function sanitizeCacheFields(cache, fileReport) {
  for (const role of roles(cache)) {
    for (const stage of stages(role)) {
      for (const field of roleFieldNames) {
        const { value, removed, pending } = sanitizeTermString(stage[field]);
        if (value !== stringValue(stage[field])) {
          stage[field] = value;
        }
        for (const term of removed) {
          recordTermRemoved(fileReport, role, stage, field, term);
        }
        for (const term of pending) {
          addRolePendingTerm(role, term, stage.frame_indexes, fileReport);
        }
      }
      if (Array.isArray(stage.evidence_terms)) {
        stage.evidence_terms = cleanEvidenceTerms(stage.evidence_terms);
      }
    }
  }

  for (const assembly of assemblies(cache)) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      for (const partsName of ['sourceParts']) {
        const parts = stage[partsName];
        if (!parts || typeof parts !== 'object') continue;
        for (const field of mappingPartNames) {
          const { value, removed } = sanitizeTermString(parts[field]);
          if (value !== stringValue(parts[field])) {
            parts[field] = value;
          }
          for (const term of removed) {
            fileReport.terms_removed.push({
              role_id: stringValue(assembly.sourceRoleId),
              stage_id: stringValue(stage.id),
              field: `${partsName}.${field}`,
              term,
            });
            report.totals.terms_removed += 1;
          }
        }
      }
    }
  }
}

function sanitizeTermString(value) {
  const kept = [];
  const removed = [];
  const pending = [];
  for (const term of splitTerms(value)) {
    const key = normalizeTerm(term);
    if (transientTerms.has(key)) {
      removed.push(term);
      continue;
    }
    if (pendingStateTerms.has(key)) {
      removed.push(term);
      pending.push(term);
      continue;
    }
    kept.push(term);
  }
  return {
    value: joinTerms(kept),
    removed,
    pending,
  };
}

function cleanEvidenceTerms(values) {
  const kept = [];
  for (const term of values) {
    const key = normalizeTerm(term);
    if (transientTerms.has(key) || pendingStateTerms.has(key)) continue;
    kept.push(stringValue(term).trim());
  }
  return uniqueTerms(kept);
}

function mergeRoleByPlan(cache, plan, fileReport) {
  const from = findRole(cache, plan.from);
  if (!from) return;
  if (plan.splitBySource) {
    let moved = false;
    for (const appearance of appearances(from)) {
      const targetId = plan.splitBySource[stringValue(appearance.source_id)];
      if (!targetId) continue;
      const target = findRole(cache, targetId);
      if (!target) {
        fileReport.notes.push(`${plan.from}:${appearance.source_id}:target_missing`);
        continue;
      }
      addAppearanceFrames(
        target,
        appearance.source_id,
        intList(appearance.frame_indexes),
      );
      addRoleFrames(target, intList(appearance.frame_indexes));
      moved = true;
      fileReport.role_merges.push({
        from: plan.from,
        to: targetId,
        source_id: stringValue(appearance.source_id),
        frame_count: intList(appearance.frame_indexes).length,
      });
      report.totals.roles_merged += 1;
    }
    if (moved) removeRole(cache, plan.from, fileReport);
    return;
  }

  const target = findRole(cache, plan.to);
  if (!target) {
    fileReport.notes.push(`${plan.from}:target_missing:${plan.to}`);
    return;
  }
  for (const appearance of appearances(from)) {
    addAppearanceFrames(
      target,
      appearance.source_id,
      intList(appearance.frame_indexes),
    );
    addRoleFrames(target, intList(appearance.frame_indexes));
  }
  for (const pending of from.unassigned_terms ?? []) {
    addRolePendingTerm(
      target,
      stringValue(pending.term),
      intList(pending.frame_indexes),
      fileReport,
      stringValue(pending.reason),
    );
  }
  if (plan.moveStages) {
    target.stages = [
      ...stages(target),
      ...stages(from).map((stage) => ({
        ...stage,
        stage_id: uniqueStageId(target, stringValue(stage.stage_id)),
      })),
    ];
  }
  fileReport.role_merges.push({
    from: plan.from,
    to: plan.to,
    moved_stages: Boolean(plan.moveStages),
  });
  report.totals.roles_merged += 1;
  removeRole(cache, plan.from, fileReport);
}

function removeRole(cache, roleId, fileReport) {
  const extraction = cache.aiRoleExtraction;
  if (!Array.isArray(extraction?.roles)) return;
  const before = extraction.roles.length;
  extraction.roles = extraction.roles.filter(
    (role) => stringValue(role.source_role_id) !== roleId,
  );
  if (extraction.roles.length !== before) {
    fileReport.roles_removed.push(roleId);
    report.totals.roles_removed += 1;
  }
}

function collapseAllEquivalentStages(cache, fileReport) {
  for (const role of roles(cache)) {
    const before = stages(role).length;
    role.stages = collapseEquivalentStages(stages(role), role, fileReport);
    const after = role.stages.length;
    if (after !== before) {
      fileReport.stages_merged.push({
        role_id: stringValue(role.source_role_id),
        before,
        after,
      });
      report.totals.stages_merged += before - after;
    }
  }
}

function collapseEquivalentStages(stageList, role, fileReport) {
  const collapsed = [];
  const byKey = new Map();
  for (const stage of stageList) {
    const key = stageStableKey(stage);
    const index = byKey.get(key);
    if (index == null) {
      byKey.set(key, collapsed.length);
      collapsed.push({
        ...stage,
        frame_indexes: uniqueSorted(intList(stage.frame_indexes)),
        evidence_terms: cleanEvidenceTerms(stage.evidence_terms ?? []),
        warnings: uniqueTerms(stage.warnings ?? []),
        missing_fields: uniqueTerms(stage.missing_fields ?? []),
      });
      continue;
    }
    const existing = collapsed[index];
    existing.frame_indexes = uniqueSorted([
      ...intList(existing.frame_indexes),
      ...intList(stage.frame_indexes),
    ]);
    existing.evidence_terms = cleanEvidenceTerms([
      ...(existing.evidence_terms ?? []),
      ...(stage.evidence_terms ?? []),
    ]);
    existing.warnings = uniqueTerms([
      ...(existing.warnings ?? []),
      ...(stage.warnings ?? []),
      'outfit_state_variant_merged',
    ]);
    existing.missing_fields = uniqueTerms([
      ...(existing.missing_fields ?? []),
      ...(stage.missing_fields ?? []),
    ]);
    for (const term of splitTerms(stage.non_role)) {
      addRolePendingTerm(
        role,
        term,
        intList(stage.frame_indexes),
        fileReport,
        'merged stage pending field',
      );
    }
  }
  return collapsed.map((stage, index) => ({
    ...stage,
    stage_id: stringValue(stage.stage_id).trim() || `stage-${index + 1}`,
  }));
}

function stageStableKey(stage) {
  return roleFieldNames
    .map((field) =>
      splitTerms(stage[field])
        .map(normalizeTerm)
        .sort()
        .join(','),
    )
    .join('|');
}

function removeChiaraNonSlotZeroAppearances(cache, fileReport) {
  const role = findRole(cache, 'role-source-slot-0');
  if (!role) return;
  const removed = [];
  role.appearances = appearances(role).filter((appearance) => {
    const sourceId = stringValue(appearance.source_id);
    if (sourceId === 'slot-0') return true;
    removed.push({
      source_id: sourceId,
      frame_indexes: intList(appearance.frame_indexes),
    });
    return false;
  });
  if (removed.length === 0) return;
  const remainingFrames = new Set();
  for (const appearance of appearances(role)) {
    for (const index of intList(appearance.frame_indexes)) {
      remainingFrames.add(index);
    }
  }
  for (const stage of stages(role)) {
    stage.frame_indexes = intList(stage.frame_indexes).filter((index) =>
      remainingFrames.has(index),
    );
  }
  role.frame_indexes = uniqueSorted([...remainingFrames]);
  fileReport.notes.push({
    action: 'removed_chiara_non_slot_zero_appearances',
    removed,
  });
}

function coverChiaraDetachedSlotEvidence(cache, fileReport) {
  const slotOneRole = findRole(cache, 'role-source-slot-1');
  const slotTwoRole = findRole(cache, 'role-source-slot-2');
  let changed = false;

  if (slotOneRole) {
    changed =
      addAppearanceFrames(slotOneRole, 'slot-1', [18, 19, 20, 21]) || changed;
    changed =
      ensureStage(slotOneRole, {
        stage_id: 'stage-pov-hands',
        label: 'Pending slot evidence',
        confidence: 0.5,
        frame_indexes: [18, 19],
        identity: '',
        upper_body: '',
        lower_body: '',
        upper_clothing: '',
        lower_clothing: '',
        evidence_terms: [],
        missing_fields: [],
        warnings: ['slot evidence kept pending; no stable role fields'],
      }) || changed;
    changed =
      ensureStage(slotOneRole, {
        stage_id: 'stage-pov-male-hands',
        label: 'Pending male slot evidence',
        confidence: 0.56,
        frame_indexes: [20, 21],
        identity: 'male',
        upper_body: '',
        lower_body: '',
        upper_clothing: '',
        lower_clothing: '',
        evidence_terms: ['male'],
        missing_fields: [],
        warnings: ['slot evidence kept pending; action terms not materialized'],
      }) || changed;
    for (const term of [
      'pov hand',
      'pov crotch',
      'grabbing wrist',
      'holding hand',
      'restraining',
      'looking down at (chiara)',
    ]) {
      changed =
        addRolePendingTerm(
          slotOneRole,
          term,
          [18, 19, 20, 21],
          fileReport,
          'slot evidence kept pending; not a stable role field',
        ) || changed;
    }
  }

  if (slotTwoRole) {
    changed = addAppearanceFrames(slotTwoRole, 'slot-2', [82, 83]) || changed;
    changed =
      ensureStage(slotTwoRole, {
        stage_id: 'stage-pov-bottle-hands',
        label: 'Pending bottle-hand evidence',
        confidence: 0.5,
        frame_indexes: [82, 83],
        identity: '',
        upper_body: '',
        lower_body: '',
        upper_clothing: '',
        lower_clothing: '',
        evidence_terms: [],
        missing_fields: [],
        warnings: ['slot evidence kept pending; no stable role fields'],
      }) || changed;
    for (const term of [
      'pov hands',
      'holding wine bottle',
      'inserting bottle',
      'green glass bottle',
      'watching (chiara)',
    ]) {
      changed =
        addRolePendingTerm(
          slotTwoRole,
          term,
          [82, 83],
          fileReport,
          'slot evidence kept pending; not a stable role field',
        ) || changed;
    }
  }

  const slotOneAssembly = findAssembly(cache, 'role-source-slot-1');
  if (slotOneAssembly) {
    changed =
      addAssemblyAppearanceFrames(slotOneAssembly, 'slot-1', [18, 19, 20, 21]) ||
      changed;
    changed =
      ensureAssemblyStage(slotOneAssembly, {
        id: 'stage-pov-hands',
        label: 'Pending slot evidence',
        frameIndexes: [18, 19],
        sourceSummary: '',
        sourceParts: {},
      }) || changed;
    changed =
      ensureAssemblyStage(slotOneAssembly, {
        id: 'stage-pov-male-hands',
        label: 'Pending male slot evidence',
        frameIndexes: [20, 21],
        sourceSummary: 'male',
        sourceParts: { identity: 'male' },
      }) || changed;
  }

  const slotTwoAssembly = findAssembly(cache, 'role-source-slot-2');
  if (slotTwoAssembly) {
    changed =
      addAssemblyAppearanceFrames(slotTwoAssembly, 'slot-2', [82, 83]) ||
      changed;
    changed =
      ensureAssemblyStage(slotTwoAssembly, {
        id: 'stage-pov-bottle-hands',
        label: 'Pending bottle-hand evidence',
        frameIndexes: [82, 83],
        sourceSummary: '',
        sourceParts: {},
      }) || changed;
  }

  if (changed) {
    fileReport.notes.push({
      action: 'covered_chiara_detached_slot_evidence',
      slot_1_frames: [18, 19, 20, 21],
      slot_2_frames: [82, 83],
    });
  }
}

function removeFundoshiLeakFromSlotOneBoy(cache, fileReport) {
  const role = findRole(cache, 'role-generic-boy-slot-1');
  if (!role) return;
  let changed = 0;
  for (const stage of stages(role)) {
    for (const field of roleFieldNames) {
      const terms = splitTerms(stage[field]);
      const next = terms.filter((term) => normalizeTerm(term) !== 'fundoshi');
      if (next.length !== terms.length) {
        stage[field] = joinTerms(next);
        changed += 1;
        recordTermRemoved(fileReport, role, stage, field, 'fundoshi');
      }
    }
  }
  if (changed > 0) {
    fileReport.notes.push({
      action: 'removed_slot_1_fundoshi_leak',
      changed_fields: changed,
    });
  }
}

function normalizeAllRoleFrameIndexes(cache) {
  for (const role of roles(cache)) {
    const frames = new Set(intList(role.frame_indexes));
    for (const appearance of appearances(role)) {
      appearance.frame_indexes = uniqueSorted(intList(appearance.frame_indexes));
      for (const index of appearance.frame_indexes) frames.add(index);
    }
    for (const stage of stages(role)) {
      stage.frame_indexes = uniqueSorted(intList(stage.frame_indexes));
      for (const index of stage.frame_indexes) frames.add(index);
    }
    role.frame_indexes = uniqueSorted([...frames]);
  }
}

function addAppearanceFrames(role, sourceId, frameIndexes) {
  const normalizedSource = stringValue(sourceId);
  if (!normalizedSource || frameIndexes.length === 0) return false;
  role.appearances = appearances(role);
  let appearance = role.appearances.find(
    (item) => stringValue(item.source_id) === normalizedSource,
  );
  let changed = false;
  if (!appearance) {
    appearance = {
      source_id: normalizedSource,
      source_kind: 'slot',
      frame_indexes: [],
    };
    role.appearances.push(appearance);
    changed = true;
  }
  const next = uniqueSorted([
    ...intList(appearance.frame_indexes),
    ...frameIndexes,
  ]);
  if (!sameIntList(intList(appearance.frame_indexes), next)) {
    appearance.frame_indexes = next;
    changed = true;
  }
  return changed;
}

function addRoleFrames(role, frameIndexes) {
  const next = uniqueSorted([
    ...intList(role.frame_indexes),
    ...frameIndexes,
  ]);
  const changed = !sameIntList(intList(role.frame_indexes), next);
  role.frame_indexes = next;
  return changed;
}

function addRolePendingTerm(
  role,
  term,
  frameIndexes,
  fileReport,
  reason = 'state term needs user confirmation',
) {
  const clean = stringValue(term).trim();
  if (!clean) return;
  role.unassigned_terms = Array.isArray(role.unassigned_terms)
    ? role.unassigned_terms
    : [];
  const key = normalizeTerm(clean);
  const frames = uniqueSorted(intList(frameIndexes));
  const exists = role.unassigned_terms.some(
    (item) =>
      normalizeTerm(item.term) === key &&
      sameIntList(intList(item.frame_indexes), frames),
  );
  if (exists) return;
  role.unassigned_terms.push({
    term: clean,
    frame_indexes: frames,
    reason,
  });
  fileReport.pending_terms_added.push({
    role_id: stringValue(role.source_role_id),
    term: clean,
    frame_indexes: frames,
    reason,
  });
  report.totals.pending_terms_added += 1;
  return true;
}

function ensureStage(role, stageData) {
  role.stages = stages(role);
  let stage = role.stages.find(
    (item) => stringValue(item.stage_id) === stringValue(stageData.stage_id),
  );
  let changed = false;
  if (!stage) {
    stage = {
      stage_id: stringValue(stageData.stage_id),
      label: stringValue(stageData.label),
      appearance_group_id: '',
      merge_with_stage_ids: [],
      field_reasons: {},
      confidence: stageData.confidence ?? 0.5,
      frame_indexes: [],
      identity: '',
      upper_body: '',
      lower_body: '',
      upper_clothing: '',
      lower_clothing: '',
      evidence_terms: [],
      missing_fields: [],
      warnings: [],
    };
    role.stages.push(stage);
    changed = true;
  }
  const nextFrames = uniqueSorted([
    ...intList(stage.frame_indexes),
    ...intList(stageData.frame_indexes),
  ]);
  if (!sameIntList(intList(stage.frame_indexes), nextFrames)) {
    stage.frame_indexes = nextFrames;
    changed = true;
  }
  for (const field of [
    'label',
    'identity',
    'upper_body',
    'lower_body',
    'upper_clothing',
    'lower_clothing',
  ]) {
    const next = stringValue(stageData[field]);
    if (stringValue(stage[field]) !== next) {
      stage[field] = next;
      changed = true;
    }
  }
  for (const field of ['evidence_terms', 'missing_fields', 'warnings']) {
    const next = uniqueTerms(stageData[field] ?? []);
    if (!sameStringList(stage[field] ?? [], next)) {
      stage[field] = next;
      changed = true;
    }
  }
  if (stage.confidence !== stageData.confidence) {
    stage.confidence = stageData.confidence;
    changed = true;
  }
  return changed;
}

function addAssemblyAppearanceFrames(assembly, sourceId, frameIndexes) {
  const normalizedSource = stringValue(sourceId);
  if (!normalizedSource || frameIndexes.length === 0) return false;
  assembly.sourceAppearances = Array.isArray(assembly.sourceAppearances)
    ? assembly.sourceAppearances
    : [];
  let appearance = assembly.sourceAppearances.find(
    (item) => stringValue(item.sourceId) === normalizedSource,
  );
  let changed = false;
  if (!appearance) {
    appearance = {
      sourceId: normalizedSource,
      sourceKind: 'slot',
      frameIndexes: [],
    };
    assembly.sourceAppearances.push(appearance);
    changed = true;
  }
  const next = uniqueSorted([
    ...intList(appearance.frameIndexes),
    ...frameIndexes,
  ]);
  if (!sameIntList(intList(appearance.frameIndexes), next)) {
    appearance.frameIndexes = next;
    changed = true;
  }
  return changed;
}

function ensureAssemblyStage(assembly, stageData) {
  assembly.stages = Array.isArray(assembly.stages) ? assembly.stages : [];
  let stage = assembly.stages.find(
    (item) => stringValue(item.id) === stringValue(stageData.id),
  );
  let changed = false;
  if (!stage) {
    stage = {
      id: stringValue(stageData.id),
      label: stringValue(stageData.label),
      frameIndexes: [],
      sourceSummary: '',
      sourceParts: {},
    };
    assembly.stages.push(stage);
    changed = true;
  }
  const nextFrames = uniqueSorted([
    ...intList(stage.frameIndexes),
    ...intList(stageData.frameIndexes),
  ]);
  if (!sameIntList(intList(stage.frameIndexes), nextFrames)) {
    stage.frameIndexes = nextFrames;
    changed = true;
  }
  for (const field of ['label', 'sourceSummary']) {
    const next = stringValue(stageData[field]);
    if (stringValue(stage[field]) !== next) {
      stage[field] = next;
      changed = true;
    }
  }
  const nextParts = stageData.sourceParts ?? {};
  if (JSON.stringify(stage.sourceParts ?? {}) !== JSON.stringify(nextParts)) {
    stage.sourceParts = nextParts;
    changed = true;
  }
  return changed;
}

function recordTermRemoved(fileReport, role, stage, field, term) {
  fileReport.terms_removed.push({
    role_id: stringValue(role.source_role_id),
    stage_id: stringValue(stage.stage_id),
    field,
    term,
  });
  report.totals.terms_removed += 1;
}

function findRole(cache, roleId) {
  return roles(cache).find(
    (role) => stringValue(role.source_role_id) === roleId,
  );
}

function findAssembly(cache, roleId) {
  return assemblies(cache).find(
    (assembly) =>
      stringValue(assembly.sourceRoleId ?? assembly.source_role_id) === roleId,
  );
}

function roles(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
}

function stages(role) {
  return Array.isArray(role?.stages) ? role.stages : [];
}

function appearances(role) {
  return Array.isArray(role?.appearances) ? role.appearances : [];
}

function assemblies(cache) {
  return Array.isArray(cache.mapping?.roleAssemblies)
    ? cache.mapping.roleAssemblies
    : [];
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter((term) => term.length > 0);
}

function joinTerms(terms) {
  return uniqueTerms(terms).join(', ');
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = stringValue(value).trim();
    const key = normalizeTerm(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function uniqueStrings(values) {
  return [...new Set(values.map((value) => stringValue(value)).filter(Boolean))]
    .sort((left, right) => left.localeCompare(right));
}

function sameStringList(left, right) {
  const leftList = Array.isArray(left) ? left.map(stringValue) : [];
  const rightList = Array.isArray(right) ? right.map(stringValue) : [];
  if (leftList.length !== rightList.length) return false;
  for (let index = 0; index < leftList.length; index += 1) {
    if (leftList[index] !== rightList[index]) return false;
  }
  return true;
}

function uniqueStageId(role, desired) {
  const used = new Set(stages(role).map((stage) => stringValue(stage.stage_id)));
  const base = desired.trim() || 'merged-stage';
  if (!used.has(base)) return base;
  let suffix = 2;
  while (used.has(`${base}-${suffix}`)) suffix += 1;
  return `${base}-${suffix}`;
}

function normalizeTerm(value) {
  return stringValue(value)
    .trim()
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ');
}

function intList(values) {
  if (!Array.isArray(values)) return [];
  return values
    .map((value) => Number(value))
    .filter((value) => Number.isInteger(value) && value > 0);
}

function uniqueSorted(values) {
  return [...new Set(values.map((value) => Number(value)).filter(Number.isInteger))]
    .sort((left, right) => left - right);
}

function sameIntList(left, right) {
  if (left.length !== right.length) return false;
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) return false;
  }
  return true;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    reportPath: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const equalIndex = arg.indexOf('=');
    const key = equalIndex > 0 ? arg.slice(2, equalIndex) : arg.slice(2);
    const value =
      equalIndex > 0 ? arg.slice(equalIndex + 1) : args[index + 1] ?? '';
    if (equalIndex < 0) index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.reportPath = value;
  }
  return parsed;
}
