import fs from 'node:fs';
import path from 'node:path';

const TARGET_IDS = new Set([
  'script-2-386d8895c7683ba6',
  'script-32294165a138a3c9',
  'script-a196cfd91d2e07a3',
  'script-toki-bunny-bbc-ntr-657f2ea003b35f20',
]);

const ALLOWED_CATEGORIES = new Set([
  'identity',
  'body',
  'clothing',
  'clothingState',
  'accessory',
]);

const IDENTITY_TERMS = setOf(`
  girl
  boy
  maid
  rem (re:zero)
  ram (re:zero)
  emilia (re:zero)
  regulus corneas
  regulus_corneas
  natsuki subaru
  dark-skinned male
  faceless male
  muscular male
  anis (nikke)
  anis (sparkling summer) (nikke)
  black man
  cinderella_(nikke)
  commander_(nikke)
  mature male
  mature man
  rapi_(nikke)
  very dark-skinned male
  african
  mika (blue archive)
  nagisa (blue archive)
  sensei_(blue_archive_the_animation)
  fat man
  toki (bunny) (blue archive)
  gyaruo
  ugly bastard
  crossdressing_(mtf)
`);

const BODY_TERMS = setOf(`
  alternate hair length
  alternate hairstyle
  armpits
  armpits crease
  ass
  bald
  bare shoulders
  big belly
  black hair
  bob cut
  brown pubic hair
  cleavage
  cleft of venus
  collarbone
  crown braid
  curvy
  erect nipples
  feather wings
  female pubic hair
  hair slicked back
  halo
  heart tattoo
  huge ass
  huge breasts
  inverted nipples
  large areola
  large breasts
  long hair
  low wings
  male black hair
  male blonde hair
  male pubic hair
  medium breasts
  messy hair
  midriff
  navel
  nipples
  no eyes
  pink tattoo
  pubic tattoo
  short hair
  single side bun
  skin fang
  small breasts
  thick thighs
  thighs
  underbutt
  very dark skin
  white hair
  wide hips
  wide wide hips
  black penis
  dark penis
  girthy penis
  huge penis
  huge testicles
  large black penis
  large penis
  large veiny black penis
  large veiny penis
  small penis
  testicles
  veiny penis
`);

const ACCESSORY_TERMS = setOf(`
  animal collar
  aviator sunglasses
  ball gag
  black blindfold
  black choker
  black flower
  black hat
  blindfold
  blindfold_slip
  chastity_cage
  detached collar
  eyewear on head
  frilled choker
  hair flower
  hair ornament
  hair ribbon
  handcuffs
  leash
  maid headdress
  no hat
  purple ribbon
  red collar
  rope
  star necklace
  thigh strap
  tongue piercing
  tongue_piercing
  white flower
  x hair ornament
`);

const CLOTHING_TERMS = setOf(`
  alternate costume
  official costume
  revealing clothes
  black bikini
  black dress
  black gloves
  black jacket
  black leotard
  black shorts
  black sleeves
  black thighhighs
  bikini bottom only
  bodycon
  bow panties
  collared shirt
  cropped jacket
  cropped shirt
  detached sleeves
  elbow gloves
  eyepatch bikini
  fishnet thighhighs
  frilled dress
  frilled sleeves
  front-tie bikini top
  grey shirt
  highleg thong leotard
  latex dress
  long coat
  maid bikini
  male black panties
  male black swimsuit
  male red swimsuit
  micro bikini
  micro panties
  microdress
  military uniform
  o-ring dress
  pink babydoll
  pink bridal gauntlets
  pink dress
  pink gloves
  pink panties
  purple bridal gauntlets
  purple dress
  red bikini
  red swimsuit
  roswaal mansion maid uniform
  short dress
  short shorts
  side-tie bikini bottom
  slingshot swimsuit
  string bikini
  tight dress
  track jacket
  track suit
  unconventional maid
  waist apron
  wedding dress
  white apron
  white bikini
  white coat
  white dress
  white garterbelt
  white gloves
  white panties
  white pants
  white thighhighs
  yellow jacket
`);

const CLOTHING_STATE_TERMS = setOf(`
  adjusting clothes
  areola slip
  barefoot
  bikini top pull
  bottomless
  bottomless female
  bottomless male
  breast out
  breasts out
  cameltoe
  center opening
  clothed female nude male
  completely nude
  covered nipples
  cum on clothes
  highleg thong leotard aside
  leotard aside
  lifting own clothes
  male topless
  naked jacket
  nipple peek
  no bra
  no panties
  one breast out
  open jacket
  panties pull
  pants pull
  torn clothes
  torn leotard
  unworn bikini
`);

const LOWER_BODY_TERMS = setOf(`
  ass
  big belly
  cleft of venus
  huge ass
  male pubic hair
  female pubic hair
  navel
  pink tattoo
  pubic tattoo
  thick thighs
  thighs
  underbutt
  wide hips
  wide wide hips
  black penis
  dark penis
  girthy penis
  huge penis
  huge testicles
  large black penis
  large penis
  large veiny black penis
  large veiny penis
  small penis
  testicles
  veiny penis
`);

const LOWER_CLOTHING_TERMS = setOf(`
  bikini bottom only
  black shorts
  black thighhighs
  bow panties
  fishnet thighhighs
  male black panties
  male black swimsuit
  male red swimsuit
  micro panties
  pink panties
  short shorts
  side-tie bikini bottom
  white garterbelt
  white panties
  white pants
  white thighhighs
`);

const LOWER_ACCESSORY_TERMS = setOf(`
  thigh strap
`);

const TERM_NORMALIZATIONS = new Map([
  ['collared shrit', 'collared shirt'],
  ['invereted nipples', 'inverted nipples'],
  ['musclar male', 'muscular male'],
  ['thigh thighs', 'thick thighs'],
]);

const SPLIT_TERMS = new Map([
  ['pink gloves black thighhighs', ['pink gloves', 'black thighhighs']],
]);

const SCENE_TERMS_BY_SCRIPT = {
  'script-2-386d8895c7683ba6': setOf(`
    indoors
    on bed
    white bed sheet
    dark
    room
    hotel room
    prison
    brick wall
    night
    wooden chair
    stone floor
    hallway
    lamp
    full-length mirror
    in cell
    stone wall
    sunlight
    table
    teacup
    door
    red couch
    trash
    pink dildo
    sex toy
    suction_cup_dildo
  `),
  'script-32294165a138a3c9': setOf(`
    indoors
    outdoors
    dark
    hotel room
    room
    beach
    day
    summer
    sunlight
    commander's room
    wooden stool
    wooden table
    evening
    ocean
    sunrise
    desk
    open door
    blue drink
    straw
    pointless condom
    used condom
    pink condom
  `),
  'script-a196cfd91d2e07a3': setOf(`
    indoors
    on bed
    dark
    pink lights
    bar
    red couch
    sofa
  `),
  'script-toki-bunny-bbc-ntr-657f2ea003b35f20': setOf(`
    casino
    toilet
    toilet interior
    urinal
    used condom
  `),
};

const SCRIPT_CONFIGS = {
  'script-2-386d8895c7683ba6': {
    roles: [
      role('role-rem-re-zero', 'rem (re:zero) / 雷姆（Re:从零开始的异世界生活）', 'rem', 're:zero', ['role-rem-re-zero'], ({ text }) => text.includes('rem (re:zero)')),
      role('role-ram-re-zero', 'ram (re:zero) / 拉姆（Re:从零开始的异世界生活）', 'ram', 're:zero', ['role-ram-re-zero'], ({ text }) => text.includes('ram (re:zero)')),
      role('role-emilia-re-zero', 'emilia (re:zero) / 爱蜜莉雅（Re:从零开始的异世界生活）', 'emilia', 're:zero', ['role-emilia-re-zero'], ({ text }) => text.includes('emilia (re:zero)')),
      role('role-regulus-corneas', 'regulus corneas / 雷古勒斯·柯尔尼亚斯', 'regulus corneas', 're:zero', ['role-anonymous-male', 'role-muscular-male'], ({ frameIndex, slot, text }) => text.includes('regulus corneas') || text.includes('regulus_corneas') || (slot === 1 && [60, 152, 153, 158].includes(frameIndex))),
      role('role-natsuki-subaru', 'natsuki subaru / 菜月昴', 'natsuki subaru', 're:zero', ['role-anonymous-male'], ({ text }) => text.includes('natsuki subaru')),
      role('role-dark-muscular-male-a', 'dark-skinned muscular male / 深肤色肌肉男性 A', '', '', ['role-muscular-male'], ({ frameIndex, slot }) => slot === 1 && inRanges(frameIndex, [[77, 85], [87, 87], [91, 102], [104, 113], [116, 135], [262, 265]])),
      role('role-dark-muscular-male-b', 'dark-skinned muscular male / 深肤色肌肉男性 B', '', '', ['role-muscular-male'], ({ frameIndex, slot }) => slot === 2 && inRanges(frameIndex, [[262, 265]])),
    ],
  },
  'script-32294165a138a3c9': {
    roles: [
      role('role-anis-sparkling-summer-nikke', 'anis (sparkling summer) (nikke) / 阿妮斯（闪耀夏日）（胜利女神：妮姬）', 'anis', 'nikke', ['role-anis-sparkling-summer-nikke'], ({ text }) => text.includes('anis (')),
      role('role-muscular-male', 'black man / 黑人肌肉男性', '', '', ['role-muscular-male'], ({ text }) => text.includes('black man') || text.includes('very dark-skinned male') || text.includes('african')),
      role('role-commander-nikke', 'commander_(nikke) / 指挥官（胜利女神：妮姬）', 'commander', 'nikke', ['role-commander-nikke'], ({ text }) => text.includes('commander_(nikke)')),
      role('role-cinderella-nikke', 'cinderella_(nikke) / 灰姑娘（胜利女神：妮姬）', 'cinderella', 'nikke', ['role-cinderella-nikke'], ({ text }) => text.includes('cinderella_(nikke)')),
      role('role-rapi-nikke', 'rapi_(nikke) / 拉毗（胜利女神：妮姬）', 'rapi', 'nikke', ['role-rapi-nikke'], ({ text }) => text.includes('rapi_(nikke)')),
    ],
  },
  'script-a196cfd91d2e07a3': {
    roles: [
      role('role-mika-blue-archive', 'mika (blue archive) / 圣园未花（碧蓝档案）', 'mika', 'blue archive', ['role-mika-blue-archive'], ({ text }) => text.includes('mika (blue archive)')),
      role('role-sensei-blue-archive-the-animation', 'sensei_(blue_archive_the_animation) / 老师（碧蓝档案动画）', 'sensei', 'blue archive', ['role-sensei-blue-archive-the-animation'], ({ frameIndex, slot, text }) => text.includes('sensei_(blue_archive_the_animation)') || (slot === 1 && [74, 75, 78].includes(frameIndex))),
      role('role-muscular-male-a', 'muscular male / 深肤色肌肉男性 A', '', '', ['role-muscular-male'], ({ slot, text }) => slot === 1 && (text.includes('musclar male') || text.includes('muscular male'))),
      role('role-muscular-male-b', 'muscular male / 深肤色肌肉男性 B', '', '', ['role-muscular-male'], ({ frameIndex, slot }) => slot === 2 && inRanges(frameIndex, [[34, 37], [63, 69]])),
      role('role-nagisa-blue-archive', 'nagisa (blue archive) / 桐藤渚（碧蓝档案）', 'nagisa', 'blue archive', ['role-nagisa-blue-archive'], ({ text }) => text.includes('nagisa (blue archive)')),
      role('role-fat-male-a', 'fat man / 肥胖男性 A', '', '', ['role-anonymous-male'], ({ slot, text }) => slot === 1 && text.includes('fat man')),
      role('role-fat-male-b', 'fat man / 肥胖男性 B', '', '', ['role-anonymous-male'], ({ frameIndex, slot }) => slot === 2 && inRanges(frameIndex, [[54, 61], [79, 87]])),
    ],
  },
  'script-toki-bunny-bbc-ntr-657f2ea003b35f20': {
    roles: [
      role('role-toki-bunny-blue-archive', 'toki (bunny) (blue archive) / 飞鸟马时（兔女郎）（碧蓝档案）', 'toki', 'blue archive', ['role-toki-bunny-blue-archive'], ({ slot }) => slot === 0),
      role('role-dark-male-a', 'very dark skin / 深肤色男性 A', '', '', ['role-anonymous-male'], ({ slot }) => slot === 1),
      role('role-dark-male-b', 'very dark skin / 深肤色男性 B', '', '', ['role-anonymous-male'], ({ slot }) => slot === 2),
    ],
  },
};

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) {
  throw new Error('Usage: node tool/repair_script_recast_new_batch_20260720_a.mjs --cache-dir <dir> [--report <file>] [--backup-dir <dir>] [--apply]');
}

const cacheDir = path.resolve(options.cacheDir);
if (!fs.existsSync(cacheDir)) throw new Error(`Missing cache dir: ${cacheDir}`);
const backupDir = path.resolve(options.backupDir || `${cacheDir}_repair_backup_a`);
const files = fs.readdirSync(cacheDir).filter((name) => name.endsWith('.json')).sort();
const pendingWrites = [];
const report = {
  kind: 'script_recast_new_batch_20260720_a_repair',
  cache_dir: cacheDir,
  backup_dir: backupDir,
  apply: options.apply,
  api_used: false,
  files_scanned: 0,
  files_changed: 0,
  role_count_before: 0,
  role_count_after: 0,
  stage_count_before: 0,
  stage_count_after: 0,
  role_term_count_before: 0,
  role_term_count_after: 0,
  scene_term_count_before: 0,
  scene_term_count_after: 0,
  role_rule_count_after: 0,
  scene_rule_count_after: 0,
  slot_assignment_issue_count: 0,
  typo_corrections: [...TERM_NORMALIZATIONS.entries()].map(([source, target]) => ({ source, target })),
  rows: [],
};

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (!TARGET_IDS.has(cache.scriptId)) continue;
  report.files_scanned += 1;
  const beforeCache = structuredClone(cache);
  const beforeText = stableJson(cache);
  const before = counts(cache);
  const row = repairCache(cache, SCRIPT_CONFIGS[cache.scriptId]);
  const after = counts(cache);
  const afterText = stableJson(cache);
  const changed = beforeText !== afterText;
  row.file_name = fileName;
  row.changed = changed;
  row.diff_paths = changed ? diffPaths(beforeCache, cache).slice(0, 80) : [];
  row.before = before;
  row.after = after;
  report.rows.push(row);
  report.role_count_before += before.roles;
  report.role_count_after += after.roles;
  report.stage_count_before += before.stages;
  report.stage_count_after += after.stages;
  report.role_term_count_before += before.roleTerms;
  report.role_term_count_after += after.roleTerms;
  report.scene_term_count_before += before.sceneTerms;
  report.scene_term_count_after += after.sceneTerms;
  report.role_rule_count_after += after.roleRules;
  report.scene_rule_count_after += after.sceneRules;
  report.slot_assignment_issue_count += row.slot_assignment_issues.length;
  if (changed) {
    report.files_changed += 1;
    pendingWrites.push({ fileName, filePath, cache });
  }
}

if (options.report) {
  const reportPath = path.resolve(options.report);
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));
if (report.files_scanned !== TARGET_IDS.size) {
  throw new Error(`Expected ${TARGET_IDS.size} target files, found ${report.files_scanned}`);
}
if (report.slot_assignment_issue_count > 0) {
  throw new Error(`Source slot assignment has ${report.slot_assignment_issue_count} issue(s); see report output`);
}
if (options.apply && pendingWrites.length > 0) {
  fs.mkdirSync(backupDir, { recursive: true });
  for (const { fileName, filePath, cache } of pendingWrites) {
    const backupPath = path.join(backupDir, fileName);
    if (!fs.existsSync(backupPath)) fs.copyFileSync(filePath, backupPath);
    cache.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
  }
}

function repairCache(cache, config) {
  const originalRoles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  const frames = frameList(cache);
  const alreadyRepaired = isAlreadyRepaired(originalRoles, config.roles);
  const assignments = new Map(config.roles.map((spec) => [spec.id, new Map()]));
  const slotAssignmentIssues = [];

  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    const captions = Array.isArray(frame.parsed?.charCaptions)
      ? frame.parsed.charCaptions
      : [];
    for (let slot = 0; slot < captions.length; slot += 1) {
      const caption = stringValue(captions[slot]).trim();
      if (!caption) continue;
      const text = normalizedKey(caption);
      const owners = config.roles.filter((spec) => spec.owns({
        frameIndex,
        slot,
        caption,
        text,
      }));
      if (owners.length !== 1) {
        slotAssignmentIssues.push({
          frame_index: frameIndex,
          slot,
          owner_ids: owners.map((owner) => owner.id),
          caption,
        });
        continue;
      }
      const sourceId = `slot-${slot}`;
      const bySource = assignments.get(owners[0].id);
      const indexes = bySource.get(sourceId) ?? [];
      indexes.push(frameIndex);
      bySource.set(sourceId, indexes);
    }
  }

  if (slotAssignmentIssues.length > 0) {
    return {
      script_id: cache.scriptId,
      already_repaired: alreadyRepaired,
      slot_assignment_issues: slotAssignmentIssues,
      role_ids: originalRoles.map((item) => item.source_role_id),
    };
  }

  const newRoles = config.roles.map((spec) => {
    const template = originalRoles.find((item) => item.source_role_id === spec.id)
      ?? originalRoles.find((item) => spec.templateIds.includes(item.source_role_id))
      ?? {};
    return buildRole({
      cache,
      spec,
      bySource: assignments.get(spec.id),
      template,
      originalRoles,
      alreadyRepaired,
    });
  });

  cache.aiRoleExtraction ??= {};
  cache.aiRoleExtraction.status = 'ready';
  cache.aiRoleExtraction.roles = newRoles;
  cache.aiRoleExtraction.scene_terms = buildSceneTerms(cache);
  cache.aiRoleExtraction.unassigned_terms = [];
  cache.aiRoleExtraction.evidence_requests = [];
  cache.aiRoleExtraction.attention_items = [];
  cache.mapping ??= {};
  cache.mapping.id ??= `mapping-${cache.scriptId}`;
  cache.mapping.scriptId = cache.scriptId;
  cache.mapping.roleAssemblies = buildRoleAssemblies(newRoles, cache.mapping.roleAssemblies ?? []);
  cache.mapping.rolePromptReplacements = buildRolePromptMappings(newRoles, cache.mapping.rolePromptReplacements ?? []);
  cache.mapping.scenePromptReplacements = buildScenePromptMappings(cache.aiRoleExtraction.scene_terms, cache.mapping.scenePromptReplacements ?? []);

  return {
    script_id: cache.scriptId,
    already_repaired: alreadyRepaired,
    slot_assignment_issues: [],
    role_ids: newRoles.map((item) => item.source_role_id),
    role_rows: newRoles.map((item) => ({
      source_role_id: item.source_role_id,
      display_name: item.display_name,
      frame_count: item.frame_indexes.length,
      appearances: item.appearances.map((appearance) => ({
        source_id: appearance.source_id,
        frame_count: appearance.frame_indexes.length,
      })),
      stage_count: item.stages.length,
      prompt_term_count: item.prompt_terms.length,
      categories: countBy(item.prompt_terms, (term) => term.category),
    })),
  };
}

function buildRole({ cache, spec, bySource, template, originalRoles, alreadyRepaired }) {
  const appearances = [...bySource.entries()]
    .map(([sourceId, indexes]) => ({
      source_id: sourceId,
      source_kind: 'slot',
      frame_indexes: sortedInts(indexes),
    }))
    .sort((left, right) => left.source_id.localeCompare(right.source_id));
  const frameIndexes = sortedInts(appearances.flatMap((item) => item.frame_indexes));
  const promptTerms = buildRoleTerms(cache, appearances, spec.id);
  let stages;
  const currentExact = originalRoles.find((item) => item.source_role_id === spec.id);
  if (alreadyRepaired && currentExact) {
    stages = preserveExistingStages(currentExact.stages ?? [], frameIndexes, spec.id, cache, appearances);
  } else {
    const sourceStages = originalRoles
      .filter((item) => spec.templateIds.includes(item.source_role_id))
      .flatMap((item) => item.stages ?? []);
    stages = rebuildStages(sourceStages, frameIndexes, spec.id, cache, appearances);
  }
  // The shared field proofreader intentionally tightens these role-level
  // summaries after the first repair pass. Preserve that audited result on
  // subsequent passes so this repairer remains idempotent in the full pipeline.
  const evidenceTerms = alreadyRepaired && currentExact
    ? [...(currentExact.evidence_terms ?? [])]
    : unique(stages.flatMap((stage) => stage.evidence_terms ?? []));
  const identityTerms = alreadyRepaired && currentExact
    ? [...(currentExact.raw_identity_tags ?? [])]
    : promptTerms.filter((term) => term.category === 'identity').map((term) => term.text);

  return {
    source_role_id: spec.id,
    source_kind: 'slot',
    display_name: spec.display,
    role_reason: 'Source-evidence-only role rebuilt from exact non-empty character-slot ownership.',
    canonical_name: spec.canonical,
    franchise: spec.franchise,
    raw_identity_tags: unique(identityTerms),
    variant_tags: [],
    merge_with_role_id: '',
    confidence: 0.96,
    frame_indexes: frameIndexes,
    appearances,
    evidence_terms: evidenceTerms,
    warnings: [],
    stages,
    unassigned_terms: [],
    prompt_terms: promptTerms,
  };
}

function buildRoleTerms(cache, appearances, roleId) {
  const terms = new Map();
  const framesByIndex = new Map(frameList(cache).map((frame) => [Number(frame.index), frame]));
  for (const appearance of appearances) {
    const slot = Number(appearance.source_id.slice('slot-'.length));
    for (const frameIndex of appearance.frame_indexes) {
      const caption = stringValue(framesByIndex.get(frameIndex)?.parsed?.charCaptions?.[slot]);
      for (const sourceTag of parseTags(caption)) {
        const sourceKey = normalizedKey(sourceTag);
        const split = SPLIT_TERMS.get(sourceKey);
        const targets = split ?? [canonicalTerm(sourceKey)];
        for (const target of targets) {
          const category = categoryForTerm(target);
          if (!category) continue;
          const key = `${category}\u001f${target}`;
          const entry = terms.get(key) ?? {
            text: target,
            category,
            sourcePhrases: new Map(),
            sourceIds: new Set(),
            frameIndexes: new Set(),
            occurrences: new Map(),
          };
          entry.sourcePhrases.set(sourceTag, (entry.sourcePhrases.get(sourceTag) ?? 0) + 1);
          entry.sourceIds.add(appearance.source_id);
          entry.frameIndexes.add(frameIndex);
          entry.occurrences.set(`${frameIndex}\u001f${appearance.source_id}`, {
            frame_index: frameIndex,
            source_location: `${appearance.source_id} prompt`,
          });
          terms.set(key, entry);
        }
      }
    }
  }
  return [...terms.values()]
    .sort((left, right) => categoryRank(left.category) - categoryRank(right.category) || left.text.localeCompare(right.text))
    .map((entry) => {
      // Prefer an exact source variant that differs from the normalized target.
      // The normalized `text` already matches canonical occurrences; keeping the
      // alternate spelling/combined phrase here preserves point-to-point evidence
      // for corrected typos and split source tags as well.
      const sourcePhrase = preferredSourcePhrase(entry);
      const sourceIds = [...entry.sourceIds].sort();
      return {
        id: `role-${slug(roleId)}-${slug(entry.category)}-${slug(entry.text)}`,
        text: entry.text,
        category: entry.category,
        source_phrase: sourcePhrase,
        source_location: sourceIds.map((id) => `${id} prompt`).join('; '),
        frame_indexes: sortedInts(entry.frameIndexes),
        source_occurrences: [...entry.occurrences.values()].sort((a, b) => a.frame_index - b.frame_index || a.source_location.localeCompare(b.source_location)),
      };
    });
}

function buildSceneTerms(cache) {
  const allow = SCENE_TERMS_BY_SCRIPT[cache.scriptId] ?? new Set();
  const terms = new Map();
  for (const frame of frameList(cache)) {
    const frameIndex = Number(frame.index);
    for (const sourceTag of parseTags(frame.parsed?.baseCaption)) {
      const key = normalizedKey(sourceTag);
      if (!allow.has(key)) continue;
      const entry = terms.get(key) ?? {
        text: key,
        sourcePhrases: new Map(),
        frames: new Set(),
      };
      entry.sourcePhrases.set(sourceTag, (entry.sourcePhrases.get(sourceTag) ?? 0) + 1);
      entry.frames.add(frameIndex);
      terms.set(key, entry);
    }
  }
  return [...terms.values()].sort((a, b) => a.text.localeCompare(b.text)).map((entry) => ({
    id: `scene-scene-${slug(entry.text)}`,
    text: entry.text,
    category: 'scene',
    source_phrase: [...entry.sourcePhrases.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0][0],
    source_location: 'base prompt',
    frame_indexes: sortedInts(entry.frames),
    source_occurrences: sortedInts(entry.frames).map((frameIndex) => ({
      frame_index: frameIndex,
      source_location: 'base prompt',
    })),
  }));
}

function rebuildStages(sourceStages, roleFrames, roleId, cache, appearances) {
  const roleFrameSet = new Set(roleFrames);
  const groups = [];
  for (const stage of sourceStages) {
    const indexes = sortedInts((stage.frame_indexes ?? []).filter((index) => roleFrameSet.has(Number(index))));
    if (indexes.length === 0) continue;
    const label = repairedStageLabel(cache.scriptId, roleId, stage.label, indexes, cache, appearances);
    groups.push({ label, frameIndexes: indexes });
  }
  const covered = new Set(groups.flatMap((group) => group.frameIndexes));
  const missing = roleFrames.filter((index) => !covered.has(index));
  if (missing.length > 0) {
    groups.push({
      label: repairedStageLabel(cache.scriptId, roleId, '', missing, cache, appearances),
      frameIndexes: missing,
    });
  }
  return materializeStages(mergeStageGroups(groups), roleId, cache, appearances);
}

function preserveExistingStages(sourceStages, roleFrames, roleId, cache, appearances) {
  const roleFrameSet = new Set(roleFrames);
  const stages = sourceStages.map((stage) => ({
    ...stage,
    frame_indexes: sortedInts((stage.frame_indexes ?? []).filter((index) => roleFrameSet.has(Number(index)))),
  })).filter((stage) => stage.frame_indexes.length > 0);
  const covered = new Set(stages.flatMap((stage) => stage.frame_indexes));
  const missing = roleFrames.filter((index) => !covered.has(index));
  if (missing.length === 0) return stages;
  const extra = materializeStages([{
    label: repairedStageLabel(cache.scriptId, roleId, '', missing, cache, appearances),
    frameIndexes: missing,
  }], roleId, cache, appearances)[0];
  extra.stage_id = `stage-${stages.length + 1}`;
  extra.appearance_group_id = `appearance-${stages.length + 1}`;
  return [...stages, extra];
}

function mergeStageGroups(groups) {
  const byLabel = new Map();
  for (const group of groups) {
    const entry = byLabel.get(group.label) ?? new Set();
    for (const index of group.frameIndexes) entry.add(index);
    byLabel.set(group.label, entry);
  }
  return [...byLabel.entries()].map(([label, frames]) => ({ label, frameIndexes: sortedInts(frames) }))
    .sort((a, b) => a.frameIndexes[0] - b.frameIndexes[0] || a.label.localeCompare(b.label));
}

function materializeStages(groups, roleId, cache, appearances) {
  return groups.map((group, index) => {
    const fields = fiveFieldsForFrames(cache, appearances, group.frameIndexes);
    const evidenceTerms = unique([
      ...splitField(fields.identity),
      ...splitField(fields.upper_body),
      ...splitField(fields.lower_body),
      ...splitField(fields.upper_clothing),
      ...splitField(fields.lower_clothing),
    ]);
    const missingFields = [
      ['identity', fields.identity],
      ['upper_body', fields.upper_body],
      ['lower_body', fields.lower_body],
      ['upper_clothing', fields.upper_clothing],
      ['lower_clothing', fields.lower_clothing],
    ].filter(([, value]) => !value).map(([field]) => `missing_${field}`);
    return {
      stage_id: `stage-${index + 1}`,
      label: group.label,
      appearance_group_id: `appearance-${index + 1}`,
      merge_with_stage_ids: [],
      field_reasons: {
        identity: fields.identity ? 'Identity terms appear in the assigned role slot evidence.' : 'No stable identity evidence was present.',
        upper_body: fields.upper_body ? 'Upper body/accessory terms are sourced from assigned role frames.' : 'No stable upper-body evidence was present.',
        lower_body: fields.lower_body ? 'Lower body/accessory terms are sourced from assigned role frames.' : 'No stable lower-body evidence was present.',
        upper_clothing: fields.upper_clothing ? 'Upper clothing terms are sourced from assigned role frames.' : 'No stable upper-clothing evidence was present.',
        lower_clothing: fields.lower_clothing ? 'Lower clothing terms are sourced from assigned role frames.' : 'No stable lower-clothing evidence was present.',
      },
      confidence: 0.92,
      frame_indexes: group.frameIndexes,
      ...fields,
      evidence_terms: evidenceTerms,
      missing_fields: missingFields,
      warnings: [],
    };
  });
}

function fiveFieldsForFrames(cache, appearances, stageFrames) {
  const stageSet = new Set(stageFrames);
  const fields = {
    identity: new Set(),
    upper_body: new Set(),
    lower_body: new Set(),
    upper_clothing: new Set(),
    lower_clothing: new Set(),
  };
  const framesByIndex = new Map(frameList(cache).map((frame) => [Number(frame.index), frame]));
  for (const appearance of appearances) {
    const slot = Number(appearance.source_id.slice('slot-'.length));
    for (const frameIndex of appearance.frame_indexes) {
      if (!stageSet.has(frameIndex)) continue;
      const caption = stringValue(framesByIndex.get(frameIndex)?.parsed?.charCaptions?.[slot]);
      for (const sourceTag of parseTags(caption)) {
        const sourceKey = normalizedKey(sourceTag);
        const targets = SPLIT_TERMS.get(sourceKey) ?? [canonicalTerm(sourceKey)];
        for (const target of targets) {
          const category = categoryForTerm(target);
          if (category === 'identity') fields.identity.add(target);
          if (category === 'body') {
            (LOWER_BODY_TERMS.has(target) ? fields.lower_body : fields.upper_body).add(target);
          }
          if (category === 'accessory') {
            (LOWER_ACCESSORY_TERMS.has(target) ? fields.lower_body : fields.upper_body).add(target);
          }
          if (category === 'clothing') {
            (LOWER_CLOTHING_TERMS.has(target) ? fields.lower_clothing : fields.upper_clothing).add(target);
          }
        }
      }
    }
  }
  return Object.fromEntries(Object.entries(fields).map(([key, values]) => [key, [...values].sort().join(', ')]));
}

function repairedStageLabel(scriptId, roleId, oldLabel, frameIndexes, cache, appearances) {
  const evidence = stageEvidenceKeys(cache, appearances, frameIndexes);
  if (scriptId === 'script-2-386d8895c7683ba6') {
    if (roleId === 'role-natsuki-subaru') {
      if (evidence.has('pants pull')) return '房间运动服 / 下装移位';
      if (evidence.has('track suit') || evidence.has('track jacket')) return '房间运动服';
      if (evidence.has('completely nude')) return evidence.has('animal collar') ? '酒店裸体 / 项圈' : '酒店裸体';
      return '卧室被褥遮挡';
    }
    if (roleId === 'role-regulus-corneas') {
      if (evidence.has('white coat') && (evidence.has('bottomless male') || evidence.has('bottomless'))) return '卧室下身裸体 / 白色外套';
      if (evidence.has('white coat')) return '白色外套';
      if (evidence.has('completely nude')) return '卧室裸体';
      return '卧室外观未明';
    }
    if (roleId.startsWith('role-dark-muscular-male')) {
      if (evidence.has('male black panties')) return '监牢上身裸体 / 黑色内裤';
      if (evidence.has('completely nude')) return '裸体';
      return '监牢衣着未明';
    }
    if (roleId === 'role-ram-re-zero' && normalizedKey(oldLabel) === '常服') return '地面衣着未明';
    if (roleId === 'role-emilia-re-zero' && frameIndexes.some((index) => index >= 152 && index <= 158)) {
      return evidence.has('bow panties') ? '白色连衣裙 / 蝴蝶结白色内裤' : '白色连衣裙 / 白色内裤';
    }
  }
  if (scriptId === 'script-toki-bunny-bbc-ntr-657f2ea003b35f20') {
    if (roleId === 'role-toki-bunny-blue-archive') {
      if (evidence.has('highleg thong leotard aside')) return '赌场兔女郎连体衣移位';
      if (evidence.has('highleg thong leotard')) return '赌场兔女郎高叉丁字连体衣';
      return '赌场衣着未明';
    }
    return '赌场衣着未明';
  }
  const label = stringValue(oldLabel).trim();
  if (hasChinese(label) && label !== '常服') return label;
  if (evidence.has('completely nude')) return '裸体';
  return '衣着未明';
}

function stageEvidenceKeys(cache, appearances, frameIndexes) {
  const wanted = new Set(frameIndexes);
  const keys = new Set();
  const framesByIndex = new Map(frameList(cache).map((frame) => [Number(frame.index), frame]));
  for (const appearance of appearances) {
    const slot = Number(appearance.source_id.slice('slot-'.length));
    for (const frameIndex of appearance.frame_indexes) {
      if (!wanted.has(frameIndex)) continue;
      for (const tag of parseTags(framesByIndex.get(frameIndex)?.parsed?.charCaptions?.[slot])) keys.add(normalizedKey(tag));
    }
  }
  return keys;
}

function buildRoleAssemblies(roles, existingAssemblies) {
  const existing = new Map(existingAssemblies.map((item) => [item.sourceRoleId, item]));
  return roles.map((roleItem) => {
    const previous = existing.get(roleItem.source_role_id) ?? {};
    return {
      ...copyExtra(previous, new Set(['sourceRoleId', 'displayLabel', 'sourceName', 'sourceAppearances', 'stages'])),
      sourceRoleId: roleItem.source_role_id,
      displayLabel: roleItem.display_name,
      sourceName: roleItem.display_name,
      sourceAppearances: roleItem.appearances.map((appearance) => ({
        sourceId: appearance.source_id,
        sourceKind: appearance.source_kind,
        frameIndexes: appearance.frame_indexes,
      })),
      stages: roleItem.stages.map((stage) => ({
        id: stage.stage_id,
        label: stage.label,
        frameIndexes: stage.frame_indexes,
        sourceSummary: unique([
          ...splitField(stage.identity),
          ...splitField(stage.upper_body),
          ...splitField(stage.lower_body),
          ...splitField(stage.upper_clothing),
          ...splitField(stage.lower_clothing),
        ]).join(', '),
        // Empty compatibility fields are omitted by the shared proofreader.
        // Construct the mirror the same way so a post-proofread dry run is a
        // semantic no-op.
        sourceParts: {
          ...(stage.identity ? { identity: stage.identity } : {}),
          ...(stage.upper_body ? { upperBody: stage.upper_body } : {}),
          ...(stage.lower_body ? { lowerBody: stage.lower_body } : {}),
          ...(stage.upper_clothing ? { upperClothing: stage.upper_clothing } : {}),
          ...(stage.lower_clothing ? { lowerClothing: stage.lower_clothing } : {}),
        },
      })),
    };
  });
}

function buildRolePromptMappings(roles, existingGroups) {
  const existing = new Map(existingGroups.map((group) => [group.sourceRoleId, group]));
  return roles.map((roleItem) => {
    const previous = existing.get(roleItem.source_role_id) ?? {};
    const previousRules = new Map((previous.rules ?? []).flatMap((rule) => (rule.sourceTerms ?? []).map((term) => [term.id, rule])));
    return {
      ...copyExtra(previous, new Set(['sourceRoleId', 'displayLabel', 'sourcePreview', 'rules'])),
      sourceRoleId: roleItem.source_role_id,
      displayLabel: roleItem.display_name,
      sourcePreview: roleItem.prompt_terms.map((term) => term.text).join(', '),
      rules: roleItem.prompt_terms.map((term) => {
        const oldRule = previousRules.get(term.id) ?? {};
        return {
          ...copyExtra(oldRule, new Set(['id', 'sourceTerms'])),
          id: `role-${slug(roleItem.source_role_id)}-${term.id}`,
          sourceTerms: [mappingTerm(term)],
        };
      }),
    };
  });
}

function buildScenePromptMappings(sceneTerms, existingGroups) {
  if (sceneTerms.length === 0) return [];
  const previous = existingGroups.find((group) => group.id === 'scene-ai') ?? {};
  const previousRules = new Map((previous.rules ?? []).flatMap((rule) => (rule.sourceTerms ?? []).map((term) => [term.id, rule])));
  return [{
    ...copyExtra(previous, new Set(['id', 'label', 'rules'])),
    id: 'scene-ai',
    label: '场景',
    rules: sceneTerms.map((term) => {
      const oldRule = previousRules.get(term.id) ?? {};
      return {
        ...copyExtra(oldRule, new Set(['id', 'sourceTerms'])),
        id: `scene-${term.id}`,
        sourceTerms: [mappingTerm(term)],
      };
    }),
  }];
}

function mappingTerm(term) {
  return {
    id: term.id,
    text: term.text,
    category: term.category,
    sourcePhrase: term.source_phrase,
    sourceLocation: term.source_location,
    frameIndexes: term.frame_indexes,
    sourceOccurrences: (term.source_occurrences ?? []).map((item) => ({
      frameIndex: item.frame_index,
      sourceLocation: item.source_location,
    })),
  };
}

function categoryForTerm(term) {
  if (IDENTITY_TERMS.has(term)) return 'identity';
  if (BODY_TERMS.has(term)) return 'body';
  if (CLOTHING_TERMS.has(term)) return 'clothing';
  if (CLOTHING_STATE_TERMS.has(term)) return 'clothingState';
  if (ACCESSORY_TERMS.has(term)) return 'accessory';
  return '';
}

function canonicalTerm(term) {
  return TERM_NORMALIZATIONS.get(term) ?? term;
}

function preferredSourcePhrase(entry) {
  const ranked = [...entry.sourcePhrases.entries()].sort(
    (a, b) => b[1] - a[1] || a[0].localeCompare(b[0]),
  );
  return (
    ranked.find(([phrase]) => normalizedKey(phrase) !== entry.text)?.[0] ??
    ranked[0]?.[0] ??
    entry.text
  );
}

function isAlreadyRepaired(currentRoles, specs) {
  if (currentRoles.length !== specs.length) return false;
  const current = new Map(currentRoles.map((item) => [item.source_role_id, item]));
  return specs.every((spec) => {
    const roleItem = current.get(spec.id);
    return roleItem?.display_name === spec.display
      && (roleItem.prompt_terms ?? []).every((term) => ALLOWED_CATEGORIES.has(term.category));
  });
}

function counts(cache) {
  const roles = cache.aiRoleExtraction?.roles ?? [];
  return {
    roles: roles.length,
    stages: roles.reduce((sum, item) => sum + (item.stages?.length ?? 0), 0),
    roleTerms: roles.reduce((sum, item) => sum + (item.prompt_terms?.length ?? 0), 0),
    sceneTerms: cache.aiRoleExtraction?.scene_terms?.length ?? 0,
    roleGroups: cache.mapping?.rolePromptReplacements?.length ?? 0,
    roleRules: (cache.mapping?.rolePromptReplacements ?? []).reduce((sum, group) => sum + (group.rules?.length ?? 0), 0),
    sceneGroups: cache.mapping?.scenePromptReplacements?.length ?? 0,
    sceneRules: (cache.mapping?.scenePromptReplacements ?? []).reduce((sum, group) => sum + (group.rules?.length ?? 0), 0),
  };
}

function role(id, display, canonical, franchise, templateIds, owns) {
  return { id, display, canonical, franchise, templateIds, owns };
}

function parseArgs(args) {
  const parsed = { cacheDir: '', report: '', backupDir: '', apply: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1] ?? '';
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report') parsed.report = value;
    if (key === 'backup-dir') parsed.backupDir = value;
  }
  return parsed;
}

function parseTags(caption) {
  return stringValue(caption).split(',').map(cleanSourceTag).filter(Boolean);
}

function cleanSourceTag(value) {
  let text = stringValue(value).trim();
  text = text.replace(/^[-+]?\d+(?:\.\d+)?::\s*/, '').replace(/\s*::$/, '').trim();
  return text.replace(/\s+/g, ' ');
}

function normalizedKey(value) {
  return cleanSourceTag(value).toLowerCase();
}

function frameList(cache) {
  return Array.isArray(cache.scriptSnapshot?.frames) ? cache.scriptSnapshot.frames : [];
}

function sortedInts(values) {
  return [...new Set([...values].map(Number).filter(Number.isFinite))].sort((a, b) => a - b);
}

function unique(values) {
  return [...new Set(values.filter((value) => stringValue(value).trim()))];
}

function splitField(value) {
  return stringValue(value).split(',').map((item) => item.trim()).filter(Boolean);
}

function copyExtra(value, excluded) {
  return Object.fromEntries(Object.entries(value ?? {}).filter(([key]) => !excluded.has(key)));
}

function categoryRank(category) {
  return ['identity', 'body', 'clothing', 'clothingState', 'accessory'].indexOf(category);
}

function countBy(values, selector) {
  const result = {};
  for (const value of values) {
    const key = selector(value);
    result[key] = (result[key] ?? 0) + 1;
  }
  return result;
}

function stableJson(value) {
  return JSON.stringify(value);
}

function diffPaths(left, right, prefix = '') {
  if (JSON.stringify(left) === JSON.stringify(right)) return [];
  if (left == null || right == null || typeof left !== 'object' || typeof right !== 'object') return [prefix || '$'];
  if (Array.isArray(left) || Array.isArray(right)) {
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return [prefix || '$'];
    return left.flatMap((value, index) => diffPaths(value, right[index], `${prefix}[${index}]`));
  }
  const keys = new Set([...Object.keys(left), ...Object.keys(right)]);
  return [...keys].flatMap((key) => diffPaths(left[key], right[key], prefix ? `${prefix}.${key}` : key));
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function slug(value) {
  return normalizedKey(value).replace(/[^a-z0-9\u4e00-\u9fff]+/g, '-').replace(/^-+|-+$/g, '') || 'term';
}

function setOf(value) {
  return new Set(value.split('\n').map((item) => item.trim()).filter(Boolean));
}

function inRanges(value, ranges) {
  return ranges.some(([start, end]) => value >= start && value <= end);
}

function hasChinese(value) {
  return /[\u3400-\u9fff]/.test(stringValue(value));
}
