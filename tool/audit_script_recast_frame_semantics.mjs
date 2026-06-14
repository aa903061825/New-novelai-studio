import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'org.exception0x0194',
  'nai3_autodraw',
  'novel_studio',
  'script_recast',
  'cache',
);
const defaultClassificationCache =
  'E:/NAI\u7684\u811a\u672c\u7fa4/tag_classification_cache.json';

const options = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);
const classificationCache = loadJson(
  options.classificationCache ?? defaultClassificationCache,
  {},
);
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Cache directory does not exist: ${cacheDir}`);
}

const rows = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort()
  .map((file) => auditCache(path.join(cacheDir, file)));

const issueRows = rows.filter((row) => row.issue_count > 0);
const summary = {
  cache_dir: cacheDir,
  cache_count: rows.length,
  role_count: sum(rows, 'role_count'),
  stage_count: sum(rows, 'stage_count'),
  checked_frame_count: sum(rows, 'checked_frame_count'),
  issue_count: sum(rows, 'issue_count'),
  mixed_stage_issue_count: sum(rows, 'mixed_stage_issue_count'),
  label_state_issue_count: sum(rows, 'label_state_issue_count'),
  field_route_issue_count: sum(rows, 'field_route_issue_count'),
  field_source_issue_count: sum(rows, 'field_source_issue_count'),
  ui_label_issue_count: sum(rows, 'ui_label_issue_count'),
  issue_cache_count: issueRows.length,
  issue_samples: issueRows.slice(0, options.maxPrint).map((row) => ({
    file_name: row.file_name,
    script_name: row.script_name,
    issue_count: row.issue_count,
    issues: row.issues.slice(0, 12),
  })),
};

console.log(JSON.stringify(summary, null, 2));
if (options.reportPath) {
  fs.mkdirSync(path.dirname(path.resolve(options.reportPath)), {
    recursive: true,
  });
  fs.writeFileSync(
    options.reportPath,
    `${JSON.stringify({ ...summary, rows }, null, 2)}\n`,
    'utf8',
  );
}

function auditCache(filePath) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const frames = new Map();
  for (const frame of cache.scriptSnapshot?.frames ?? []) {
    frames.set(Number(frame.index), frame);
  }
  const issues = [];
  const roles = Array.isArray(cache.aiRoleExtraction?.roles)
    ? cache.aiRoleExtraction.roles
    : [];
  let stageCount = 0;
  let checkedFrameCount = 0;
  for (const role of roles) {
    const appearances = Array.isArray(role.appearances) ? role.appearances : [];
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      stageCount += 1;
      const frameStates = [];
      const sourceTerms = new Set();
      for (const frameIndex of intList(stage.frame_indexes)) {
        const captionTexts = captionsForRoleFrame(frames, appearances, frameIndex);
        if (captionTexts.length === 0) continue;
        checkedFrameCount += 1;
        const tags = captionTexts.flatMap(parseTags);
        for (const tag of tags) {
          sourceTerms.add(normalizedTagKey(tag));
          for (const equivalent of sourceEquivalentTermsForTag(tag)) {
            sourceTerms.add(equivalent);
          }
        }
        frameStates.push({
          frame_index: frameIndex,
          key: frameReplacementKey(tags),
        });
      }
      auditMixedFrameStates({ issues, role, stage, frameStates });
      auditLabelState({ issues, role, stage, frameStates });
      auditFieldTerms({ issues, role, stage, sourceTerms });
    }
  }
  const counts = countIssueKinds(issues);
  return {
    file_name: path.basename(filePath),
    script_name: stringValue(cache.scriptName),
    role_count: roles.length,
    stage_count: stageCount,
    checked_frame_count: checkedFrameCount,
    issue_count: issues.length,
    ...counts,
    issues,
  };
}

function auditMixedFrameStates({ issues, role, stage, frameStates }) {
  const keys = canonicalFrameStateKeys(
    uniqueExact(frameStates.map((item) => item.key).filter(Boolean)),
  );
  const concreteKeys = keys.filter((key) => key !== 'unspecified');
  if (
    keys.includes('unspecified') &&
    (concreteKeys.length <= 1 ||
      concreteKeys.every((key) => !key.startsWith('state:')))
  ) {
    return;
  }
  if (hasOnlyWeakStateDetailDifferences(concreteKeys)) return;
  if (isComplementaryPartialClothingEvidence(concreteKeys)) return;
  if (keys.length <= 1) return;
  issues.push({
    kind: 'mixed_stage_replacement_state',
    role_id: stringValue(role.source_role_id),
    role_display_name: stringValue(role.display_name),
    stage_id: stringValue(stage.stage_id),
    label: stringValue(stage.label),
    keys,
    frame_samples: frameStates.slice(0, 12),
  });
}

function canonicalFrameStateKeys(keys) {
  let canonical = keys.map(canonicalFrameStateKeyForReview);
  for (const [state, sparse] of [
    ['topless', 'no-lower-clothing'],
    ['bottomless', 'no-upper-clothing'],
  ]) {
    const concrete = canonical.filter(
      (key) =>
        key.startsWith(`state:${state}:`) &&
        key !== `state:${state}:${sparse}`,
    );
    const sparseKeys = new Set([
      `state:${state}`,
      `state:${state}:${sparse}`,
    ]);
    if (uniqueExact(concrete).length === 1 && canonical.some((key) => sparseKeys.has(key))) {
      const replacement = concrete[0];
      canonical = canonical.map((key) => (sparseKeys.has(key) ? replacement : key));
    }
  }
  return uniqueExact(canonical);
}

function canonicalFrameStateKeyForReview(key) {
  const value = stringValue(key);
  for (const prefix of ['state:topless:', 'state:bottomless:', 'state:nude-with:']) {
    if (!value.startsWith(prefix)) continue;
    const terms = canonicalReplacementTerms(value.slice(prefix.length).split('|'))
      .filter(Boolean)
      .sort();
    return `${prefix}${terms.join('|') || 'unspecified'}`;
  }
  return value;
}

function hasOnlyWeakStateDetailDifferences(keys) {
  if (keys.length <= 1) return true;
  const concrete = keys.filter((key) => key && key !== 'unspecified');
  if (concrete.length <= 1) return true;
  const stateNames = uniqueExact(
    concrete.map((key) => key.match(/^state:([^:]+)/)?.[1] ?? ''),
  ).filter(Boolean);
  if (stateNames.length !== 1) return false;
  const criticalSignatures = uniqueExact(
    concrete.map((key) =>
      key
        .split(':')
        .slice(2)
        .join(':')
        .split('|')
        .filter(Boolean)
        .filter((term) =>
          !['footwear', 'no-footwear'].includes(
            baseReplacementTerm(term),
          ),
        )
        .sort()
        .join('|'),
    ),
  );
  if (criticalSignatures.length === 1) return true;
  return concrete.every((key) => {
    const detail = key.split(':').slice(2).join(':');
    if (!detail || /^no-(?:upper|lower)-clothing$/.test(detail)) return true;
    return detail
      .split('|')
      .filter(Boolean)
      .every((term) =>
        ['footwear', 'no-footwear'].includes(baseReplacementTerm(term)),
      );
  });
}

function isComplementaryPartialClothingEvidence(keys) {
  const concrete = keys.filter((key) => key && key !== 'unspecified');
  if (concrete.length <= 1) return true;
  if (concrete.some((key) => key.startsWith('state:'))) return false;
  const slotTerms = new Map();
  for (const key of concrete) {
    for (const part of key.split(';')) {
      const match = part.match(/^(upper|lower):(.+)$/);
      if (!match) return false;
      const slot = match[1];
      const terms = match[2].split('|').filter(Boolean);
      const current = slotTerms.get(slot) ?? new Set();
      for (const term of terms) current.add(term);
      slotTerms.set(slot, current);
    }
  }
  for (const terms of slotTerms.values()) {
    const bases = uniqueExact([...terms].map(baseReplacementTerm));
    if (bases.length !== terms.size) return false;
  }
  return true;
}

function auditLabelState({ issues, role, stage, frameStates }) {
  const label = stringValue(stage.label);
  if (!hasChinese(label) || /角色|[A-Za-z]{3,}/.test(label)) {
    issues.push({
      kind: 'ui_stage_label_not_fully_chinese',
      role_id: stringValue(role.source_role_id),
      stage_id: stringValue(stage.stage_id),
      label,
    });
  }
  const keys = frameStates.map((item) => item.key).filter(Boolean);
  if (keys.length === 0) return;
  const requireAll = (predicate, issue) => {
    const canonicalKeys = canonicalFrameStateKeys(uniqueExact(keys));
    if (canonicalKeys.length > 0 && canonicalKeys.every(predicate)) return;
    const bad = frameStates.filter((item) => item.key && !predicate(item.key));
    if (bad.length === 0) return;
    issues.push({
      kind: issue,
      role_id: stringValue(role.source_role_id),
      role_display_name: stringValue(role.display_name),
      stage_id: stringValue(stage.stage_id),
      label,
      frame_samples: bad.slice(0, 12),
    });
  };
  if (label.includes('浴巾')) {
    requireAll((key) => key === 'state:towel', 'label_towel_without_towel_frames');
  }
  if (label.includes('上身裸体')) {
    requireAll(
      (key) => key.startsWith('state:topless'),
      'label_topless_without_topless_frames',
    );
  } else if (label.includes('下身裸体')) {
    requireAll(
      (key) => key.startsWith('state:bottomless'),
      'label_bottomless_without_bottomless_frames',
    );
  } else if (label.includes('裸体')) {
    requireAll(
      (key) => key.startsWith('state:nude'),
      'label_nude_without_nude_frames',
    );
  }
  if (label.includes('泳装') || label.includes('比基尼')) {
    requireAll(
      (key) => /bikini|swimsuit/.test(key),
      'label_swimsuit_without_swimsuit_frames',
    );
  }
}

function auditFieldTerms({ issues, role, stage, sourceTerms }) {
  for (const [field, value] of Object.entries(stageFields(stage))) {
    for (const term of parseTags(value)) {
      const normalized = normalizedTagKey(term);
      const category = categoryForTag(term);
      if (!fieldAllowsCategory(field, category)) {
        issues.push({
          kind: 'field_route_issue',
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          label: stringValue(stage.label),
          field,
          term,
          category,
        });
        continue;
      }
      if (!sourceTerms.has(normalized) && field !== 'identity') {
        issues.push({
          kind: 'field_source_issue',
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          label: stringValue(stage.label),
          field,
          term,
        });
      }
    }
  }
}

function sourceEquivalentTermsForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return [];
  const direct = [];
  if (/\bglowing vine(?: like)? dendro tattoo\b/.test(normalized)) {
    direct.push('glowing vine dendro tattoo');
  }
  if (!hasTornReplacementEvidence(normalized)) return uniqueExact(direct);
  const color = firstColorForSourceEquivalent(normalized);
  const prefix = color ? `${color} ` : '';
  const terms = [...direct];
  if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(normalized)) {
    terms.push(`${prefix}torn pantyhose`.trim());
  }
  if (/\b(panties|underwear|briefs)\b/.test(normalized)) {
    terms.push(`${prefix}torn underwear`.trim());
  }
  if (/\b(bikini bottoms?|bikini bottom)\b/.test(normalized)) {
    terms.push(`${prefix}torn bikini bottom`.trim());
  }
  if (/\b(skirt)\b/.test(normalized)) terms.push(`${prefix}torn skirt`.trim());
  if (/\b(pants|shorts|trousers)\b/.test(normalized)) {
    terms.push(`${prefix}torn pants`.trim());
  }
  if (/\b(bodysuit)\b/.test(normalized)) terms.push(`${prefix}torn bodysuit`.trim());
  if (/\b(leotard)\b/.test(normalized)) terms.push(`${prefix}torn leotard`.trim());
  if (/\b(swimsuit|bikini)\b/.test(normalized)) {
    terms.push(`${prefix}torn swimsuit`.trim());
  }
  if (/\b(bra)\b/.test(normalized)) terms.push(`${prefix}torn bra`.trim());
  if (/\b(dress)\b/.test(normalized)) terms.push(`${prefix}torn dress`.trim());
  if (/\b(shirt|blouse|halter top|top)\b/.test(normalized)) terms.push(`${prefix}torn shirt`.trim());
  if (/\b(jacket|coat|suit)\b/.test(normalized)) {
    terms.push(`${prefix}torn outerwear`.trim());
  }
  return uniqueExact(terms.map(normalizedTagKey).filter(Boolean));
}

function firstColorForSourceEquivalent(normalized) {
  for (const color of [
    'dark blue',
    'light blue',
    'black',
    'white',
    'pink',
    'red',
    'blue',
    'green',
    'yellow',
    'purple',
    'brown',
    'gray',
    'grey',
    'gold',
    'golden',
    'orange',
  ]) {
    const pattern = new RegExp(`\\b${color.replace(/\s+/g, '\\s+')}\\b`);
    if (!pattern.test(normalized)) continue;
    if (color === 'grey') return 'gray';
    if (color === 'golden') return 'gold';
    return color.replace(/\s+/g, '-');
  }
  return '';
}

function captionsForRoleFrame(frames, appearances, frameIndex) {
  const frame = frames.get(Number(frameIndex));
  if (!frame) return [];
  const captions = Array.isArray(frame.parsed?.charCaptions)
    ? frame.parsed.charCaptions
    : [];
  const result = [];
  for (const appearance of appearances) {
    if (!intList(appearance.frame_indexes).includes(frameIndex)) continue;
    const sourceId = String(appearance.source_id ?? '').toLowerCase();
    if (sourceId === 'base' || sourceId === 'global') {
      const caption = frame.parsed?.baseCaption;
      if (stringValue(caption).trim()) result.push(caption);
      continue;
    }
    const slot = Number(String(appearance.source_id ?? '').replace(/^slot-/, ''));
    const caption = captions[slot];
    if (stringValue(caption).trim()) result.push(caption);
  }
  return result;
}

function frameReplacementKey(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const actualTowel = hasActualTowelForTags(normalized);
  const upper = [];
  const lower = [];
  for (const tag of normalized) {
    const term = replacementClothingTerm(tag, normalized);
    if (!term) continue;
    if (isLowerReplacementTerm(term)) lower.push(term);
    else upper.push(term);
  }
  const canonicalUpper = canonicalReplacementTerms(upper);
  const canonicalLower = canonicalReplacementTerms(lower);
  const state = new Set();
  for (const tag of normalized) {
    if (isHoldingTowelTerm(tag)) continue;
    if (/\b(breasts? out)\b/.test(tag)) continue;
    if (isNonRoleReplacementStateTerm(tag)) continue;
    if (/\b(topless|topless female)\b/.test(tag)) state.add('topless');
    if (/\b(bottomless)\b/.test(tag)) state.add('bottomless');
    if (/\b(nude|naked|completely nude|no clothes)\b/.test(tag)) {
      state.add('nude');
    }
  }
  const upperKey = canonicalUpper.sort().join('|');
  const lowerKey = canonicalLower.sort().join('|');
  if (actualTowel) return 'state:towel';
  if (state.has('topless')) {
    return `state:topless:${lowerKey || 'no-lower-clothing'}`;
  }
  if (state.has('bottomless')) {
    const clothing = [upperKey, lowerKey].filter(Boolean).join('|');
    return `state:bottomless:${clothing || 'no-upper-clothing'}`;
  }
  if (state.has('nude')) {
    const nudeLowerKey = uniqueExact(
      canonicalLower.filter(
        (term) =>
          baseReplacementTerm(term) !== 'no-underwear' &&
          baseReplacementTerm(term) !== 'footwear',
      ),
    )
      .sort()
      .join('|');
    const clothing = [upperKey, nudeLowerKey].filter(Boolean).join('|');
    return clothing ? `state:nude-with:${clothing}` : 'state:nude';
  }
  const core = coreClothingKey({
    upper: canonicalUpper,
    lower: canonicalLower,
  });
  if (core) return core;
  return 'unspecified';
}

function canonicalReplacementTerms(terms) {
  const uniqueTerms = uniqueExact(terms);
  const bases = new Set(uniqueTerms.map(baseReplacementTerm));
  const contradictionFiltered = uniqueTerms.filter((term) => {
    const base = baseReplacementTerm(term);
    if (bases.has('no-underwear') && ['underwear', 'underwear-only'].includes(base)) {
      return false;
    }
    if (bases.has('no-bra') && ['bra', 'lace-bra'].includes(base)) return false;
    if (bases.has('no-overalls') && base === 'overalls') return false;
    return true;
  });
  const specificityFiltered = contradictionFiltered.filter((term) => {
    const base = baseReplacementTerm(term);
    const modifiers = replacementModifierSet(term);
    if (modifiers.size === 0) return true;
    return !contradictionFiltered.some((other) => {
      if (other === term || baseReplacementTerm(other) !== base) return false;
      const otherModifiers = replacementModifierSet(other);
      return (
        otherModifiers.size > modifiers.size &&
        [...modifiers].every((modifier) => otherModifiers.has(modifier))
      );
    });
  });
  const basesWithSpecificTerms = new Set(
    specificityFiltered
      .filter((term) => stringValue(term).includes(':'))
      .map(baseReplacementTerm),
  );
  return specificityFiltered.filter((term) => {
    const base = baseReplacementTerm(term);
    return stringValue(term).includes(':') || !basesWithSpecificTerms.has(base);
  });
}

function coreClothingKey({ upper, lower }) {
  const upperCore = uniqueExact(
    upper.filter((term) =>
      [
        'bikini',
        'micro-bikini',
        'maid-bikini',
        'swimsuit',
        'one-piece-swimsuit',
        'school-swimsuit',
        'bra',
        'lace-bra',
        'lingerie-set',
        'babydoll',
        'bodysuit',
        'leotard',
        'uniform',
        'kimono',
        'dress',
        'shirt',
        'outerwear',
        'gloves',
        'tank-top',
        'camisole',
      ].includes(baseReplacementTerm(term)),
    ),
  ).sort();
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTerm(term) === 'bra')) {
    upperCore.splice(upperCore.findIndex((term) => baseReplacementTerm(term) === 'bra'), 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTerm(term) === 'bikini')) {
    const swimsuitIndex = upperCore.findIndex((term) => baseReplacementTerm(term) === 'swimsuit');
    if (swimsuitIndex >= 0) upperCore.splice(swimsuitIndex, 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTerm(term) === 'uniform')) {
    const shirtIndex = upperCore.findIndex((term) => baseReplacementTerm(term) === 'shirt');
    if (shirtIndex >= 0) upperCore.splice(shirtIndex, 1);
  }
  if (upperCore.length > 1 && upperCore.some((term) => baseReplacementTerm(term) === 'outerwear')) {
    const shirtIndex = upperCore.findIndex((term) => baseReplacementTerm(term) === 'shirt');
    if (shirtIndex >= 0) upperCore.splice(shirtIndex, 1);
  }
  const lowerCore = uniqueExact(
    lower.filter((term) =>
      [
        'dress',
        'pants',
        'bikini-bottom',
        'bikini-bottom-only',
        'side-tie-bikini-bottom',
        'fundoshi',
        'swimsuit-bottom',
        'underwear',
        'underwear-only',
        'underwear-set',
        'mechanical-underwear',
        'no-underwear',
        'no-footwear',
      ].includes(baseReplacementTerm(term)),
    ),
  ).sort();
  if (lowerCore.some((term) => baseReplacementTerm(term) === 'dress')) {
    for (const term of ['shirt']) {
      const index = upperCore.findIndex((candidate) => baseReplacementTerm(candidate) === term);
      if (index >= 0) upperCore.splice(index, 1);
    }
  }
  if (upperCore.length > 0) return `upper:${upperCore.join('|')}`;
  if (lowerCore.length > 0) return `lower:${lowerCore.join('|')}`;
  if (lower.some((term) => baseReplacementTerm(term) === 'underwear')) {
    return 'lower:underwear';
  }
  if (lower.some((term) => baseReplacementTerm(term) === 'no-underwear')) {
    return 'lower:no-underwear';
  }
  return '';
}

function replacementClothingTerm(tag, allTags = []) {
  if (isOtherCharacterClothingActionTag(tag)) return '';
  if (isHeldOrUnwornClothingTag(tag, allTags)) return '';
  if (isVisualReplacementEvidenceTerm(tag)) {
    const visual = visualReplacementTerm(tag, allTags);
    if (visual) return visual;
  }
  if (isNonRoleReplacementStateTerm(tag)) return '';
  if (isTransientClothingActionTerm(tag)) return '';
  if (isActualTowelTerm(tag)) return 'towel';
  if (/\b(no panties|no underwear)\b/.test(tag)) return 'no-underwear';
  if (/\b(shoes? off|shoe removed|shoes removed)\b/.test(tag)) return 'no-footwear';
  return visualReplacementTerm(tag, allTags);
}

function visualReplacementTerm(tag, allTags = []) {
  const modifiers = visualReplacementModifiers(tag, allTags);
  const term = (base) =>
    modifiers.length > 0 ? `${base}:${modifiers.join('+')}` : base;
  if (/\b(babydoll|baby doll|negligee|chemise|teddy)\b/.test(tag)) {
    return term('babydoll');
  }
  if (/\b(lingerie set|underwear set)\b/.test(tag)) return term('underwear-set');
  if (/\b(lingerie|sleepwear|nightgown)\b/.test(tag)) return term('lingerie-set');
  if (/\b(bra).*(panties|underwear)\b|\b(panties|underwear).*(bra)\b/.test(tag)) {
    return term('underwear-set');
  }
  if (/\b(mechanical panties|mechanical underwear)\b/.test(tag)) {
    return term('mechanical-underwear');
  }
  if (/\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag)) {
    return term('bunny-suit');
  }
  if (/\b(fundoshi|loincloth)\b/.test(tag)) return term('fundoshi');
  if (/\bmale\b.*\bswimsuit\b/.test(tag)) return term('swimsuit-bottom');
  if (/\b(bikini bottom only)\b/.test(tag)) return term('bikini-bottom-only');
  if (/\b(side tie bikini bottom|side-tie bikini bottom)\b/.test(tag)) {
    return term('side-tie-bikini-bottom');
  }
  if (/\b(bikini bottoms?)\b/.test(tag)) return term('bikini-bottom');
  if (/\b(micro bikini)\b/.test(tag)) return term('micro-bikini');
  if (/\b(maid bikini)\b/.test(tag)) return term('maid-bikini');
  if (/\b(bikini)\b/.test(tag)) return term('bikini');
  if (/\b(one[- ]piece swimsuit)\b/.test(tag)) return term('one-piece-swimsuit');
  if (/\b(school swimsuit|old school swimsuit)\b/.test(tag)) return term('school-swimsuit');
  if (/\b(swimsuit|swimwear)\b/.test(tag)) return term('swimsuit');
  if (/\b(bodysuit)\b/.test(tag)) return term('bodysuit');
  if (/\b(leotard)\b/.test(tag)) return term('leotard');
  if (/\b(underwear only)\b/.test(tag)) return term('underwear-only');
  if (/\b(panty|panties|underwear|briefs)\b/.test(tag)) return term('underwear');
  if (/\b(lace bra)\b/.test(tag)) return term('lace-bra');
  if (/\b(bra)\b/.test(tag)) return term('bra');
  if (/\b(gloves?)\b/.test(tag)) return term('gloves');
  if (/\b(overalls?|overall skirt)\b/.test(tag)) return term('overalls');
  if (/\b(camisole)\b/.test(tag)) return term('camisole');
  if (/\b(tank top|vest)\b/.test(tag)) return term('tank-top');
  if (/\b(uniform|serafuku|maid uniform|naval uniform|military uniform|tennis uniform|basketball uniform)\b/.test(tag)) {
    return term('uniform');
  }
  if (/\b(kimono|yukata|naked kimono)\b/.test(tag)) return term('kimono');
  if (/\b(dress violently torn apart|torn fabric scraps? hanging|fabric scraps? hanging|torn dress remnants?)\b/.test(tag)) {
    return 'dress:torn';
  }
  if (/\b(dress|skirt)\b/.test(tag)) return term('dress');
  if (/\b(shirt|blouse|crop top|cropped shirt|halter top)\b/.test(tag)) return term('shirt');
  if (/\b(jacket|coat|hoodie|hooded jacket|blazer)\b/.test(tag)) return term('outerwear');
  if (/\b(shorts|pants|trousers|buruma)\b/.test(tag)) return term('pants');
  if (/\b(thighhighs?|pantyhose|stockings?|socks?)\b/.test(tag)) return term('legwear');
  if (/\b(shoes?|boots?|sneakers?|heels?)\b/.test(tag)) return term('footwear');
  return '';
}

function visualReplacementModifiers(tag, allTags = []) {
  const modifiers = [];
  const add = (key, pattern) => {
    if (pattern.test(tag)) modifiers.push(key);
  };
  add('dark-blue', /\bdark blue\b/);
  add('light-blue', /\blight ?blue\b/);
  add('black', /\bblack\b/);
  add('white', /\bwhite\b/);
  add('pink', /\bpink\b/);
  add('red', /\bred\b/);
  add('blue', /\bblue\b/);
  add('green', /\bgreen\b/);
  add('yellow', /\byellow\b/);
  add('purple', /\bpurple\b/);
  add('brown', /\bbrown\b/);
  add('gray', /\bgr[ae]y\b/);
  add('gold', /\bgold(?:en)?\b/);
  add('orange', /\borange\b/);
  add('lace', /\blace|lacy\b/);
  add('satin', /\bsatin\b/);
  add('silk', /\bsilk|silky\b/);
  add('leather', /\bleather\b/);
  add('latex', /\blatex\b/);
  add('sheer', /\bsheer|see[- ]through|transparent\b/);
  add('fishnet', /\bfishnet|mesh\b/);
  add('frilled', /\bfrill|frilled|frilly|ruffled\b/);
  add('striped', /\bstriped|stripes\b/);
  add('plaid', /\bplaid|checkered\b/);
  add('floral', /\bfloral|flower print\b/);
  add('ribboned', /\bribbon|bow\b/);
  add('aside', /\b(aside|pulled aside|pull aside|swimsuit pull|bikini pull|panty pull|panties pull|bra pull|leotard aside|bikini bottom aside|panties aside|swimsuit aside|shirt aside|skirt aside)\b/);
  add('lifted', /\b(bikini top lift|top lift|shirt lift|skirt lift|dress lift|lifted skirt|lifted dress|lifted shirt|lifted bra)\b/);
  add('open', /\b(open shorts|opened shorts|shorts open|open pants|opened pants|pants open|open shirt|opened shirt|shirt open|open_shorts|open_shirt)\b/);
  add('under-skirt', /\bunder skirt\b/);
  if (hasTornReplacementEvidence(tag)) modifiers.push('torn');
  if (
    /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag) &&
    !modifiers.some(isColorReplacementModifier)
  ) {
    const contextualColor = contextualBunnySuitColor(allTags);
    if (contextualColor) modifiers.push(contextualColor);
  }
  return uniqueExact(modifiers);
}

function isColorReplacementModifier(modifier) {
  return new Set([
    'dark-blue',
    'light-blue',
    'black',
    'white',
    'pink',
    'red',
    'blue',
    'green',
    'yellow',
    'purple',
    'brown',
    'gray',
    'gold',
    'orange',
  ]).has(modifier);
}

function contextualBunnySuitColor(allTags) {
  const tags = uniqueExact(
    allTags.map(normalizedTagKey).filter((tag) => tag.length > 0),
  );
  const colors = [
    ['dark-blue', /\bdark blue\b/],
    ['light-blue', /\blight ?blue\b/],
    ['black', /\bblack\b/],
    ['white', /\bwhite\b/],
    ['pink', /\bpink\b/],
    ['red', /\bred\b/],
    ['blue', /\bblue\b/],
    ['green', /\bgreen\b/],
    ['yellow', /\byellow\b/],
    ['purple', /\bpurple\b/],
    ['brown', /\bbrown\b/],
    ['gray', /\bgr[ae]y\b/],
    ['gold', /\bgold(?:en)?\b/],
    ['orange', /\borange\b/],
  ];
  const candidates = [];
  for (const [key, colorPattern] of colors) {
    const signals = tags.filter((tag) =>
      colorPattern.test(tag) &&
      /\b(stockings?|thighhighs?|socks?|legwear|neck ribbon|ribbon|bow|brooch|arm warmers?|sleeves?|bunny ears?|high heels?|heels?|garter belt|collar)\b/.test(tag),
    );
    const explicitSameSuit = tags.some((tag) =>
      colorPattern.test(tag) &&
      /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag),
    );
    if (explicitSameSuit || signals.length >= 2) candidates.push(key);
  }
  const uniqueCandidates = uniqueExact(candidates);
  return uniqueCandidates.length === 1 ? uniqueCandidates[0] : '';
}

function isVisualReplacementEvidenceTerm(tag) {
  return isVisualDisplacementTerm(tag) || hasTornReplacementEvidence(tag);
}

function hasTornReplacementEvidence(tag) {
  if (/\b(dress violently torn apart|torn fabric scraps? hanging|fabric scraps? hanging|torn dress remnants?)\b/.test(tag)) {
    return true;
  }
  return /\b(torn(?:ed)?|ripped|damaged|shredded)\b/.test(tag) &&
    /\b(panties|underwear|bra|bodysuit|leotard|swimsuit|bikini|dress|skirt|shirt|blouse|halter top|top|jacket|coat|suit|pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(tag);
}

function isVisualDisplacementTerm(tag) {
  return /\b(aside|pulled aside|pull aside|swimsuit pull|bikini pull|panty pull|panties pull|bra pull|leotard aside|bikini bottom aside|panties aside|swimsuit aside|shirt aside|skirt aside|bikini top lift|top lift|shirt lift|skirt lift|dress lift|open shorts|open shirt|open_shorts|open_shirt|shoes? off|shoe removed|shoes removed)\b/.test(
    tag,
  );
}

function isHeldOrUnwornClothingTag(tag, allTags) {
  if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear) pull\b/.test(tag)) {
    return true;
  }
  if (
    /\b(bunny suit|bunny girl outfit|bunny outfit)\b/.test(tag) &&
    (/\b(grab|grabbing|holding|pull(?:ed|ing)? down|pulling|pulled)\b/.test(tag) ||
      allTags.some((term) => /\b(nude male|naked male|faceless male|1 male|2 male|male nude)\b/.test(term)))
  ) {
    return true;
  }
  if (isUnwornOrDroppedClothingTag(tag)) return true;
  if (allTags.some((term) => /\b(holding unworn clothes|unworn clothes|discarded clothes|clothes scattered|clothes on floor|scattered around)\b/.test(term))) {
    return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom|panty|panties|underwear|clothes|bra|skirt|pants|dress|shirt|suit|gloves?|stockings?|pantyhose|thighhighs?|socks?|shoes?|boots?)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*bikinis?|holding bikini bottom)\b/.test(term))) {
    return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*pant(?:y|ies)|holding .*underwear|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing other(?:'?s| s) pant(?:y|ies)|panty pull)\b/.test(term))) {
    return /\b(panty|panties|underwear)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*bra|tearing .*bra|tearing clothes with bra|removing other(?:'?s| s) bra)\b/.test(term))) {
    return /\b(bra)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding .*skirt|tearing .*skirt|removing other(?:'?s| s) skirt)\b/.test(term))) {
    return /\b(skirt)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(pull(?:ing)? off girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl pant)\b/.test(term))) {
    return /\b(pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(tag);
  }
  if (allTags.some((term) => /\b(holding pants|pants on head|unbuttoning other(?:'?s| s) shirt|removing other(?:'?s| s) pant(?:y|ies))\b/.test(term))) {
    return /\b(pants|shirt|panty|panties|underwear)\b/.test(tag);
  }
  return false;
}

function isUnwornOrDroppedClothingTag(tag) {
  return /\b(bikini|bikini bottom|side tie bikini bottom|side-tie bikini bottom|panty|panties|underwear|clothes|bra|skirt|pants|dress|shirt|suit|gloves?|stockings?|pantyhose|thighhighs?|socks?|shoes?|boots?)\b/.test(tag) &&
    /\b(unworn|discarded|scattered|on floor|on the floor|around on floor|clothes around waist)\b/.test(tag);
}

function isOtherCharacterClothingActionTag(tag) {
  return /\b(unbuttoning|removing|tearing|pulling|lifting|grabbing)\b.*\b(?:other|another|girl)(?:'?s| s)?\b.*\b(shirt|bra|skirt|dress|pant(?:y|ies)|underwear|bikini|clothes|pantyhose|stockings?|thighhighs?|socks?|legwear)\b/.test(
    tag,
  );
}

function baseReplacementTerm(term) {
  return stringValue(term).split(':', 1)[0];
}

function replacementModifierSet(term) {
  const value = stringValue(term);
  const separator = value.indexOf(':');
  if (separator < 0) return new Set();
  return new Set(value.slice(separator + 1).split('+').filter(Boolean));
}

function isTransientClothingActionTerm(tag) {
  return [
    /\b(dress tug|skirt pull|skirt flip|adjusting clothes)\b/,
    /\b(pulling down|taking off|undressing|bra off|bra down|open towel|holding towel|cover(?:ing)? mouth with (?:a )?towel)\b/,
    /\b(fingering through clothes|hand under clothes|hand in panties|hand in another s panties|hand inside .*bikini bottom|hand on skirt|hand on .*skirt|hands on skirt)\b/,
    /\b(holding .*pants|holding another s pants|pants pull|bikini pull|pulling down .*bikini|hands on bikini|hands on breasts)\b/,
    /\b(grabbing another s (?:jacket|coat|skirt|dress|clothes|pants|panties|bikini)|grabbing girl s underwear|tear .*underwear)\b/,
    /\b(lifting .*skirt|lifting other s skirt|lifting another s skirt|removing .*top|removing other s top|lifted .*bra|lifting .*bra|lifting .*dress|dress .*lift|torn .*skirt|torn .*dress|poke .*shirt)\b/,
    /\b(girl panties|wedgie|partially undressed|torn clothes|forced exposure|pussy cutout)\b/,
  ].some((pattern) => pattern.test(tag));
}

function isLowerReplacementTerm(term) {
  const base = baseReplacementTerm(term);
  return [
    'bikini-bottom',
    'bikini-bottom-only',
    'side-tie-bikini-bottom',
    'underwear',
    'underwear-only',
    'underwear-set',
    'mechanical-underwear',
    'fundoshi',
    'swimsuit-bottom',
    'no-underwear',
    'no-footwear',
    'dress',
    'pants',
    'legwear',
    'footwear',
  ].includes(base);
}

function hasActualTowelForTags(tags) {
  const normalized = tags.map(normalizedTagKey).filter(Boolean);
  const hasBodyTowel = normalized.some((tag) =>
    /\b(naked towel|bath towel|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body)\b/.test(
      tag,
    ),
  );
  if (hasBodyTowel) return true;
  if (normalized.some(isHoldingTowelTerm)) return false;
  return normalized.some(isActualTowelTerm);
}

function isActualTowelTerm(tag) {
  if (isHoldingTowelTerm(tag)) return false;
  return (
    tag === 'towel' ||
    /\b(naked towel|white towel|bath towel|towel wrap|wrapped in towel|towel around body|large towel around body|long white towel around body|long towel around body)\b/.test(
      tag,
    )
  );
}

function isHoldingTowelTerm(tag) {
  return /\b(holding towel|cover(?:ing)? mouth with (?:a )?towel|cover(?:ing)? with (?:a )?towel|towel over mouth|towel in mouth)\b/.test(
    tag,
  );
}

function isNonRoleReplacementStateTerm(tag) {
  return [
    /\b(nude male'?s? arm|nude male s arm|nude man'?s? arm|nude man s arm|nude boy'?s? arm|nude boy s arm|male'?s? arm|male s arm|man'?s? arm|man s arm|boy'?s? arm|boy s arm|nude arm)\b/,
    /\b(girl panties|girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|girl pant|hand bra|hand wedgie|wedgie|hand in panties|hand in another s panties|hand inside .*bikini bottom|holding .*pants|holding another s pants|holding .*pant(?:y|ies)|holding .*bikini|holding .*bra|holding .*skirt|holding bikini bottom|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing other(?:'?s| s) pant(?:y|ies)|pull(?:ing)? off girl'?s? .*(?:pantyhose|stockings?|thighhighs?|socks?|legwear)|(?:pantyhose|stockings?|thighhighs?|socks?|legwear) pull|removing other(?:'?s| s) pant(?:y|ies))\b/,
    /\b(hand on skirt|hands on skirt|lifting .*skirt|lifted .*skirt|lifting other s skirt|lifting another s skirt|removing .*top|removing other s top)\b/,
    /\b(pants pull|bikini pull|pulling down .*bikini|hands on bikini|hands on breasts|bikini top pull|hands on bikini top)\b/,
    /\b(grabbing another s (?:jacket|coat|skirt|dress|clothes|pants|panties|bikini)|grabbing girl s underwear|tear .*underwear|poke .*shirt)\b/,
    /\b(lifted .*bra|lifting .*bra|lifting .*dress|dress .*lift|torn .*skirt|torn .*dress|skirt pull|skirt lift)\b/,
    /\b(partially undressed|torn clothes|forced exposure|pussy cutout|breasts? out|face to crotch|undressing another)\b/,
    /\b(bikini aside|swimsuit aside|leotard aside|bra aside|shirt aside|skirt aside|clothes aside|panties aside)\b/,
  ].some((pattern) => pattern.test(tag));
}

function stageFields(stage) {
  return {
    identity: stringValue(stage.identity),
    upper_body: stringValue(stage.upper_body),
    lower_body: stringValue(stage.lower_body),
    upper_clothing: stringValue(stage.upper_clothing),
    lower_clothing: stringValue(stage.lower_clothing),
  };
}

function fieldAllowsCategory(field, category) {
  if (field === 'identity') return category === 'identity';
  if (field === 'upper_body') return category === 'upperBody';
  if (field === 'lower_body') return category === 'lowerBody';
  if (field === 'upper_clothing') return category === 'upperClothing';
  if (field === 'lower_clothing') return category === 'lowerClothing';
  return false;
}

function categoryForTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized) return 'nonRole';
  if (isWeightedBodyNoiseTag(tag)) return 'nonRole';
  if (
    isKnownFranchiseCharacterTag(tag, normalized) ||
    isVariantNamedCharacterTag(tag) ||
    isConcreteCharacterTag(tag) ||
    isGenericIdentity(normalized)
  ) {
    return 'identity';
  }
  if (hasTornReplacementEvidence(normalized)) {
    if (/\b(pantyhose|stockings?|thighhighs?|socks?|legwear|panties|underwear|bikini bottoms?|pants|shorts|skirt)\b/.test(normalized)) {
      return 'lowerClothing';
    }
    if (/\b(bra|bodysuit|leotard|swimsuit|bikini|dress|shirt|blouse|halter top|top|jacket|coat|suit)\b/.test(normalized)) {
      return 'upperClothing';
    }
  }
  if (isForbiddenFieldTerm(normalized)) return 'nonRole';
  if (isActualTowelTerm(normalized)) return 'upperClothing';
  if (/\b(no bra)\b/.test(normalized)) return 'upperClothing';
  if (/\b(no panties|no underwear|no overall|no overalls)\b/.test(normalized)) {
    return 'lowerClothing';
  }
  if (/\b(paw gloves|gloves?)\b/.test(normalized)) return 'upperClothing';
  if (/\b(tail|paw|hooves?|feet|foot)\b/.test(normalized)) return 'lowerBody';
  if (/\b(fundoshi|loincloth|male\b.*\bswimsuit|shoes?|boots?|sneakers?|socks?|thighhigs|thighhighs?|pantyhose|stockings?|sandals?|heels?|pants|shorts|skirt|miniskirt|panties|underwear|briefs|trousers|leggings|garter|legwear|buruma|bikini bottoms?|bikini bottom only|side tie bikini bottom|side-tie bikini bottom)\b/.test(normalized)) {
    return 'lowerClothing';
  }
  if (/\b(shirt|tanktop|blouse|halter top|jacket|hoodie|hood|coat|suit|bunny suit|bunny outfit|bunny girl outfit|dress|uniform|serafuku|school uniform|school swimsuit|kimono|yukata|bra|bikini|swimsuit|leotard|lingerie|babydoll|baby doll|negligee|chemise|teddy|sleepwear|nightgown|sleeves?|gloves?|robe|armor|apron|overalls|tank top|crop top|cropped shirt|camisole|vest|cloak|hooded jacket|blazer|sweater|paw gloves)\b/.test(normalized)) {
    return 'upperClothing';
  }
  if (
    /\b(hair|eyes?|iris|pupils?|ears?|horns?|halo|fangs?|skin|hat|cap|headdress|headwear|hair ornament|jewelry|earrings?|necklace|choker|collar|twintails?|twin tails?|pony ?tail|pigtails?|braids?|bangs?|hairclip|hairband|ribbon|bow|glasses|crown|bracelet|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|ribs?|chest|breasts?|bust|flat chest|midriff|abs|face)\b/.test(
      normalized,
    )
  ) {
    return 'upperBody';
  }
  if (
    /\b(thighs?|thick thighs?|bare legs?|legs?|navel|stomach|hips?|waist|barefoot|toes?|thighcut)\b/.test(
      normalized,
    )
  ) {
    return 'lowerBody';
  }
  if (/\b(shoes?|boots?|sneakers?|socks?|thighhigs|thighhighs?|pantyhose|stockings?|sandals?|heels?|pants|shorts|skirt|miniskirt|panties|underwear|briefs|trousers|leggings|garter|legwear|buruma|bikini bottoms?|bikini bottom only|side tie bikini bottom|side-tie bikini bottom)\b/.test(normalized)) {
    return 'lowerClothing';
  }
  if (/\b(shirt|tanktop|blouse|halter top|jacket|hoodie|hood|coat|suit|bunny suit|bunny outfit|bunny girl outfit|dress|uniform|serafuku|school uniform|school swimsuit|kimono|yukata|bra|bikini|swimsuit|leotard|lingerie|babydoll|baby doll|negligee|chemise|teddy|sleepwear|nightgown|sleeves?|gloves?|robe|armor|apron|overalls|tank top|crop top|cropped shirt|camisole|vest|cloak|hooded jacket|blazer|sweater|paw gloves)\b/.test(normalized)) {
    return 'upperClothing';
  }
  if (
    /^(black male|black man|faceless male|faceless muscular male|dark[- ]skinned male|dark[- ]skined male|black skinned male|very dark[- ]skined male|muscular male|musclar male|bald man|old man|big man|fat man|shadow male|dark[- ]skinned female|nun|elf|succubus|demon girl|dragon girl|cheerleader|assertive female|petite slender girl|multiple boys|focus girl|male focus|african|thief|shota|bandit|goblin|monster|tentacle monster|orc|student|boy|girl)$/.test(
      normalized,
    )
  ) {
    return 'identity';
  }
  const classified = classificationCategoryForTag(tag);
  if (classified === 'character') return 'identity';
  if (classified === 'upperBody') return 'upperBody';
  if (classified === 'lowerBody') return 'lowerBody';
  if (classified === 'upperClothing') return 'upperClothing';
  if (classified === 'lowerClothing') return 'lowerClothing';
  if (['artist', 'quality', 'action', 'camera', 'scene', 'other'].includes(classified)) {
    return 'nonRole';
  }
  return 'nonRole';
}

function isWeightedBodyNoiseTag(tag) {
  const raw = stringValue(tag).trim();
  if (!raw) return false;
  if (!/^\(+.*\)+$/.test(raw)) return false;
  const normalized = normalizedTagKey(
    raw
      .replace(/[()]/g, ' ')
      .replace(/:/g, ' ')
      .replace(/\s+/g, ' ')
      .trim(),
  );
  return /^(?:4 toes|feet|foot|barefoot|shiny skin)(?:\s+[\d.]+)*$/.test(
    normalized,
  );
}

function isKnownFranchiseCharacterTag(tag, normalized) {
  const raw = stringValue(tag);
  if (!/[_\s]*\([^)]{3,}\)/.test(raw) || /^artist[:\s]/i.test(raw)) {
    return false;
  }
  return /\b(fate|princess connect|blue archive|azur lane|genshin impact|honkai|star rail|arknights|granblue fantasy|zenless zone zero|re zero|date a live|hololive|idolmaster|girls frontline|touhou|kancolle|umamusume|flower knight girl|black survival)\b/.test(
    normalized,
  );
}

function isForbiddenFieldTerm(normalized) {
  if (
    new Set([
      'chair',
      'closed eye',
      'hair censor',
      'troll face',
      'bulging eyes',
      'clitoral hood',
      'face in crotch',
      'holding towel',
      'cover mouth with a towel',
      'covering mouth with a towel',
      'shower place',
      'bathroom place',
      'tattoo machine laser',
      'face down on chest',
      'face to crotch',
      'nude male arm',
      "nude male's arm",
      'nude male s arm',
      'hand wedgie girl panties up',
      'girl panties up',
      'hand bra',
      'dress tug',
      'skirt flip',
      'skirt pull',
      'adjusting clothes',
      'forced exposure',
      'pussy cutout',
      'breasts out',
      'breast out',
      'exposed breasts',
      'nude breasts',
      'exposed nipples',
      'wide eyes',
      'vacant eyes',
      'liquid on skin',
      'face smushed',
      'squished face',
      'bare shoulders and thighs',
      'bikini top pull',
      'hands on bikini top',
      'undressing another',
      'dull eyes',
      'girl shaded face and dull eyes',
      'girl s shaded face',
      "girl's shaded face",
      'face turned sideways showing flushed face',
    ]).has(normalized)
  ) {
    return true;
  }
  return /\b(looking|sitting|standing|lying|kneeling|holding|grabbing|touching|pulling|lifting|open mouth|closed eyes?|smile|crying|tears?|blush|sex|cum|semen|pussy|penis|nipples?|areola|ass|spread legs|from behind|from side|close up|camera|solo|text|artist|quality|towel over mouth|shaded face|dull eyes?|wide eyes?|vacant eyes?|dead eyes?|face turned sideways|partially shaded face|flushed face|face flushed|face flushed deep red|deep flushed face|pale face|magical girl pale face|extremely red face|fear face|despairing face|distorted face|very distorted face|shocked face|face up|face down|face down on chest|face to crotch|face to the ground|face not visible|no face visible|no face details|no man's face in screen|eyes? rolled back|ahegao|unfocused|clench teeth|gritted teeth|white teeth|male teeth|messy lower body|thighhold|elegant posture|on stomach|legs together|legs up|relaxed shoulder movement|stomach bulge|breast press|bouncing breasts|breasts? fully bouncing|breasts? bouncing|jiggling|groping .*breasts?|breasts? out|exposed breasts?|nude breasts?|exposed nipples?|deep cleavage (?:fully exposed|spilling out)|bare shoulders and thighs|exposing hips|heaving chest|flushed heaving chest|deeply flushed heaving chest|legs? wrapped around waist|face smushed|squished face|liquid on skin|squeezed together|hard nipple|hide nipple|tattoo machine|condom box|mart text|dress tug|skirt flip|skirt pull|adjusting clothes|fingering through clothes|hand under clothes|male'?s? arm|girl panties|wedgie|partially undressed|torn clothes|forced exposure|pussy cutout|bikini top pull|hands on bikini top|undressing another|one ripping .*halter top|ripping .*top|tearing .*clothes|holding .*pant(?:y|ies)|pant(?:y|ies) in .*hand|look(?:ing)? at pant(?:y|ies)|cum on pant(?:y|ies)|tearing other(?:'?s| s) pant(?:y|ies)|removing other(?:'?s| s) pant(?:y|ies))\b/.test(
    normalized,
  );
}

function isConcreteCharacterTag(tag) {
  const normalized = normalizedTagKey(tag);
  if (!normalized || isGenericIdentity(normalized)) return false;
  if (isForbiddenFieldTerm(normalized)) return false;
  if (
    /\b(hair|eyes?|ears?|tail|fangs?|face|tattoo|hat|cap|shirt|jacket|skirt|shorts|pants|panties|shoes?|boots?|socks?|nude|sex|artist|quality|scene|place|uniform|bikini|swimsuit|dress)\b/.test(
      normalized,
    )
  ) {
    return false;
  }
  return /[_\s]*\([^)]{3,}\)/.test(tag) && !/^artist[:\s]/i.test(tag);
}

function isVariantNamedCharacterTag(tag) {
  const raw = stringValue(tag).trim();
  if (!/[_\s]*\([^)]{3,}\)/.test(raw) || /^artist[:\s]/i.test(raw)) {
    return false;
  }
  const normalized = raw.replace(/_/g, ' ');
  const groups = [...normalized.matchAll(/\(([^)]*)\)/g)]
    .map((match) => normalizedTagKey(match[1]))
    .filter(Boolean);
  if (!groups.some(isVariantOnlyCharacterGroup)) return false;
  const canonical = normalizedTagKey(normalized.replace(/\([^)]*\)/g, ' '));
  if (!/^[a-z][a-z0-9]*(?:\s+[a-z][a-z0-9]*){1,4}$/.test(canonical)) {
    return false;
  }
  return !isForbiddenFieldTerm(canonical);
}

function isVariantOnlyCharacterGroup(normalized) {
  return /^(summer|swimsuit|school uniform|bunny girl|dress|casual|track|maid|santa|idol|princess|halloween|new year|christmas|gym uniform|sportswear|first costume|1st costume)$/.test(
    normalized,
  );
}

function isGenericIdentity(normalized) {
  return /^(1girl|2girls|girl|girls|woman|female|1boy|boy|boys|man|male|loli|child|student|fat man|faceless male|faceless_male|dark-skinned male|dark skinned male|muscular male|musclar male|bald man|old man|big man|thief|homeless man|homless man|goblin|monster|tentacle monster|octopus tentacle monster|ugly octopus tentacle monster|orc|giant orc)$/.test(
    normalized,
  );
}

function classificationCategoryForTag(tag) {
  const raw = cleanTag(tag);
  if (!raw) return undefined;
  const lower = raw.toLowerCase();
  const spaced = lower.replace(/_/g, ' ');
  const normalized = normalizedTagKey(raw);
  const keys = uniqueExact([
    raw,
    lower,
    spaced,
    normalized,
    normalized.replace(/\s+/g, '_'),
    normalized.replace(/\s+/g, '-'),
  ]);
  for (const key of keys) {
    const entry = classificationCache[`positive:${key}`];
    if (entry?.category) return entry.category;
  }
  return undefined;
}

function parseTags(text) {
  return stripNegativeWeightedGroups(stringValue(text).replace(/\r?\n/g, ','))
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[\uFF0C\u3001\uFF1B]/g, ',')
    .replace(/[，、；]/g, ',')
    .replace(/[、，；;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function stripNegativeWeightedGroups(text) {
  return stringValue(text).replace(/-\d+(?:\.\d+)?\s*::[\s\S]*?::/g, ',');
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  text = text.replace(/^["']|["']$/g, '').trim();
  if (/^-\d+(?:\.\d+)?\s*::\s*/.test(text)) return '';
  let changed = true;
  while (changed) {
    const leadingWeight = text.match(/^([+-]?\d+(?:\.\d+)?)\s*::\s*/);
    if (leadingWeight && Number(leadingWeight[1]) <= 0) return '';
    const next = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
    changed = next !== text;
    text = next;
  }
  text = text.replace(/::+$/g, '').replace(/^:+|:+$/g, '').trim();
  text = text.replace(/^(?:and|with)\s+/i, '').trim();
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) {
    if (Number(weighted[2]) <= 0) return '';
    text = weighted[1].trim();
  }
  let unwrapped = true;
  while (unwrapped) {
    const next = text.match(/^\(([^()]+)\)$/);
    if (!next) {
      unwrapped = false;
    } else {
      text = next[1].trim();
    }
  }
  return text.replace(/\s+/g, ' ').trim();
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function countIssueKinds(issues) {
  const count = (prefix) =>
    issues.filter((issue) => issue.kind.startsWith(prefix)).length;
  return {
    mixed_stage_issue_count: count('mixed_stage'),
    label_state_issue_count: issues.filter((issue) =>
      issue.kind.startsWith('label_'),
    ).length,
    field_route_issue_count: count('field_route'),
    field_source_issue_count: count('field_source'),
    ui_label_issue_count: count('ui_stage_label'),
  };
}

function intList(values) {
  return Array.isArray(values)
    ? values.map(Number).filter((value) => Number.isInteger(value))
    : [];
}

function uniqueExact(values) {
  const result = [];
  const seen = new Set();
  for (const value of values) {
    const text = stringValue(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    result.push(text);
  }
  return result;
}

function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0);
}

function hasChinese(value) {
  return /[\u4e00-\u9fff]/.test(stringValue(value));
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = {
    cacheDir: undefined,
    reportPath: undefined,
    classificationCache: undefined,
    maxPrint: 20,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[index + 1];
    index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'report-path') parsed.reportPath = value;
    if (key === 'classification-cache') parsed.classificationCache = value;
    if (key === 'max-print') parsed.maxPrint = Number(value);
  }
  return parsed;
}

function loadJson(filePath, fallback) {
  if (!filePath || !fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}
