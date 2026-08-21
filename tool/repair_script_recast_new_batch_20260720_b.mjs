#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const TARGET_IDS = [
  'script-2-db8e8408f5c5a47b',
  'script-2-e55e317517d0fe4b',
  'script-ako-dress-bbc-ntr-3ad4bf46dce6774e',
  'script-reisa-magical-defeat-3277fc501f49a035',
];

const options = parseArgs(process.argv.slice(2));
if (options.help) {
  printHelp();
  process.exit(0);
}
if (!options.cacheDir) throw new Error('Missing required --cache-dir <dir>.');

const cacheDir = path.resolve(options.cacheDir);
const reportPath = options.report ? path.resolve(options.report) : null;
const backupDir = path.resolve(
  options.backupDir ?? `${cacheDir}_backup_before_new_batch_20260720_b`,
);
if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);

const report = {
  tool: 'repair_script_recast_new_batch_20260720_b',
  api_used: false,
  cache_dir: cacheDir,
  apply: options.apply,
  backup_dir: options.apply ? backupDir : null,
  target_script_ids: TARGET_IDS,
  files_scanned: 0,
  files_changed: 0,
  role_count_before: 0,
  role_count_after: 0,
  stage_count_before: 0,
  stage_count_after: 0,
  role_prompt_term_count_before: 0,
  role_prompt_term_count_after: 0,
  scene_term_count_before: 0,
  scene_term_count_after: 0,
  role_mapping_rule_count_after: 0,
  scene_mapping_rule_count_after: 0,
  strict_uncovered_slot_count: 0,
  allowed_no_role_partial_count: 0,
  quality_issue_count: 0,
  rows: [],
};

for (const scriptId of TARGET_IDS) {
  const fileName = `${scriptId}.json`;
  const filePath = path.join(cacheDir, fileName);
  if (!fs.existsSync(filePath)) throw new Error(`Missing target cache: ${filePath}`);
  const cache = loadJson(filePath);
  report.files_scanned += 1;
  const before = JSON.stringify(cache);
  const beforeCounts = cacheCounts(cache);
  const next = repairCache(cache);
  const audit = auditCache(next);
  const after = JSON.stringify(next);
  const changed = before !== after;

  report.role_count_before += beforeCounts.roleCount;
  report.role_count_after += audit.counts.roleCount;
  report.stage_count_before += beforeCounts.stageCount;
  report.stage_count_after += audit.counts.stageCount;
  report.role_prompt_term_count_before += beforeCounts.rolePromptTermCount;
  report.role_prompt_term_count_after += audit.counts.rolePromptTermCount;
  report.scene_term_count_before += beforeCounts.sceneTermCount;
  report.scene_term_count_after += audit.counts.sceneTermCount;
  report.role_mapping_rule_count_after += audit.counts.roleMappingRuleCount;
  report.scene_mapping_rule_count_after += audit.counts.sceneMappingRuleCount;
  report.strict_uncovered_slot_count += audit.strictCoverage.uncovered.length;
  report.allowed_no_role_partial_count += audit.strictCoverage.allowed.length;
  report.quality_issue_count += audit.issues.length;
  if (changed) report.files_changed += 1;

  report.rows.push({
    file_name: fileName,
    script_id: scriptId,
    changed,
    before: beforeCounts,
    after: audit.counts,
    strict_slot_coverage: audit.strictCoverage,
    issues: audit.issues,
    roles: audit.roles,
  });

  if (options.apply && audit.issues.length === 0 && changed) {
    fs.mkdirSync(backupDir, { recursive: true });
    const backupPath = path.join(backupDir, fileName);
    if (!fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
    next.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
  }
}

if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));

if (report.quality_issue_count > 0) {
  if (options.apply) {
    throw new Error(
      `Refusing partial apply: ${report.quality_issue_count} quality issue(s) remain.`,
    );
  }
  process.exitCode = 2;
}

function repairCache(cache) {
  const next = structuredClone(cache);
  const allCandidateTerms = collectCandidateTerms(next);
  if (cache.scriptId === 'script-2-db8e8408f5c5a47b') {
    repairToki(next);
  } else if (cache.scriptId === 'script-2-e55e317517d0fe4b') {
    repairCitlali(next);
  } else if (cache.scriptId === 'script-ako-dress-bbc-ntr-3ad4bf46dce6774e') {
    repairAko(next);
  } else if (cache.scriptId === 'script-reisa-magical-defeat-3277fc501f49a035') {
    repairReisa(next);
  } else {
    throw new Error(`Unsupported script: ${cache.scriptId}`);
  }

  for (const role of next.aiRoleExtraction.roles) {
    normalizeRole(role, next);
    role.prompt_terms = buildRolePromptTerms(
      next,
      role,
      allCandidateTerms,
      extraTermsForRole(next.scriptId, role.source_role_id),
    );
  }
  next.aiRoleExtraction.scene_terms = buildSceneTerms(
    next,
    scenePlanForScript(next.scriptId),
  );
  next.aiRoleExtraction.status = 'ready';
  next.aiRoleExtraction.attention_items = [];
  next.aiRoleExtraction.unassigned_terms = [];
  next.aiRoleExtraction.evidence_requests = [];
  next.aiRoleExtractionChunks = [];
  syncMapping(next);
  return next;
}

function repairToki(cache) {
  const roles = roleMap(cache);
  const toki = requiredRole(roles, 'role-toki-bunny-blue-archive');
  const male = requiredRole(roles, 'role-muscular-male');
  const asuna = requiredRole(roles, 'role-asuna-blue-archive');
  const sensei = requiredRole(roles, 'role-sensei-blue-archive-the-animation');

  toki.display_name = 'toki (bunny) (blue archive) / 时（兔女郎，碧蓝档案）';
  patchStage(toki, 'stage-1', {
    lower_body: removeTerms(stageById(toki, 'stage-1').lower_body, ['legs together']),
  });
  patchStage(toki, 'stage-2', {
    upper_body: removeTerms(stageById(toki, 'stage-2').upper_body, ['messy hair']),
  });
  patchStage(toki, 'stage-3', {
    upper_body: removeTerms(stageById(toki, 'stage-3').upper_body, ['messy hair']),
  });
  patchStage(toki, 'stage-4', {
    upper_body: removeTerms(stageById(toki, 'stage-4').upper_body, ['bare shoulders']),
  });

  setAppearances(male, [
    { sourceId: 'slot-0', frames: appearanceFrames(male, 'slot-0') },
    {
      sourceId: 'slot-1',
      frames: uniqueSorted([
        ...appearanceFrames(male, 'slot-1'),
        18,
        19,
        20,
        21,
        22,
        76,
      ]),
    },
    { sourceId: 'slot-2', frames: appearanceFrames(male, 'slot-2') },
  ]);
  patchStage(male, 'stage-2', { upper_body: '' });
  patchStage(male, 'stage-3', {
    frame_indexes: uniqueSorted([...stageById(male, 'stage-3').frame_indexes, 76]),
  });
  patchStage(male, 'stage-4', {
    label: '酒店房间浴巾',
    identity: replaceTerm(stageById(male, 'stage-4').identity, 'mature man', 'mature male'),
    upper_clothing: removeTerms(stageById(male, 'stage-4').upper_clothing, ['naked towel']),
  });
  patchStage(male, 'stage-5', { label: '酒店房间（服装未标注）' });
  const barStage = makeStage({
    id: 'stage-6',
    label: '酒吧局部入镜（服装未标注）',
    frames: [18, 19, 20, 21, 22],
    identity: 'boy',
  });
  const barStageIndex = male.stages.findIndex(
    (stage) => (stage.stage_id ?? stage.id) === 'stage-6',
  );
  if (barStageIndex >= 0) male.stages[barStageIndex] = barStage;
  else male.stages.push(barStage);

  asuna.display_name = 'asuna (blue archive) / 明日奈（碧蓝档案）';
  patchStage(asuna, 'stage-1', {
    label: '校服 / 白衬衫 / 黑色裙子',
  });
  patchStage(asuna, 'stage-4', {
    upper_body: removeTerms(stageById(asuna, 'stage-4').upper_body, ['bare shoulders']),
    lower_body: removeTerms(stageById(asuna, 'stage-4').lower_body, ['bare legs']),
    upper_clothing: removeTerms(stageById(asuna, 'stage-4').upper_clothing, ['no bra']),
    lower_clothing: removeTerms(stageById(asuna, 'stage-4').lower_clothing, [
      'panties only',
      'underwear only',
    ]),
  });
  patchStage(asuna, 'stage-5', {
    label: '校服 / 白衬衫 / 黑色裙子 / 无裆内裤',
  });
  patchStage(asuna, 'stage-7', {
    upper_body: removeTerms(stageById(asuna, 'stage-7').upper_body, ['bare shoulders']),
    lower_clothing: removeTerms(stageById(asuna, 'stage-7').lower_clothing, ['no panties']),
  });
  patchStage(asuna, 'stage-8', {
    upper_body: removeTerms(stageById(asuna, 'stage-8').upper_body, ['bare shoulders']),
  });

  patchStage(sensei, 'stage-3', { lower_body: '' });
  cache.aiRoleExtraction.roles = [toki, male, asuna, sensei];
}

function repairCitlali(cache) {
  const roles = roleMap(cache);
  const aether = requiredRole(roles, 'role-aether-genshin-impact');
  const citlali = requiredRole(roles, 'role-citlali-genshin-impact');
  const male = requiredRole(roles, 'role-muscular-male');

  aether.display_name = 'aether (genshin_impact) / 空（原神）';
  for (const stage of aether.stages) {
    stage.identity = canonicalizeCommaTerms(stage.identity, {
      'aether_(genshin_impact)': 'aether (genshin_impact)',
    });
  }

  patchStage(citlali, 'stage-1', {
    upper_body: removeTerms(stageById(citlali, 'stage-1').upper_body, [
      'bare shoulders',
      'avertising eyes',
    ]),
    upper_clothing: removeTerms(stageById(citlali, 'stage-1').upper_clothing, ['no gloves']),
  });
  patchStage(citlali, 'stage-2', {
    upper_body: removeTerms(stageById(citlali, 'stage-2').upper_body, ['bare shoulders']),
  });
  patchStage(citlali, 'stage-4', {
    lower_clothing: removeTerms(stageById(citlali, 'stage-4').lower_clothing, [
      'panties vieible through clothes',
    ]),
  });
  patchStage(citlali, 'stage-6', { label: '灰色连衣裙 / 裙装掀起' });
  patchStage(citlali, 'stage-9', {
    upper_body: removeTerms(stageById(citlali, 'stage-9').upper_body, ['avertising eyes']),
  });
  patchStage(citlali, 'stage-10', {
    lower_body: removeTerms(stageById(citlali, 'stage-10').lower_body, ['leg up']),
  });

  patchStage(male, 'stage-1', {
    identity: replaceTerm(stageById(male, 'stage-1').identity, 'mature man', 'mature male'),
  });
  patchStage(male, 'stage-2', {
    label: '酒店房间局部入镜（服装未标注）',
    lower_body: '',
  });
  cache.aiRoleExtraction.roles = [aether, citlali, male];
}

function repairAko(cache) {
  const roles = roleMap(cache);
  const ako = requiredRole(roles, 'role-ako-dress-blue-archive');
  const oldSensei = requiredRole(roles, 'role-sensei-blue-archive-the-animation');
  const oldAnonymous =
    roles.get('role-anonymous-male') ??
    requiredRole(roles, 'role-dark-skinned-male-slot-1');

  ako.display_name = 'ako (dress) (blue archive) / 亚子（礼服，碧蓝档案）';
  setAppearances(ako, [{ sourceId: 'slot-0', frames: intRange(1, 93) }]);
  ako.stages = akoStages();

  const sensei = roleFrom(oldSensei, {
    id: 'role-sensei-blue-archive-the-animation',
    display: 'sensei (blue archive the animation) / 老师（碧蓝档案动画）',
    canonical: 'sensei',
    franchise: 'blue archive the animation',
    appearances: [
      { sourceId: 'slot-1', frames: [5, 6, 7, 8, 83, 85] },
      { sourceId: 'slot-2', frames: [86, 87] },
    ],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '燕尾服',
        frames: [7, 8, 83, 85],
        identity: 'sensei (blue archive the animation), boy',
        upperClothing: 'tuxedo',
      }),
      makeStage({
        id: 'stage-2',
        label: '第一视角（服装未标注）',
        frames: [5, 6, 86, 87],
        identity: 'sensei (blue archive the animation), boy',
      }),
    ],
  });

  const male1Frames = [
    11, 12, 13, 14, 15, 16, 18, 19, 20, 21, 22, 47, 48, 49, 50, 51,
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67,
    68, 69, 70, 71, 72, 73, 74, 86, 87, 88, 89, 90, 91, 92, 93,
  ];
  const male1 = roleFrom(oldAnonymous, {
    id: 'role-dark-skinned-male-slot-1',
    display: 'dark-skinned male / 深色皮肤男性甲',
    appearances: [{ sourceId: 'slot-1', frames: male1Frames }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '深色皮肤男性甲（服装未标注）',
        frames: male1Frames,
        identity: 'boy',
        upperBody: 'very dark skin',
      }),
    ],
  });
  const male2 = roleFrom(oldAnonymous, {
    id: 'role-dark-skinned-male-slot-2',
    display: 'dark-skinned male / 深色皮肤男性乙',
    appearances: [{ sourceId: 'slot-2', frames: [70, 71, 72] }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '深色皮肤男性乙（服装未标注）',
        frames: [70, 71, 72],
        upperBody: 'very dark skin',
      }),
    ],
  });
  const whiteBoy = roleFrom(oldAnonymous, {
    id: 'role-white-skinned-boy-slot-2',
    display: 'white-skinned boy / 白皮肤男孩',
    appearances: [{ sourceId: 'slot-2', frames: [88, 89, 90, 91, 92, 93] }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '白皮肤男孩（服装未标注）',
        frames: [88, 89, 90, 91, 92, 93],
        identity: 'white-skinned boy',
      }),
    ],
  });
  cache.aiRoleExtraction.roles = [ako, sensei, male1, male2, whiteBoy];
}

function repairReisa(cache) {
  const roles = roleMap(cache);
  const reisa = requiredRole(roles, 'role-reisa-blue-archive');
  const anonymous =
    roles.get('role-anonymous-male') ?? requiredRole(roles, 'role-fat-man-slot-1');

  reisa.display_name = 'reisa (blue archive) / 玲纱（碧蓝档案）';
  reisa.stages = [
    makeStage({
      id: 'stage-1',
      label: '街头魔法少女装',
      frames: [1, 2, 3, 4, 5, 6, 7, 12],
      identity: 'reisa (blue archive), girl, magical girl',
      upperBody: 'high twintails',
      upperClothing: 'alternate costume',
    }),
    makeStage({
      id: 'stage-2',
      label: '魔法少女装 / 连裤袜',
      frames: [8],
      identity: 'reisa (blue archive), girl, magical girl',
      upperBody: 'high twintails',
      upperClothing: 'alternate costume',
      lowerClothing: 'pantyhose',
    }),
    makeStage({
      id: 'stage-3',
      label: '魔法少女装 / 条纹破损连裤袜',
      frames: [9, 10, 11],
      identity: 'reisa (blue archive), girl, magical girl',
      upperBody: 'high twintails',
      lowerBody: 'thick thighs, wide hips',
      upperClothing: 'alternate costume',
      lowerClothing: 'striped pantyhose',
    }),
    makeStage({
      id: 'stage-4',
      label: '街头裸体',
      frames: intRange(13, 59),
      identity: 'reisa (blue archive), girl, magical girl',
      upperBody: 'twintails, medium breasts',
      lowerBody: 'thick thighs, wide hips',
    }),
  ];

  const fat1Frames = [
    28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
    44, 45, 46, 47, 48, 49, 50, 51, 54, 55, 56, 57,
  ];
  const fat2Frames = [
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 44, 45, 46,
    47, 48, 49,
  ];
  const fat1 = roleFrom(anonymous, {
    id: 'role-fat-man-slot-1',
    display: 'fat man / 胖男人甲',
    appearances: [{ sourceId: 'slot-1', frames: fat1Frames }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '街头胖男人甲（服装未标注）',
        frames: fat1Frames,
        identity: 'fat man, boy',
        upperBody: 'very dark skin',
      }),
    ],
  });
  const fat2 = roleFrom(anonymous, {
    id: 'role-fat-man-slot-2',
    display: 'fat man / 胖男人乙',
    appearances: [{ sourceId: 'slot-2', frames: fat2Frames }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '街头胖男人乙（服装未标注）',
        frames: fat2Frames,
        identity: 'fat man, boy',
        upperBody: 'very dark skin',
      }),
    ],
  });
  const dark = roleFrom(anonymous, {
    id: 'role-dark-skinned-male-slot-2',
    display: 'dark-skinned male / 深色皮肤男性（第二槽位）',
    appearances: [{ sourceId: 'slot-2', frames: [57] }],
    stages: [
      makeStage({
        id: 'stage-1',
        label: '巷口深色皮肤男性（服装未标注）',
        frames: [57],
        identity: 'boy',
        upperBody: 'very dark skin',
      }),
    ],
  });
  cache.aiRoleExtraction.roles = [reisa, fat1, fat2, dark];
}

function akoStages() {
  return [
    makeStage({
      id: 'stage-1',
      label: '服装敞开',
      frames: [1, 23, 24, 25, 26, 27, 28, 29, 30, 31, 87, 88, 89, 90, 91, 92, 93],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
    }),
    makeStage({
      id: 'stage-2',
      label: '服装移位',
      frames: [17],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
    }),
    makeStage({
      id: 'stage-3',
      label: '服装掀起',
      frames: [82],
      identity: 'ako (dress) (blue archive), girl',
      lowerBody: 'wide hips',
    }),
    makeStage({
      id: 'stage-4',
      label: '服装未标注',
      frames: [2, 3, 4, 80, 81],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
    }),
    makeStage({
      id: 'stage-5',
      label: '透视连衣裙',
      frames: [5, 6, 7, 8, 11, 15, 16, 18, 83, 84, 85, 86],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
      upperClothing: 'see-through dress',
    }),
    makeStage({
      id: 'stage-6',
      label: '透视连衣裙 / 服装移位',
      frames: [19],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
      upperClothing: 'see-through dress',
    }),
    makeStage({
      id: 'stage-7',
      label: '无内裤 / 透视连衣裙',
      frames: [9, 10, 12, 13, 14],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
      upperClothing: 'see-through dress',
    }),
    makeStage({
      id: 'stage-8',
      label: '透视连衣裙 / 连衣裙掀起',
      frames: [20],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'wide hips',
      upperClothing: 'see-through dress',
    }),
    makeStage({
      id: 'stage-9',
      label: '连衣裙掀起 / 服装敞开',
      frames: [21, 22, ...intRange(32, 74)],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips, navel, stomach',
    }),
    makeStage({
      id: 'stage-10',
      label: '无内裤 / 服装移位',
      frames: [75, 76, 77, 78, 79],
      identity: 'ako (dress) (blue archive), girl',
      upperBody: 'huge breasts',
      lowerBody: 'thick thighs, wide hips',
    }),
  ];
}

function collectCandidateTerms(cache) {
  const terms = [];
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    for (const term of role.prompt_terms ?? []) {
      terms.push({ text: term.text, category: term.category });
    }
  }
  return terms;
}

function extraTermsForRole(scriptId, roleId) {
  const common = [
    term('girl', 'identity'),
    term('boy', 'identity'),
    term('curvy', 'body'),
    term('bald', 'body'),
    term('triangle facial mark', 'body'),
    term('facial mark', 'body'),
    term('floating headgear', 'accessory'),
    term('twin drills', 'body'),
    term('alternate hairstyle', 'body'),
    term('magical girl', 'identity'),
    term('white scarf', 'accessory'),
    term('id card', 'accessory'),
    term('black necktie', 'clothing'),
    term('tuxedo', 'clothing'),
    term('untied necktie', 'accessory'),
    term('chastity_cage', 'accessory'),
    term('gyaruo', 'identity'),
    term('muscular', 'body'),
    term('large veiny penis', 'body'),
    term('large black penis', 'body'),
    term('large black veiny penis', 'body'),
    term('erection under clothes', 'clothingState'),
    term('presenting_removed_panties', 'clothingState'),
    term("adjusting another's clothes", 'clothingState'),
    term('cum on clothes', 'clothingState'),
  ];
  if (scriptId === 'script-reisa-magical-defeat-3277fc501f49a035') {
    common.push(term('alternate costume', 'clothing'));
  }
  if (roleId === 'role-white-skinned-boy-slot-2') {
    common.push(term('white-skinned boy', 'identity'));
  }
  return common;
}

function buildRolePromptTerms(cache, role, candidates, extras) {
  const merged = new Map();
  for (const candidate of [...candidates, ...extras]) {
    const canonical = canonicalPromptTerm(candidate.text);
    const category = categoryForPromptTerm(canonical.text, candidate.category);
    if (!category || isPromptLeak(canonical.text)) continue;
    const key = `${category}\u001f${normalizeTag(canonical.text)}`;
    if (!merged.has(key)) {
      merged.set(key, {
        text: canonical.text,
        category,
        aliases: new Set(canonical.aliases),
      });
    } else {
      for (const alias of canonical.aliases) merged.get(key).aliases.add(alias);
    }
  }

  const result = [];
  for (const candidate of merged.values()) {
    const evidence = roleTermEvidence(cache, role, [...candidate.aliases]);
    if (evidence.occurrences.length === 0) continue;
    result.push({
      id: `role-${safeId(role.source_role_id)}-${candidate.category}-${safeId(candidate.text)}`,
      text: candidate.text,
      category: candidate.category,
      source_phrase: evidence.phrases[0],
      source_location: evidence.locations.join('; '),
      frame_indexes: uniqueSorted(evidence.occurrences.map((item) => item.frame_index)),
      source_occurrences: evidence.occurrences,
    });
  }
  return result.sort(compareTerms);
}

function canonicalPromptTerm(textValue) {
  const text = stringValue(textValue).trim();
  const normalized = normalizeTag(text);
  const aliases = [text];
  if (normalized === normalizeTag('deated collar') || normalized === normalizeTag('detached collar')) {
    return { text: 'detached collar', aliases: ['deated collar', 'detached collar'] };
  }
  if (normalized === normalizeTag('leotard aisde') || normalized === normalizeTag('leotard aside')) {
    return { text: 'leotard aside', aliases: ['leotard aisde', 'leotard aside'] };
  }
  if (
    normalized === normalizeTag('aether_(genshin_impact)') ||
    normalized === normalizeTag('aether (genshin_impact)')
  ) {
    return {
      text: 'aether (genshin_impact)',
      aliases: ['aether_(genshin_impact)', 'aether (genshin_impact)'],
    };
  }
  if (
    normalized === normalizeTag('ako (dress) ( blue archive)') ||
    normalized === normalizeTag('ako (dress) (blue archive)')
  ) {
    return {
      text: 'ako (dress) (blue archive)',
      aliases: ['ako (dress) ( blue archive)', 'ako (dress) (blue archive)'],
    };
  }
  if (normalized === normalizeTag('mature man') || normalized === normalizeTag('mature male')) {
    return { text: 'mature male', aliases: ['mature male'] };
  }
  return { text, aliases };
}

function categoryForPromptTerm(textValue, categoryValue) {
  const text = normalizeTag(textValue);
  const category = contractCategory(categoryValue);
  if (!text) return '';
  if (text === 'clitoral hood') return 'body';
  if (text === 'off shoulder dress' || text === 'off-shoulder dress') return 'clothing';
  if (text === 'fake animal ears') return 'accessory';
  if (isClothingStateTerm(text)) return 'clothingState';
  return category;
}

function contractCategory(value) {
  const category = stringValue(value).trim();
  if (category === 'identity' || category === 'character') return 'identity';
  if (['body', 'upperBody', 'lowerBody'].includes(category)) return 'body';
  if (['clothing', 'upperClothing', 'lowerClothing'].includes(category)) return 'clothing';
  if (category === 'clothingState' || category === 'clothing_state') return 'clothingState';
  if (category === 'accessory') return 'accessory';
  return '';
}

function isClothingStateTerm(text) {
  if (
    text === 'off shoulder dress' ||
    text === 'off-shoulder dress' ||
    text === 'see through dress' ||
    text === 'see-through dress'
  ) return false;
  return /(?:^|\b)(?:no panties|no bra|no gloves|bottomless|topless|nude|naked|completely nude|aside|clothes? (?:lift|pull|aside)|dress lift|leotard aside|bikini aside|pants pull|open clothes|torn|wet pantyhose|strap slip|undressing|unworn|holding panties|holding underwear|holding unworn clothes|lifting own clothes|underwear only|panties only|bare shoulders|bare legs|bare ass|breasts out|nipple peek|cameltoe|covered nipples|off shoulder|panty shot|see through dress|presenting removed panties|erection under clothes|cum on clothes|adjusting another s clothes|fingering through clothes)(?:\b|$)/.test(
    text,
  );
}

function isPromptLeak(textValue) {
  const text = normalizeTag(textValue);
  if (!text) return true;
  return /(?:avertising eyes|dashed eyes|heart eye|heart shaped pupils|uneven eyes|symbol shaped pupils|bouncing breasts|bouncing ass|breast sucking|breast apart|breast press|breasts squeezed together|guided breast grab|nipple stimulation|nipple tweak|hair grab|finger on another|view between legs|leg up|legs together|legs apart|legs up|leg lock|paw pose|ass visible through thighs|stomach bulge|sweaty breasts|armpit focus|ass focus|covering own eyes|face in crotch|ass in center|ass ripple|bum on breasts|face down|face on floor|outstretched legs|swaying hip|thick thighs contrapposto|feet out of frame|bound legs|^no face$|^no eyes$|undressing another s mask|messy hair)/.test(
    text,
  );
}

function roleTermEvidence(cache, role, aliases) {
  const aliasKeys = new Set(aliases.map(normalizeTag));
  const occurrences = [];
  const phrases = [];
  const locations = [];
  const frames = frameMap(cache);
  for (const appearance of role.appearances ?? []) {
    for (const frameIndex of appearance.frame_indexes ?? []) {
      const frame = frames.get(frameIndex);
      const caption = sourceCaption(frame, appearance.source_id);
      for (const tag of parseTags(caption)) {
        if (!aliasKeys.has(normalizeTag(tag))) continue;
        const location = `${appearance.source_id} prompt`;
        occurrences.push({ frame_index: frameIndex, source_location: location });
        if (!phrases.includes(tag)) phrases.push(tag);
        if (!locations.includes(location)) locations.push(location);
      }
    }
  }
  return {
    occurrences: dedupeOccurrences(occurrences),
    phrases,
    locations,
  };
}

function buildSceneTerms(cache, plan) {
  const frames = cache.scriptSnapshot?.frames ?? [];
  const terms = [];
  for (const item of plan) {
    const aliases = item.aliases ?? [item.text];
    const keys = new Set(aliases.map(normalizeTag));
    const occurrences = [];
    const phrases = [];
    for (const frame of frames) {
      for (const tag of parseTags(frame.parsed?.baseCaption)) {
        if (!keys.has(normalizeTag(tag))) continue;
        occurrences.push({ frame_index: frame.index, source_location: 'base prompt' });
        if (!phrases.includes(tag)) phrases.push(tag);
      }
    }
    if (occurrences.length === 0) continue;
    terms.push({
      id: `scene-scene-${safeId(item.text)}`,
      text: item.text,
      category: 'scene',
      source_phrase: phrases[0],
      source_location: 'base prompt',
      frame_indexes: uniqueSorted(occurrences.map((entry) => entry.frame_index)),
      source_occurrences: dedupeOccurrences(occurrences),
    });
  }
  return terms.sort(compareTerms);
}

function scenePlanForScript(scriptId) {
  const byScript = {
    'script-2-db8e8408f5c5a47b': [
      'indoors', 'outdoors', 'bar (place)', 'sofa', 'red sofa', 'hotel room',
      'bathroom', 'tile wall', 'water', 'wet', 'shower (place)', 'street',
      'alley', 'bed room', 'bed sheet', 'condom on bed', 'room', 'home',
      'mirror', 'day', 'morning', 'night', 'dark', 'mixed-sex bathing',
      'open door',
    ],
    'script-2-e55e317517d0fe4b': [
      'indoors', 'outdoors', 'street', 'hotel room', 'room', 'home',
      'restaurant', 'booth seating', 'red seating', 'table', 'grass',
      'wooden wall', 'convenience_store', 'tree', 'cash register',
      'condom box', 'lamp', 'door', 'day', 'morning', 'night', 'dark',
      'open door',
    ],
    'script-ako-dress-bbc-ntr-3ad4bf46dce6774e': ['party'],
    'script-reisa-magical-defeat-3277fc501f49a035': [
      'city', 'outdoors', 'street', 'ground', 'alley', 'trash can',
      'pink tentacles',
    ],
  };
  const values = byScript[scriptId] ?? [];
  const result = values.map((text) => ({ text }));
  if (scriptId === 'script-2-db8e8408f5c5a47b') {
    result.push({ text: 'lamppost', aliases: ['lampost'] });
  }
  return result;
}

function syncMapping(cache) {
  if (!cache.mapping || typeof cache.mapping !== 'object') cache.mapping = {};
  const roles = cache.aiRoleExtraction.roles ?? [];
  cache.mapping.roleAssemblies = roles.map((role) => ({
    sourceRoleId: role.source_role_id,
    displayLabel: role.display_name,
    sourceName: role.display_name,
    sourceAppearances: (role.appearances ?? []).map((appearance) => ({
      sourceId: appearance.source_id,
      sourceKind: appearance.source_kind,
      frameIndexes: appearance.frame_indexes,
    })),
    stages: (role.stages ?? []).map((stage) => {
      const sourceParts = {};
      if (stage.identity) sourceParts.identity = stage.identity;
      if (stage.upper_body) sourceParts.upperBody = stage.upper_body;
      if (stage.lower_body) sourceParts.lowerBody = stage.lower_body;
      if (stage.upper_clothing) sourceParts.upperClothing = stage.upper_clothing;
      if (stage.lower_clothing) sourceParts.lowerClothing = stage.lower_clothing;
      return {
        id: stage.stage_id,
        label: stage.label,
        frameIndexes: stage.frame_indexes,
        sourceSummary: fieldTerms(stage).join(', '),
        sourceParts,
      };
    }),
  }));
  cache.mapping.rolePromptReplacements = roles.map((role) => ({
    sourceRoleId: role.source_role_id,
    displayLabel: role.display_name,
    sourcePreview: (role.prompt_terms ?? []).map((termItem) => termItem.text).join(', '),
    rules: (role.prompt_terms ?? []).map((termItem) => ({
      id: `${safeId(role.source_role_id)}-${safeId(termItem.id)}`,
      sourceTerms: [mappingTerm(termItem)],
    })),
  }));
  const sceneTerms = cache.aiRoleExtraction.scene_terms ?? [];
  cache.mapping.scenePromptReplacements = sceneTerms.length === 0
    ? []
    : [
        {
          id: 'scene-ai',
          label: 'Scene',
          rules: sceneTerms.map((termItem) => ({
            id: `scene-${safeId(termItem.id)}`,
            sourceTerms: [mappingTerm(termItem)],
          })),
        },
      ];
}

function mappingTerm(termItem) {
  return {
    id: termItem.id,
    text: termItem.text,
    category: termItem.category,
    ...(termItem.source_phrase ? { sourcePhrase: termItem.source_phrase } : {}),
    ...(termItem.source_location ? { sourceLocation: termItem.source_location } : {}),
    frameIndexes: termItem.frame_indexes ?? [],
    sourceOccurrences: (termItem.source_occurrences ?? []).map((entry) => ({
      frameIndex: entry.frame_index,
      sourceLocation: entry.source_location,
    })),
  };
}

function normalizeRole(role, cache) {
  role.source_kind = role.appearances.length > 1 ? 'cross_slot' : 'slot';
  role.frame_indexes = uniqueSorted(
    role.appearances.flatMap((appearance) => appearance.frame_indexes ?? []),
  );
  role.raw_identity_tags = uniqueStrings(
    role.stages.flatMap((stage) => splitComma(stage.identity)),
  );
  role.variant_tags = [];
  role.merge_with_role_id = '';
  role.confidence = 0.9;
  role.warnings = [];
  role.unassigned_terms = [];
  role.stages = role.stages.map((stage) => normalizeStage(stage, role, cache));
  role.evidence_terms = uniqueStrings(role.stages.flatMap(fieldTerms));
}

function normalizeStage(stage, role, cache) {
  const normalized = {
    ...stage,
    stage_id: stage.stage_id || stage.id,
    label: stage.label,
    appearance_group_id: stage.appearance_group_id || `appearance-${safeId(stage.stage_id || stage.id)}`,
    merge_with_stage_ids: [],
    field_reasons: stage.field_reasons ?? {},
    confidence: 0.9,
    frame_indexes: uniqueSorted(stage.frame_indexes ?? stage.frames ?? []),
    identity: stringValue(stage.identity),
    upper_body: stringValue(stage.upper_body),
    lower_body: stringValue(stage.lower_body),
    upper_clothing: stringValue(stage.upper_clothing),
    lower_clothing: stringValue(stage.lower_clothing),
    warnings: [],
  };
  filterStageFieldsByEvidence(normalized, role, cache);
  normalized.evidence_terms = fieldTerms(normalized);
  normalized.missing_fields = [
    ['identity', normalized.identity],
    ['upper_body', normalized.upper_body],
    ['lower_body', normalized.lower_body],
    ['upper_clothing', normalized.upper_clothing],
    ['lower_clothing', normalized.lower_clothing],
  ]
    .filter(([, value]) => !value)
    .map(([name]) => `missing_${name}`);
  validateStageFieldEvidence(normalized, role, cache);
  return normalized;
}

function filterStageFieldsByEvidence(stage, role, cache) {
  const frames = frameMap(cache);
  const captions = [];
  for (const appearance of role.appearances ?? []) {
    for (const frameIndex of appearance.frame_indexes ?? []) {
      if (!stage.frame_indexes.includes(frameIndex)) continue;
      captions.push(sourceCaption(frames.get(frameIndex), appearance.source_id));
    }
  }
  const sourceKeys = new Set(captions.flatMap(parseTags).map(normalizeTag));
  for (const fieldName of [
    'identity',
    'upper_body',
    'lower_body',
    'upper_clothing',
    'lower_clothing',
  ]) {
    stage[fieldName] = splitComma(stage[fieldName])
      .filter((termValue) =>
        canonicalPromptTerm(termValue).aliases
          .map(normalizeTag)
          .some((alias) => sourceKeys.has(alias)),
      )
      .join(', ');
  }
}

function validateStageFieldEvidence(stage, role, cache) {
  const frames = frameMap(cache);
  const captions = [];
  for (const appearance of role.appearances ?? []) {
    for (const frameIndex of appearance.frame_indexes ?? []) {
      if (!stage.frame_indexes.includes(frameIndex)) continue;
      captions.push(sourceCaption(frames.get(frameIndex), appearance.source_id));
    }
  }
  const sourceKeys = new Set(captions.flatMap(parseTags).map(normalizeTag));
  for (const termValue of fieldTerms(stage)) {
    const aliases = canonicalPromptTerm(termValue).aliases.map(normalizeTag);
    if (!aliases.some((alias) => sourceKeys.has(alias))) {
      throw new Error(
        `${cache.scriptId}/${role.source_role_id}/${stage.stage_id}: ` +
          `field term lacks same-role stage evidence: ${termValue}`,
      );
    }
  }
}

function auditCache(cache) {
  const issues = [];
  const strictCoverage = strictSlotCoverage(cache);
  if (strictCoverage.uncovered.length > 0) {
    issues.push({ kind: 'strict_slot_coverage', rows: strictCoverage.uncovered });
  }
  const roleFramesSeen = new Set();
  for (const role of cache.aiRoleExtraction.roles ?? []) {
    const appearanceUnion = uniqueSorted(
      role.appearances.flatMap((appearance) => appearance.frame_indexes ?? []),
    );
    if (!sameInts(appearanceUnion, role.frame_indexes)) {
      issues.push({ kind: 'role_frame_drift', role: role.source_role_id });
    }
    const stageUnion = uniqueSorted(role.stages.flatMap((stage) => stage.frame_indexes ?? []));
    if (!sameInts(stageUnion, role.frame_indexes)) {
      issues.push({ kind: 'stage_frame_drift', role: role.source_role_id });
    }
    const perFrameSources = new Map();
    for (const appearance of role.appearances ?? []) {
      for (const frameIndex of appearance.frame_indexes ?? []) {
        const key = `${frameIndex}`;
        const sources = perFrameSources.get(key) ?? [];
        sources.push(appearance.source_id);
        perFrameSources.set(key, sources);
      }
    }
    for (const [frameIndex, sources] of perFrameSources) {
      if (sources.length > 1) {
        issues.push({
          kind: 'same_role_multiple_slots_same_frame',
          role: role.source_role_id,
          frame: Number(frameIndex),
          sources,
        });
      }
    }
    for (const termItem of role.prompt_terms ?? []) {
      if (!['identity', 'body', 'clothing', 'clothingState', 'clothing_state', 'accessory'].includes(termItem.category)) {
        issues.push({ kind: 'invalid_prompt_category', role: role.source_role_id, term: termItem.text, category: termItem.category });
      }
      if (isPromptLeak(termItem.text)) {
        issues.push({ kind: 'prompt_action_leak', role: role.source_role_id, term: termItem.text });
      }
      if (!termHasRoleEvidence(cache, role, termItem)) {
        issues.push({ kind: 'prompt_term_no_same_slot_evidence', role: role.source_role_id, term: termItem.text });
      }
    }
    for (const stage of role.stages ?? []) {
      const labelKey = `${role.source_role_id}\u001f${stage.label}`;
      if (roleFramesSeen.has(labelKey)) {
        issues.push({ kind: 'duplicate_stage_label', role: role.source_role_id, label: stage.label });
      }
      roleFramesSeen.add(labelKey);
      for (const [field, value] of Object.entries({
        identity: stage.identity,
        upper_body: stage.upper_body,
        lower_body: stage.lower_body,
        upper_clothing: stage.upper_clothing,
        lower_clothing: stage.lower_clothing,
      })) {
        for (const termValue of splitComma(value)) {
          if (isPromptLeak(termValue) || isInvalidFiveFieldState(field, termValue)) {
            issues.push({ kind: 'stage_field_leak', role: role.source_role_id, stage: stage.stage_id, field, term: termValue });
          }
        }
      }
    }
  }
  auditMappingSync(cache, issues);
  return {
    counts: cacheCounts(cache),
    strictCoverage,
    issues,
    roles: (cache.aiRoleExtraction.roles ?? []).map((role) => ({
      source_role_id: role.source_role_id,
      display_name: role.display_name,
      frame_count: role.frame_indexes.length,
      appearances: role.appearances.map((appearance) => ({
        source_id: appearance.source_id,
        frame_count: appearance.frame_indexes.length,
        frame_indexes: appearance.frame_indexes,
      })),
      stage_count: role.stages.length,
      prompt_term_count: role.prompt_terms.length,
    })),
  };
}

function strictSlotCoverage(cache) {
  const covered = new Map();
  for (const role of cache.aiRoleExtraction.roles ?? []) {
    for (const appearance of role.appearances ?? []) {
      for (const frameIndex of appearance.frame_indexes ?? []) {
        const key = `${frameIndex}\u001f${appearance.source_id}`;
        const roles = covered.get(key) ?? [];
        roles.push(role.source_role_id);
        covered.set(key, roles);
      }
    }
  }
  const uncovered = [];
  const duplicates = [];
  for (const frame of cache.scriptSnapshot?.frames ?? []) {
    (frame.parsed?.charCaptions ?? []).forEach((caption, slot) => {
      if (!stringValue(caption).trim()) return;
      const sourceId = `slot-${slot}`;
      const key = `${frame.index}\u001f${sourceId}`;
      const roles = covered.get(key) ?? [];
      if (roles.length === 0) {
        uncovered.push({
          frame_index: frame.index,
          source_id: sourceId,
          caption,
          evidence: parseTags(caption),
        });
      } else if (roles.length > 1) {
        duplicates.push({ frame_index: frame.index, source_id: sourceId, roles });
      }
    });
  }
  return { uncovered, duplicate_ownership: duplicates, allowed: [] };
}

function auditMappingSync(cache, issues) {
  const roles = cache.aiRoleExtraction.roles ?? [];
  const groups = cache.mapping?.rolePromptReplacements ?? [];
  if (groups.length !== roles.length) {
    issues.push({ kind: 'role_mapping_group_count', expected: roles.length, actual: groups.length });
  }
  for (const role of roles) {
    const group = groups.find((item) => item.sourceRoleId === role.source_role_id);
    if (!group) {
      issues.push({ kind: 'missing_role_mapping_group', role: role.source_role_id });
      continue;
    }
    const aiKeys = role.prompt_terms.map(termKey).sort();
    const mapKeys = group.rules.flatMap((rule) => rule.sourceTerms ?? []).map(mappingTermKey).sort();
    if (JSON.stringify(aiKeys) !== JSON.stringify(mapKeys)) {
      issues.push({ kind: 'role_mapping_term_drift', role: role.source_role_id });
    }
  }
  const aiScene = (cache.aiRoleExtraction.scene_terms ?? []).map(termKey).sort();
  const mappedScene = (cache.mapping?.scenePromptReplacements ?? [])
    .flatMap((group) => group.rules ?? [])
    .flatMap((rule) => rule.sourceTerms ?? [])
    .map(mappingTermKey)
    .sort();
  if (JSON.stringify(aiScene) !== JSON.stringify(mappedScene)) {
    issues.push({ kind: 'scene_mapping_term_drift' });
  }
  if ((cache.mapping?.roleAssemblies ?? []).length !== roles.length) {
    issues.push({ kind: 'role_assembly_group_count' });
  }
}

function termHasRoleEvidence(cache, role, termItem) {
  const phrase = termItem.source_phrase || termItem.text;
  const keys = new Set([normalizeTag(phrase), normalizeTag(termItem.text)]);
  const frames = frameMap(cache);
  for (const occurrence of termItem.source_occurrences ?? []) {
    const match = /^slot-(\d+) prompt$/.exec(occurrence.source_location);
    if (!match) return false;
    const sourceId = `slot-${match[1]}`;
    const appearance = role.appearances.find((item) => item.source_id === sourceId);
    if (!appearance?.frame_indexes.includes(occurrence.frame_index)) return false;
    const tags = parseTags(sourceCaption(frames.get(occurrence.frame_index), sourceId));
    if (!tags.some((tag) => keys.has(normalizeTag(tag)))) return false;
  }
  return (termItem.source_occurrences ?? []).length > 0;
}

function isInvalidFiveFieldState(field, termValue) {
  const text = normalizeTag(termValue);
  if ((field === 'upper_clothing' || field === 'lower_clothing') && isClothingStateTerm(text)) {
    return true;
  }
  return false;
}

function cacheCounts(cache) {
  const roles = cache.aiRoleExtraction?.roles ?? [];
  return {
    frameCount: cache.scriptSnapshot?.frames?.length ?? 0,
    roleCount: roles.length,
    stageCount: roles.reduce((count, role) => count + (role.stages?.length ?? 0), 0),
    rolePromptTermCount: roles.reduce((count, role) => count + (role.prompt_terms?.length ?? 0), 0),
    sceneTermCount: cache.aiRoleExtraction?.scene_terms?.length ?? 0,
    roleMappingGroupCount: cache.mapping?.rolePromptReplacements?.length ?? 0,
    roleMappingRuleCount: (cache.mapping?.rolePromptReplacements ?? []).reduce((count, group) => count + (group.rules?.length ?? 0), 0),
    sceneMappingGroupCount: cache.mapping?.scenePromptReplacements?.length ?? 0,
    sceneMappingRuleCount: (cache.mapping?.scenePromptReplacements ?? []).reduce((count, group) => count + (group.rules?.length ?? 0), 0),
  };
}

function roleFrom(template, spec) {
  const role = structuredClone(template);
  role.source_role_id = spec.id;
  role.display_name = spec.display;
  role.canonical_name = spec.canonical ?? '';
  role.franchise = spec.franchise ?? '';
  role.role_reason = 'Conservative source-evidence role with explicit slot ownership.';
  role.stages = spec.stages;
  role.prompt_terms = [];
  setAppearances(role, spec.appearances);
  return role;
}

function setAppearances(role, specs) {
  role.appearances = specs
    .filter((spec) => spec.frames.length > 0)
    .map((spec) => ({
      source_id: spec.sourceId,
      source_kind: 'slot',
      frame_indexes: uniqueSorted(spec.frames),
    }));
  role.frame_indexes = uniqueSorted(role.appearances.flatMap((item) => item.frame_indexes));
  role.source_kind = role.appearances.length > 1 ? 'cross_slot' : 'slot';
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
  return {
    stage_id: id,
    label,
    appearance_group_id: `appearance-${safeId(id)}`,
    merge_with_stage_ids: [],
    field_reasons: {},
    confidence: 0.9,
    frame_indexes: uniqueSorted(frames),
    identity,
    upper_body: upperBody,
    lower_body: lowerBody,
    upper_clothing: upperClothing,
    lower_clothing: lowerClothing,
    evidence_terms: [],
    missing_fields: [],
    warnings: [],
  };
}

function patchStage(role, stageId, patch) {
  Object.assign(stageById(role, stageId), patch);
}

function stageById(role, stageId) {
  const stage = role.stages.find((item) => item.stage_id === stageId);
  if (!stage) throw new Error(`Missing stage ${role.source_role_id}/${stageId}`);
  return stage;
}

function roleMap(cache) {
  return new Map((cache.aiRoleExtraction?.roles ?? []).map((role) => [role.source_role_id, role]));
}

function requiredRole(roles, roleId) {
  const role = roles.get(roleId);
  if (!role) throw new Error(`Missing role ${roleId}`);
  return role;
}

function appearanceFrames(role, sourceId) {
  return role.appearances.find((item) => item.source_id === sourceId)?.frame_indexes ?? [];
}

function fieldTerms(stage) {
  return uniqueStrings([
    ...splitComma(stage.identity),
    ...splitComma(stage.upper_body),
    ...splitComma(stage.lower_body),
    ...splitComma(stage.upper_clothing),
    ...splitComma(stage.lower_clothing),
  ]);
}

function removeTerms(value, removes) {
  const keys = new Set(removes.map(normalizeTag));
  return splitComma(value).filter((item) => !keys.has(normalizeTag(item))).join(', ');
}

function replaceTerm(value, before, after) {
  return splitComma(value).map((item) => normalizeTag(item) === normalizeTag(before) ? after : item).join(', ');
}

function canonicalizeCommaTerms(value, replacements) {
  const map = new Map(Object.entries(replacements).map(([from, to]) => [normalizeTag(from), to]));
  return uniqueStrings(splitComma(value).map((item) => map.get(normalizeTag(item)) ?? item)).join(', ');
}

function parseTags(textValue) {
  return stringValue(textValue)
    .replace(/\r?\n/g, ',')
    .replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',')
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/[，、；;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function cleanTag(value) {
  let text = stringValue(value).trim().replace(/^['"]|['"]$/g, '').trim();
  let changed = true;
  while (changed) {
    const next = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  text = text.replace(/^:+|:+$/g, '').trim();
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) text = weighted[1].trim();
  return text.replace(/^[{}\[\]]+|[{}\[\]]+$/g, '').replace(/\s+/g, ' ').trim();
}

function normalizeTag(value) {
  return cleanTag(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function sourceCaption(frame, sourceId) {
  if (!frame) return '';
  if (sourceId === 'base') return stringValue(frame.parsed?.baseCaption);
  const match = /^slot-(\d+)$/.exec(sourceId);
  if (!match) return '';
  return stringValue(frame.parsed?.charCaptions?.[Number(match[1])]);
}

function frameMap(cache) {
  return new Map((cache.scriptSnapshot?.frames ?? []).map((frame) => [Number(frame.index), frame]));
}

function compareTerms(left, right) {
  const order = { identity: 0, body: 1, clothing: 2, clothingState: 3, accessory: 4, scene: 5 };
  return (order[left.category] ?? 99) - (order[right.category] ?? 99) || left.text.localeCompare(right.text);
}

function termKey(termItem) {
  return `${termItem.category}\u001f${normalizeTag(termItem.text)}\u001f${JSON.stringify(termItem.frame_indexes ?? [])}`;
}

function mappingTermKey(termItem) {
  return `${termItem.category}\u001f${normalizeTag(termItem.text)}\u001f${JSON.stringify(termItem.frameIndexes ?? [])}`;
}

function term(text, category) {
  return { text, category };
}

function dedupeOccurrences(values) {
  const seen = new Set();
  return values.filter((item) => {
    const key = `${item.frame_index}\u001f${item.source_location}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).sort((a, b) => a.frame_index - b.frame_index || a.source_location.localeCompare(b.source_location));
}

function uniqueSorted(values) {
  return [...new Set((values ?? []).map(Number).filter(Number.isInteger))].sort((a, b) => a - b);
}

function uniqueStrings(values) {
  const result = [];
  const seen = new Set();
  for (const value of values ?? []) {
    const text = stringValue(value).trim();
    const key = normalizeTag(text);
    if (!text || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function splitComma(value) {
  return stringValue(value).split(',').map((item) => item.trim()).filter(Boolean);
}

function sameInts(left, right) {
  return JSON.stringify(uniqueSorted(left)) === JSON.stringify(uniqueSorted(right));
}

function intRange(from, to) {
  return Array.from({ length: to - from + 1 }, (_, index) => from + index);
}

function safeId(value) {
  return normalizeTag(value).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'term';
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function parseArgs(args) {
  const parsed = { apply: false, help: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') parsed.apply = true;
    else if (arg === '--help' || arg === '-h') parsed.help = true;
    else if (arg === '--cache-dir') parsed.cacheDir = args[++index];
    else if (arg === '--report') parsed.report = args[++index];
    else if (arg === '--backup-dir') parsed.backupDir = args[++index];
  }
  return parsed;
}

function printHelp() {
  console.log(`Usage:
  node tool/repair_script_recast_new_batch_20260720_b.mjs \\
    --cache-dir <isolated-cache-dir> [--report <json>] [--backup-dir <dir>] [--apply]

Default is dry-run. --apply writes only the explicitly named --cache-dir.
No API, network, translation endpoint, or project credential is used.`);
}
