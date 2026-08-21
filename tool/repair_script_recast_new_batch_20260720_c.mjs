#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const TARGET_IDS = new Set([
  'script-4-483f0d961dbafdcc',
  'script-4d8a25fdbfe8f855',
  'script-d539a04e23fddcb6',
  'script-maki-camp-bbc-ntr-af6f4d2f59ae3d94',
]);

const DISPLAY_NAMES = {
  'role-kurumi-princess-connect':
    'kurumi (princess connect!) / 胡桃（公主连结）',
  'role-ayane-princess-connect':
    'ayane (princess connect!) / 绫音（公主连结）',
  'role-suzume-princess-connect':
    'suzume (princess connect!) / 铃莓（公主连结）',
  'role-misato-princess-connect':
    'misato (princess connect!) / 美里（公主连结）',
  'role-marie-antoinette-fate':
    'marie antoinette (fate) / 玛丽·安托瓦内特（Fate）',
  'role-maki-camp-blue-archive':
    'maki (camp) (blue archive) / 真纪（露营）（碧蓝档案）',
  'role-sensei-blue-archive':
    'sensei (blue archive) / 老师（碧蓝档案）',
};

const INVALID_ROLE_TERMS = new Set([
  'arm under breast',
  'armpit crease',
  'ass focus',
  'averting eyes',
  'bouncing ass',
  'bouncing breast',
  'bouncing breasts',
  'breast on dresser',
  'breast press',
  'breast sucking',
  'breasts apart',
  'breasts on glass',
  'breasts squeezed together',
  'covering own eyes',
  'covering own face',
  'dashed eyes',
  'eye contact',
  'face down',
  'face in crotch',
  'face outside',
  'fingering through clothes',
  'guided breast grab',
  'hand in clothes',
  'hand over eyes',
  'heart-shaped pupils',
  'holding another s legs',
  "holding another's legs",
  'hugging own legs',
  'knees to chest',
  'leg around another s leg',
  "leg around another's leg",
  'leg grab',
  'leg lift',
  'leg lock',
  'leg up',
  'legs apart',
  'legs up',
  'm legs',
  'male focus',
  'nipple pull',
  'nipple rub',
  'nipple stimulation',
  'nipple tweak',
  'no eyes',
  'peins on face',
  'penis awe',
  'stomach bulge',
  'symbol-shaped pupils',
  'uneven eyes',
  'view between legs',
]);

const ACCESSORY_TERMS = new Set([
  'animal collar',
  'black bow',
  'black choker',
  'black collar',
  'blindfold',
  'black blindfold',
  'blue gemstone',
  'cap',
  'detached collar',
  'feather hair ornament',
  'hair band',
  'hair bow',
  'hair flower',
  'hair ornament',
  'hair ribbon',
  'hairband',
  'knit cap',
  'knit hat',
  'maid headdress',
  'mouth veil',
  'no hair ornament',
  'nun headdress',
  'orange veil',
  'pink bowtie',
  'red collar',
  'straw hat',
  'unworn blindfold',
  'veil',
  'visor cap',
  'wing collar',
  'wrist cuffs',
]);

const CLOTHING_STATE_TERMS = new Set([
  'bare shoulders',
  'beer on shoes',
  'bikini bottom only',
  'breasts out',
  'cameltoe',
  'covered navel',
  'covered nipples',
  'denim shorts around one leg',
  'no bra',
  'no gloves',
  'no panties',
  'nipple peek',
  'nipple slip',
  'see-through dress',
  'see-through shirt',
  'torn pantyhose',
  'torn thighhighs',
  'towel around waist',
  'underwear only',
]);

const BODY_TERMS = new Set([
  'bald',
  'curvy',
  'dark-skinned male',
  'faceless male',
  'fat man',
  'musclar male',
  'muscular',
  'muscular male',
  'shortstack',
  'underbutt',
  'ugly bastard',
  'very dark skin',
  'white boy',
]);

const SCENE_TERMS = new Set([
  'alley',
  'autumn',
  'bar',
  'beach',
  'bed curtains',
  'bed room',
  'book',
  'bathroom',
  'dark',
  'dark room',
  'day',
  'indoors',
  'lamp',
  'night',
  'on bed',
  'outdoors',
  'park',
  'room',
  'sand',
  'sign',
  'sky',
  'street',
  'sunrise',
  'tent',
  'tent door',
  'tent interior',
  'white bed sheet',
  'wooden chair',
  'wooden desk',
  'wooden door',
  'wooden table',
  'wooden wall',
]);

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Pass --cache-dir <directory>.');
}
const cacheDir = path.resolve(options.cacheDir);
const reportPath = path.resolve(
  options.report ?? path.join(cacheDir, 'repair_c_report.json'),
);
const backupDir = path.resolve(
  options.backupDir ?? path.join(path.dirname(cacheDir), 'repair_c_backup'),
);
if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();
const report = {
  tool: 'repair_script_recast_new_batch_20260720_c',
  api_used: false,
  apply: options.apply,
  cache_dir: cacheDir,
  backup_dir: options.apply ? backupDir : null,
  files_scanned: 0,
  files_changed: 0,
  roles_before: 0,
  roles_after: 0,
  stages_before: 0,
  stages_after: 0,
  role_prompt_terms_before: 0,
  role_prompt_terms_after: 0,
  scene_terms_before: 0,
  scene_terms_after: 0,
  role_mapping_groups_after: 0,
  role_mapping_rules_after: 0,
  scene_mapping_groups_after: 0,
  scene_mapping_rules_after: 0,
  rows: [],
};

for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (!TARGET_IDS.has(stringValue(cache.scriptId))) continue;
  report.files_scanned += 1;
  const before = stats(cache);
  const beforeText = JSON.stringify(cache);
  const changes = [];
  repairCache(cache, changes);
  const after = stats(cache);
  const changed = beforeText !== JSON.stringify(cache);
  if (changed) report.files_changed += 1;
  accumulate(report, before, after);
  report.rows.push({
    file_name: file,
    script_id: cache.scriptId,
    changed,
    before,
    after,
    changes,
  });
  if (options.apply && changed) {
    fs.mkdirSync(backupDir, { recursive: true });
    const backupPath = path.join(backupDir, file);
    if (!fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
    cache.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(report, null, 2));

function repairCache(cache, changes) {
  const scriptId = stringValue(cache.scriptId);
  const extraction = cache.aiRoleExtraction ?? {};
  extraction.roles = arrayValue(extraction.roles);
  extraction.scene_terms = arrayValue(extraction.scene_terms);
  extraction.attention_items = arrayValue(extraction.attention_items);
  cache.aiRoleExtraction = extraction;

  if (scriptId === 'script-4-483f0d961dbafdcc') {
    deleteRole(extraction, 'role-null-nyanpyoun', changes);
    addAppearanceFrames(
      findRole(extraction, 'role-anonymous-male'),
      'slot-1',
      [156, 157],
      changes,
    );
    addStageFrames(
      findRole(extraction, 'role-anonymous-male'),
      'stage-1',
      [156, 157],
      changes,
    );
    setNoRolePartial(extraction, {
      id: 'no-role-partial-slot-1-frames-175-177',
      source_id: 'slot-1',
      frame_indexes: [175, 176, 177],
      evidence: 'boy, disembodied hands, holding syringe',
      message:
        'Frames 175-177 slot-1 contain disembodied hands and syringe actions only; intentionally not materialized as a role.',
    });
  }

  if (scriptId === 'script-maki-camp-bbc-ntr-af6f4d2f59ae3d94') {
    splitMakiAnonymousMale(cache, changes);
    mergeMakiSensei(cache, changes);
  }

  for (const role of extraction.roles) {
    if (DISPLAY_NAMES[role.source_role_id]) {
      setValue(role, 'display_name', DISPLAY_NAMES[role.source_role_id], changes);
    }
    role.warnings = [];
    normalizeAppearances(role);
    repairPromptTerms(cache, role, changes);
    addGenericBoyIdentity(cache, role, changes);
    cleanStages(role, changes);
  }

  addScriptSpecificTermsAndFields(cache, changes);
  applyStageLabels(cache, changes);
  for (const role of extraction.roles) finalizeRole(role);
  extraction.scene_terms = buildSceneTerms(cache);
  extraction.status = extraction.roles.length > 0 ? 'ready' : 'needs_more_evidence';
  synchronizeMapping(cache);
}

function splitMakiAnonymousMale(cache, changes) {
  const extraction = cache.aiRoleExtraction;
  const original = findRole(extraction, 'role-anonymous-male');
  if (!original) return;
  const specs = [
    {
      id: 'role-anonymous-male-slot-1',
      display: 'boy / 匿名男性 A',
      sourceId: 'slot-1',
      frames: uniqueInts([
        ...appearanceFrames(original, 'slot-1'),
        87,
      ]),
      label: '露营地匿名男性 A',
      bodyTerms: ['very dark skin', 'muscular'],
    },
    {
      id: 'role-anonymous-male-slot-2',
      display: 'boy / 匿名男性 B',
      sourceId: 'slot-2',
      frames: uniqueInts([
        ...appearanceFrames(original, 'slot-2'),
        87,
      ]),
      label: '露营地匿名男性 B',
      bodyTerms: ['very dark skin', 'muscular'],
    },
    {
      id: 'role-anonymous-male-slot-3',
      display: 'boy / 匿名男性 C',
      sourceId: 'slot-3',
      frames: appearanceFrames(original, 'slot-3'),
      label: '露营地匿名男性 C',
      bodyTerms: [],
    },
  ];
  const roles = specs.map((spec) => {
    const role = {
      source_role_id: spec.id,
      source_kind: 'slot',
      display_name: spec.display,
      role_reason:
        'Conservative per-slot split because multiple anonymous males occur simultaneously in the source frames.',
      canonical_name: '',
      franchise: '',
      raw_identity_tags: ['boy'],
      variant_tags: [],
      merge_with_role_id: '',
      confidence: 0.72,
      frame_indexes: spec.frames,
      appearances: [
        {
          source_id: spec.sourceId,
          source_kind: 'slot',
          frame_indexes: spec.frames,
        },
      ],
      evidence_terms: [],
      warnings: [],
      stages: [
        makeStage({
          id: 'stage-1',
          label: spec.label,
          frames: spec.frames,
          identity: 'boy',
          upperBody: spec.bodyTerms.join(', '),
        }),
      ],
      unassigned_terms: [],
      prompt_terms: [],
    };
    addTermFromRoleSource(cache, role, 'boy', 'identity', ['boy']);
    for (const term of spec.bodyTerms) {
      addTermFromRoleSource(cache, role, term, 'body', [term]);
    }
    return role;
  });
  const index = extraction.roles.indexOf(original);
  extraction.roles.splice(index, 1, ...roles);
  changes.push(
    'split role-anonymous-male into role-anonymous-male-slot-1/2/3 by simultaneous source slots',
  );
}

function mergeMakiSensei(cache, changes) {
  const extraction = cache.aiRoleExtraction;
  const animation = findRole(
    extraction,
    'role-sensei-blue-archive-the-animation',
  );
  const standard = findRole(extraction, 'role-sensei-blue-archive');
  if (!animation || !standard) return;
  const mergedAppearances = mergeAppearances([
    ...arrayValue(animation.appearances),
    ...arrayValue(standard.appearances),
  ]);
  const merged = {
    ...standard,
    source_role_id: 'role-sensei-blue-archive',
    source_kind: 'cross_slot',
    display_name: DISPLAY_NAMES['role-sensei-blue-archive'],
    role_reason:
      'Merged source-faithful Sensei franchise-tag variants across continuous frames 88-94.',
    raw_identity_tags: [
      'sensei (blue archive the animation)',
      'sensei (blue archive)',
      'boy',
    ],
    frame_indexes: uniqueInts(
      mergedAppearances.flatMap((appearance) => appearance.frame_indexes),
    ),
    appearances: mergedAppearances,
    warnings: [],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '白色袖套',
        frames: uniqueInts(
          mergedAppearances.flatMap((appearance) => appearance.frame_indexes),
        ),
        identity:
          'sensei (blue archive the animation), sensei (blue archive), boy',
        upperBody: 'white boy',
        upperClothing: 'white sleeves',
      }),
    ],
    prompt_terms: [],
  };
  addTermFromRoleSource(
    cache,
    merged,
    'sensei (blue archive the animation)',
    'identity',
    ['sensei (blue archive the animation)'],
  );
  addTermFromRoleSource(
    cache,
    merged,
    'sensei (blue archive)',
    'identity',
    ['sensei (blue archive)'],
  );
  addTermFromRoleSource(cache, merged, 'boy', 'identity', ['boy']);
  addTermFromRoleSource(cache, merged, 'white boy', 'body', ['white boy']);
  addTermFromRoleSource(
    cache,
    merged,
    'white sleeves',
    'clothing',
    ['white sleeves'],
  );
  const firstIndex = Math.min(
    extraction.roles.indexOf(animation),
    extraction.roles.indexOf(standard),
  );
  extraction.roles = extraction.roles.filter(
    (role) => role !== animation && role !== standard,
  );
  extraction.roles.splice(firstIndex, 0, merged);
  changes.push(
    'merged role-sensei-blue-archive-the-animation into role-sensei-blue-archive',
  );
}

function repairPromptTerms(cache, role, changes) {
  const next = [];
  for (const rawTerm of arrayValue(role.prompt_terms)) {
    let text = cleanTag(rawTerm.text);
    if (!text) continue;
    const normalized = normalizedTagKey(text);
    if (INVALID_ROLE_TERMS.has(normalized)) {
      changes.push(`removed transient/action prompt term ${role.source_role_id}:${text}`);
      continue;
    }
    if (normalized === 'mature man') text = 'mature male';
    let category = contractCategory(rawTerm.category);
    if (ACCESSORY_TERMS.has(normalizedTagKey(text))) category = 'accessory';
    if (CLOTHING_STATE_TERMS.has(normalizedTagKey(text))) {
      category = 'clothingState';
    }
    if (BODY_TERMS.has(normalizedTagKey(text))) category = 'body';
    if (normalizedTagKey(text) === 'mature male' || normalizedTagKey(text) === 'student') {
      category = 'identity';
    }
    if (!category || category === 'scene') continue;
    const occurrences = validatedOccurrences(cache, role, rawTerm, text);
    if (occurrences.length === 0) {
      changes.push(`removed no-source prompt term ${role.source_role_id}:${text}`);
      continue;
    }
    mergeTerm(next, makeTerm(role.source_role_id, text, category, occurrences));
  }
  role.prompt_terms = next;
}

function validatedOccurrences(cache, role, term, repairedText) {
  const frames = frameMap(cache);
  const rolePositions = rolePositionSet(role);
  const candidates = arrayValue(term.source_occurrences).map((occurrence) => ({
    frameIndex: Number(occurrence.frame_index),
    sourceId: sourceIdFromLocation(occurrence.source_location),
  }));
  const sourcePhrases = uniqueStrings([
    cleanTag(term.source_phrase),
    cleanTag(term.text),
    cleanTag(repairedText),
    normalizedTagKey(term.text) === 'mature man' ? 'mature male' : '',
  ]);
  const valid = [];
  for (const candidate of candidates) {
    if (!Number.isInteger(candidate.frameIndex) || !candidate.sourceId) continue;
    if (!rolePositions.has(`${candidate.frameIndex}\u001f${candidate.sourceId}`)) {
      continue;
    }
    const caption = sourceCaption(frames.get(candidate.frameIndex), candidate.sourceId);
    const tags = parseTags(caption).map(normalizedTagKey);
    if (!sourcePhrases.some((phrase) => tags.includes(normalizedTagKey(phrase)))) {
      continue;
    }
    valid.push(candidate);
  }
  return uniqueOccurrences(valid);
}

function addGenericBoyIdentity(cache, role, changes) {
  if (!/^role-(?:anonymous|muscular)/.test(stringValue(role.source_role_id))) {
    return;
  }
  const before = arrayValue(role.prompt_terms).length;
  addTermFromRoleSource(cache, role, 'boy', 'identity', ['boy']);
  if (arrayValue(role.prompt_terms).length > before) {
    changes.push(`added source-backed boy identity to ${role.source_role_id}`);
  }
}

function addScriptSpecificTermsAndFields(cache, changes) {
  const id = stringValue(cache.scriptId);
  const add = (roleId, text, category, phrases = [text], field = '', frames = []) => {
    const role = findRole(cache.aiRoleExtraction, roleId);
    if (!role) return;
    const before = arrayValue(role.prompt_terms).length;
    const term = addTermFromRoleSource(cache, role, text, category, phrases, frames);
    if (term && arrayValue(role.prompt_terms).length > before) {
      changes.push(`added ${roleId}:${text} as ${category}`);
    }
    if (term && field) {
      addFieldTermToIntersectingStages(role, field, text, term.frame_indexes);
    }
  };

  if (id === 'script-4-483f0d961dbafdcc') {
    add('role-saren-princess-connect', 'white cape', 'clothing', ['white cape'], 'upper_clothing');
    add('role-saren-princess-connect', 'night gown', 'clothing', ['night gown'], 'upper_clothing');
    add('role-saren-princess-connect', 'blue gemstone', 'accessory', ['blue gemstone'], 'upper_body');
    add('role-saren-princess-connect', 'wrist cuffs', 'accessory', ['wrist cuffs'], 'upper_body');
    add('role-saren-princess-connect', 'sundress', 'clothing', ['sundress'], 'upper_clothing');
    add('role-saren-princess-connect', 'adjusting clothes', 'clothingState', ['adjusting clothes']);
    add('role-saren-princess-connect', 'curvy', 'body', ['curvy'], 'upper_body');
    add('role-yuuki-princess-connect', 'blue cape', 'clothing', ['blue cape'], 'upper_clothing');
    add('role-suzume-princess-connect', 'blindfold', 'accessory', ['blindfold'], 'upper_body');
    add('role-suzume-princess-connect', 'black blindfold', 'accessory', ['black blindfold'], 'upper_body');
    add('role-suzume-princess-connect', 'unworn blindfold', 'accessory', ['unworn blindfold']);
    add('role-suzume-princess-connect', 'shortstack', 'body', ['shortstack'], 'upper_body');
    add('role-muscular-male', 'gyaruo', 'identity', ['gyaruo'], 'identity');
    add('role-anonymous-male', 'bald', 'body', ['bald'], 'upper_body');
    add('role-anonymous-male', 'ugly bastard', 'body', ['ugly bastard'], 'upper_body');
  }

  if (id === 'script-4d8a25fdbfe8f855') {
    add('role-saren-princess-connect', 'adjusting clothes', 'clothingState', ['adjusting clothes']);
    add('role-saren-princess-connect', 'curvy', 'body', ['curvy'], 'upper_body');
    add('role-muscular-male', 'gyaruo', 'identity', ['gyaruo'], 'identity');
  }

  if (id === 'script-d539a04e23fddcb6') {
    add('role-muscular-male', 'gyaruo', 'identity', ['gyaruo'], 'identity');
  }

  if (id === 'script-maki-camp-bbc-ntr-af6f4d2f59ae3d94') {
    add('role-marie-antoinette-fate', 'curvy', 'body', ['curvy'], 'upper_body');
    add('role-marie-antoinette-fate', 'underbutt', 'body', ['underbutt'], 'lower_body');
    add('role-maki-camp-blue-archive', 'curvy', 'body', ['curvy'], 'upper_body');
    add('role-maki-camp-blue-archive', 'underbutt', 'body', ['underbutt'], 'lower_body');
  }
}

function cleanStages(role, changes) {
  for (const stage of arrayValue(role.stages)) {
    for (const field of [
      'identity',
      'upper_body',
      'lower_body',
      'upper_clothing',
      'lower_clothing',
    ]) {
      const original = fieldTerms(stage[field]);
      const kept = [];
      for (let term of original) {
        const normalized = normalizedTagKey(term);
        if (INVALID_ROLE_TERMS.has(normalized)) continue;
        if (normalized === 'mature man') term = 'mature male';
        if (
          (field === 'upper_clothing' || field === 'lower_clothing') &&
          isFieldUnsafeClothingState(normalized)
        ) {
          continue;
        }
        if (field === 'upper_body' && normalized === 'male pubic hair') {
          appendFieldTerm(stage, 'lower_body', term);
          continue;
        }
        if (field === 'lower_body' && normalized === 'towel around waist') {
          continue;
        }
        kept.push(term);
      }
      stage[field] = uniqueStrings(kept).join(', ');
    }
    stage.warnings = [];
    refreshStage(stage);
  }
  const duplicateLabels = duplicateStageLabels(role.stages);
  if (duplicateLabels.length > 0) {
    changes.push(
      `role ${role.source_role_id} still has duplicate stage labels: ${duplicateLabels.join(', ')}`,
    );
  }
}

function applyStageLabels(cache, changes) {
  const id = stringValue(cache.scriptId);
  const set = (roleId, stageId, label) => {
    const role = findRole(cache.aiRoleExtraction, roleId);
    const stage = arrayValue(role?.stages).find((item) => item.stage_id === stageId);
    if (stage && stage.label !== label) {
      stage.label = label;
      stage.warnings = [];
      changes.push(`renamed ${roleId}/${stageId} to ${label}`);
    }
  };
  if (id === 'script-4-483f0d961dbafdcc') {
    set('role-saren-princess-connect', 'stage-9', '白色披风');
    set('role-kurumi-princess-connect', 'stage-8', '卧室外观');
    set('role-suzume-princess-connect', 'stage-2', '海滩草帽外观');
    set('role-muscular-male', 'stage-1', '白色短袖衬衫 / 黑色长裤');
    set('role-muscular-male', 'stage-2', '男性局部外观');
    set('role-muscular-male', 'stage-3', '白色短袖衬衫（下装未注明）');
    set('role-anonymous-male', 'stage-3', '男性局部外观');
  }
  if (id === 'script-4d8a25fdbfe8f855') {
    set('role-suzume-princess-connect', 'stage-2', '海滩草帽外观');
    set('role-muscular-male', 'stage-1', '白色短袖衬衫 / 黑色长裤');
    set('role-muscular-male', 'stage-2', '男性局部外观');
    set('role-muscular-male', 'stage-3', '白色短袖衬衫（下装未注明）');
  }
  if (id === 'script-d539a04e23fddcb6') {
    set('role-muscular-male', 'stage-1', '白色短袖衬衫（下装未注明）');
    set('role-muscular-male', 'stage-2', '白色短袖衬衫 / 黑色长裤');
    set('role-muscular-male', 'stage-5', '男性局部外观');
  }
  if (id === 'script-maki-camp-bbc-ntr-af6f4d2f59ae3d94') {
    set('role-maki-camp-blue-archive', 'stage-1', '露营外观');
  }
}

function buildSceneTerms(cache) {
  const terms = [];
  for (const frame of arrayValue(cache.scriptSnapshot?.frames)) {
    const frameIndex = Number(frame.index);
    if (!Number.isInteger(frameIndex)) continue;
    for (const rawTag of parseTags(frame.parsed?.baseCaption)) {
      const normalized = normalizedTagKey(rawTag);
      if (!SCENE_TERMS.has(normalized)) continue;
      const occurrence = { frameIndex, sourceId: 'base' };
      const existing = terms.find(
        (term) => normalizedTagKey(term.text) === normalized,
      );
      if (existing) {
        existing._occurrences.push(occurrence);
      } else {
        terms.push({ text: cleanTag(rawTag), category: 'scene', _occurrences: [occurrence] });
      }
    }
  }
  return terms
    .map((term) =>
      makeTerm('scene-ai', term.text, 'scene', uniqueOccurrences(term._occurrences)),
    )
    .sort(termSort);
}

function synchronizeMapping(cache) {
  const mapping = cache.mapping ?? {};
  mapping.id = `mapping-${cache.scriptId}`;
  mapping.scriptId = cache.scriptId;
  mapping.roleAssemblies = cache.aiRoleExtraction.roles.map((role) => ({
    sourceRoleId: role.source_role_id,
    displayLabel: role.display_name,
    sourceName: role.display_name,
    sourceAppearances: role.appearances.map((appearance) => ({
      sourceId: appearance.source_id,
      sourceKind: appearance.source_kind,
      frameIndexes: appearance.frame_indexes,
    })),
    stages: role.stages.map((stage) => ({
      id: stage.stage_id,
      label: stage.label,
      frameIndexes: stage.frame_indexes,
      sourceSummary: stage.evidence_terms.join(', '),
      sourceParts: sourceParts(stage),
    })),
  }));
  mapping.rolePromptReplacements = cache.aiRoleExtraction.roles
    .filter((role) => arrayValue(role.prompt_terms).length > 0)
    .map((role) => ({
      sourceRoleId: role.source_role_id,
      displayLabel: role.display_name,
      sourcePreview: role.prompt_terms.map((term) => term.text).join(', '),
      rules: role.prompt_terms.map((term) => ({
        id: `rule-${term.id}`,
        sourceTerms: [mappingTerm(term)],
      })),
    }));
  mapping.scenePromptReplacements = cache.aiRoleExtraction.scene_terms.length
    ? [
        {
          id: 'scene-ai',
          label: '场景',
          rules: cache.aiRoleExtraction.scene_terms.map((term) => ({
            id: `rule-${term.id}`,
            sourceTerms: [mappingTerm(term)],
          })),
        },
      ]
    : [];
  cache.mapping = mapping;
}

function finalizeRole(role) {
  normalizeAppearances(role);
  role.frame_indexes = uniqueInts(
    role.appearances.flatMap((appearance) => appearance.frame_indexes),
  );
  role.prompt_terms = arrayValue(role.prompt_terms)
    .filter((term) => arrayValue(term.source_occurrences).length > 0)
    .map((term) => {
      const occurrences = uniqueOccurrences(
        term.source_occurrences.map((occurrence) => ({
          frameIndex: Number(occurrence.frame_index),
          sourceId: sourceIdFromLocation(occurrence.source_location),
        })),
      );
      return makeTerm(
        role.source_role_id,
        term.text,
        contractCategory(term.category),
        occurrences,
      );
    })
    .sort(termSort);
  for (const stage of arrayValue(role.stages)) refreshStage(stage);
  role.evidence_terms = uniqueStrings(
    role.stages.flatMap((stage) => arrayValue(stage.evidence_terms)),
  );
  role.warnings = [];
  role.unassigned_terms = [];
}

function addTermFromRoleSource(
  cache,
  role,
  text,
  category,
  sourcePhrases,
  allowedFrames = [],
) {
  const frameByIndex = frameMap(cache);
  const allowed = new Set(uniqueInts(allowedFrames));
  const occurrences = [];
  for (const appearance of arrayValue(role.appearances)) {
    if (!stringValue(appearance.source_id).startsWith('slot-')) continue;
    for (const frameIndex of uniqueInts(appearance.frame_indexes)) {
      if (allowed.size > 0 && !allowed.has(frameIndex)) continue;
      const tags = parseTags(
        sourceCaption(frameByIndex.get(frameIndex), appearance.source_id),
      ).map(normalizedTagKey);
      if (!sourcePhrases.some((phrase) => tags.includes(normalizedTagKey(phrase)))) {
        continue;
      }
      occurrences.push({ frameIndex, sourceId: appearance.source_id });
    }
  }
  if (occurrences.length === 0) return null;
  const term = makeTerm(role.source_role_id, text, category, occurrences);
  role.prompt_terms = arrayValue(role.prompt_terms);
  return mergeTerm(role.prompt_terms, term);
}

function makeTerm(ownerId, text, category, rawOccurrences) {
  const occurrences = uniqueOccurrences(rawOccurrences);
  const locations = uniqueStrings(
    occurrences.map((occurrence) => `${occurrence.sourceId} prompt`),
  );
  return {
    id: `role-${safeId(ownerId)}-${category}-${safeId(text)}`,
    text: cleanTag(text),
    category: contractCategory(category),
    source_phrase: cleanTag(text),
    source_location: locations.join('; '),
    frame_indexes: uniqueInts(occurrences.map((occurrence) => occurrence.frameIndex)),
    source_occurrences: occurrences.map((occurrence) => ({
      frame_index: occurrence.frameIndex,
      source_location: `${occurrence.sourceId} prompt`,
    })),
  };
}

function mergeTerm(terms, incoming) {
  const key = `${incoming.category}\u001f${normalizedTagKey(incoming.text)}`;
  const existing = terms.find(
    (term) =>
      `${contractCategory(term.category)}\u001f${normalizedTagKey(term.text)}` === key,
  );
  if (!existing) {
    terms.push(incoming);
    return incoming;
  }
  const occurrences = uniqueOccurrences([
    ...arrayValue(existing.source_occurrences).map((occurrence) => ({
      frameIndex: Number(occurrence.frame_index),
      sourceId: sourceIdFromLocation(occurrence.source_location),
    })),
    ...arrayValue(incoming.source_occurrences).map((occurrence) => ({
      frameIndex: Number(occurrence.frame_index),
      sourceId: sourceIdFromLocation(occurrence.source_location),
    })),
  ]);
  Object.assign(
    existing,
    makeTerm('merged', existing.text, existing.category, occurrences),
    { id: incoming.id },
  );
  return existing;
}

function makeStage({
  id,
  label,
  frames,
  identity = '',
  upperBody = '',
  lowerBody = '',
  upperClothing = '',
  lowerClothing = '',
}) {
  const stage = {
    stage_id: id,
    label,
    appearance_group_id: id.replace(/^stage-/, 'appearance-'),
    merge_with_stage_ids: [],
    field_reasons: {},
    confidence: 0.72,
    frame_indexes: uniqueInts(frames),
    identity,
    upper_body: upperBody,
    lower_body: lowerBody,
    upper_clothing: upperClothing,
    lower_clothing: lowerClothing,
    evidence_terms: [],
    missing_fields: [],
    warnings: [],
  };
  refreshStage(stage);
  return stage;
}

function refreshStage(stage) {
  stage.frame_indexes = uniqueInts(stage.frame_indexes);
  for (const field of [
    'identity',
    'upper_body',
    'lower_body',
    'upper_clothing',
    'lower_clothing',
  ]) {
    stage[field] = uniqueStrings(fieldTerms(stage[field])).join(', ');
  }
  stage.evidence_terms = uniqueStrings([
    ...fieldTerms(stage.identity),
    ...fieldTerms(stage.upper_body),
    ...fieldTerms(stage.lower_body),
    ...fieldTerms(stage.upper_clothing),
    ...fieldTerms(stage.lower_clothing),
  ]);
  stage.missing_fields = [
    ['identity', 'missing_identity'],
    ['upper_body', 'missing_upper_body'],
    ['lower_body', 'missing_lower_body'],
    ['upper_clothing', 'missing_upper_clothing'],
    ['lower_clothing', 'missing_lower_clothing'],
  ]
    .filter(([field]) => !stringValue(stage[field]).trim())
    .map(([, issue]) => issue);
  stage.warnings = [];
}

function addFieldTermToIntersectingStages(role, field, term, frames) {
  const evidenceFrames = new Set(uniqueInts(frames));
  for (const stage of arrayValue(role.stages)) {
    if (!uniqueInts(stage.frame_indexes).some((frame) => evidenceFrames.has(frame))) {
      continue;
    }
    appendFieldTerm(stage, field, term);
    refreshStage(stage);
  }
}

function appendFieldTerm(stage, field, term) {
  stage[field] = uniqueStrings([...fieldTerms(stage[field]), term]).join(', ');
}

function isFieldUnsafeClothingState(normalized) {
  return (
    CLOTHING_STATE_TERMS.has(normalized) ||
    /\b(?:aside|lift|pulled|pull|torn|ripped|wet|stained|unworn|around one leg|open jacket|open clothes|no bra|no panties|no gloves|see through|see-through)\b/.test(
      normalized,
    )
  );
}

function deleteRole(extraction, roleId, changes) {
  const before = extraction.roles.length;
  extraction.roles = extraction.roles.filter(
    (role) => role.source_role_id !== roleId,
  );
  if (extraction.roles.length !== before) changes.push(`deleted ${roleId}`);
}

function setNoRolePartial(extraction, item) {
  extraction.attention_items = extraction.attention_items.filter(
    (entry) => entry.id !== item.id,
  );
  extraction.attention_items.push({
    id: item.id,
    kind: 'no_role_partial',
    source_id: item.source_id,
    frame_indexes: item.frame_indexes,
    evidence: item.evidence,
    message: item.message,
    blocking: false,
  });
}

function addAppearanceFrames(role, sourceId, frames, changes) {
  if (!role) return;
  let appearance = arrayValue(role.appearances).find(
    (item) => item.source_id === sourceId,
  );
  if (!appearance) {
    appearance = { source_id: sourceId, source_kind: 'slot', frame_indexes: [] };
    role.appearances.push(appearance);
  }
  const before = JSON.stringify(appearance.frame_indexes);
  appearance.frame_indexes = uniqueInts([...appearance.frame_indexes, ...frames]);
  if (before !== JSON.stringify(appearance.frame_indexes)) {
    changes.push(`added ${sourceId} frames ${frames.join(',')} to ${role.source_role_id}`);
  }
}

function addStageFrames(role, stageId, frames, changes) {
  const stage = arrayValue(role?.stages).find((item) => item.stage_id === stageId);
  if (!stage) return;
  const before = JSON.stringify(stage.frame_indexes);
  stage.frame_indexes = uniqueInts([...stage.frame_indexes, ...frames]);
  if (before !== JSON.stringify(stage.frame_indexes)) {
    changes.push(`added frames ${frames.join(',')} to ${role.source_role_id}/${stageId}`);
  }
}

function normalizeAppearances(role) {
  role.appearances = mergeAppearances(arrayValue(role.appearances));
}

function mergeAppearances(appearances) {
  const bySource = new Map();
  for (const appearance of appearances) {
    const sourceId = stringValue(appearance.source_id);
    if (!sourceId) continue;
    const current = bySource.get(sourceId) ?? {
      source_id: sourceId,
      source_kind: stringValue(appearance.source_kind) || 'slot',
      frame_indexes: [],
    };
    current.frame_indexes.push(...uniqueInts(appearance.frame_indexes));
    bySource.set(sourceId, current);
  }
  return [...bySource.values()]
    .map((appearance) => ({
      ...appearance,
      frame_indexes: uniqueInts(appearance.frame_indexes),
    }))
    .sort((left, right) => left.source_id.localeCompare(right.source_id));
}

function buildSceneMappingSignature(cache) {
  return arrayValue(cache.aiRoleExtraction?.scene_terms)
    .map((term) => `${term.id}\u001f${term.text}\u001f${term.category}`)
    .sort();
}

function mappingTerm(term) {
  return {
    id: term.id,
    text: term.text,
    category: term.category,
    sourcePhrase: term.source_phrase,
    sourceLocation: term.source_location,
    frameIndexes: term.frame_indexes,
    sourceOccurrences: arrayValue(term.source_occurrences).map((occurrence) => ({
      frameIndex: occurrence.frame_index,
      sourceLocation: occurrence.source_location,
    })),
  };
}

function sourceParts(stage) {
  const result = {};
  if (stage.identity) result.identity = stage.identity;
  if (stage.upper_body) result.upperBody = stage.upper_body;
  if (stage.lower_body) result.lowerBody = stage.lower_body;
  if (stage.upper_clothing) result.upperClothing = stage.upper_clothing;
  if (stage.lower_clothing) result.lowerClothing = stage.lower_clothing;
  return result;
}

function stats(cache) {
  const roles = arrayValue(cache.aiRoleExtraction?.roles);
  const roleGroups = arrayValue(cache.mapping?.rolePromptReplacements);
  const sceneGroups = arrayValue(cache.mapping?.scenePromptReplacements);
  return {
    roles: roles.length,
    stages: roles.reduce((count, role) => count + arrayValue(role.stages).length, 0),
    role_prompt_terms: roles.reduce(
      (count, role) => count + arrayValue(role.prompt_terms).length,
      0,
    ),
    scene_terms: arrayValue(cache.aiRoleExtraction?.scene_terms).length,
    role_mapping_groups: roleGroups.length,
    role_mapping_rules: roleGroups.reduce(
      (count, group) => count + arrayValue(group.rules).length,
      0,
    ),
    scene_mapping_groups: sceneGroups.length,
    scene_mapping_rules: sceneGroups.reduce(
      (count, group) => count + arrayValue(group.rules).length,
      0,
    ),
  };
}

function accumulate(report, before, after) {
  report.roles_before += before.roles;
  report.roles_after += after.roles;
  report.stages_before += before.stages;
  report.stages_after += after.stages;
  report.role_prompt_terms_before += before.role_prompt_terms;
  report.role_prompt_terms_after += after.role_prompt_terms;
  report.scene_terms_before += before.scene_terms;
  report.scene_terms_after += after.scene_terms;
  report.role_mapping_groups_after += after.role_mapping_groups;
  report.role_mapping_rules_after += after.role_mapping_rules;
  report.scene_mapping_groups_after += after.scene_mapping_groups;
  report.scene_mapping_rules_after += after.scene_mapping_rules;
}

function findRole(extraction, roleId) {
  return arrayValue(extraction?.roles).find(
    (role) => role.source_role_id === roleId,
  );
}

function appearanceFrames(role, sourceId) {
  return uniqueInts(
    arrayValue(role?.appearances)
      .filter((appearance) => appearance.source_id === sourceId)
      .flatMap((appearance) => appearance.frame_indexes),
  );
}

function frameMap(cache) {
  return new Map(
    arrayValue(cache.scriptSnapshot?.frames).map((frame) => [Number(frame.index), frame]),
  );
}

function rolePositionSet(role) {
  const result = new Set();
  for (const appearance of arrayValue(role.appearances)) {
    for (const frameIndex of uniqueInts(appearance.frame_indexes)) {
      result.add(`${frameIndex}\u001f${appearance.source_id}`);
    }
  }
  return result;
}

function sourceCaption(frame, sourceId) {
  if (!frame) return '';
  if (sourceId === 'base') return stringValue(frame.parsed?.baseCaption);
  const match = /^slot-(\d+)$/.exec(sourceId);
  if (!match) return '';
  return stringValue(arrayValue(frame.parsed?.charCaptions)[Number(match[1])]);
}

function sourceIdFromLocation(location) {
  const match = /^(base|slot-\d+) prompt/.exec(stringValue(location));
  return match?.[1] ?? '';
}

function parseTags(value) {
  return stringValue(value)
    .replace(/\r?\n/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  let changed = true;
  while (changed) {
    const next = text.replace(/^[+]?\d+(?:\.\d+)?::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  return text
    .replace(/::+$/g, '')
    .replace(/^[{}\[\]]+|[{}\[\]]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizedTagKey(value) {
  return cleanTag(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function contractCategory(value) {
  const category = stringValue(value);
  if (category === 'character' || category === 'identity') return 'identity';
  if (['upperBody', 'lowerBody', 'body'].includes(category)) return 'body';
  if (['upperClothing', 'lowerClothing', 'clothing'].includes(category)) {
    return 'clothing';
  }
  if (category === 'clothing_state' || category === 'clothingState') {
    return 'clothingState';
  }
  if (category === 'accessory' || category === 'scene') return category;
  return '';
}

function uniqueOccurrences(values) {
  const byKey = new Map();
  for (const value of values) {
    const frameIndex = Number(value.frameIndex);
    const sourceId = stringValue(value.sourceId);
    if (!Number.isInteger(frameIndex) || !sourceId) continue;
    byKey.set(`${frameIndex}\u001f${sourceId}`, { frameIndex, sourceId });
  }
  return [...byKey.values()].sort(
    (left, right) =>
      left.frameIndex - right.frameIndex || left.sourceId.localeCompare(right.sourceId),
  );
}

function uniqueInts(values) {
  return [...new Set(arrayValue(values).map(Number).filter(Number.isInteger))].sort(
    (left, right) => left - right,
  );
}

function uniqueStrings(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const text = cleanTag(value);
    const key = normalizedTagKey(text);
    if (!text || !key || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function fieldTerms(value) {
  return stringValue(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function duplicateStageLabels(stages) {
  const counts = new Map();
  for (const stage of arrayValue(stages)) {
    const label = stringValue(stage.label).trim();
    if (!label) continue;
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts].filter(([, count]) => count > 1).map(([label]) => label);
}

function termSort(left, right) {
  return (
    stringValue(left.category).localeCompare(stringValue(right.category)) ||
    normalizedTagKey(left.text).localeCompare(normalizedTagKey(right.text))
  );
}

function safeId(value) {
  return normalizedTagKey(value).replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'term';
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function setValue(object, key, value, changes) {
  if (object[key] === value) return;
  object[key] = value;
  changes.push(`set ${object.source_role_id ?? 'object'}.${key}`);
}

function parseArgs(values) {
  const result = { apply: false };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (arg === '--apply') {
      result.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    result[key] = values[index + 1];
    index += 1;
  }
  return result;
}
