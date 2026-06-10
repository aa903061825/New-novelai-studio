import fs from 'node:fs';
import path from 'node:path';

const workspaceRoot =
  process.argv.find((arg) => arg.startsWith('--workspace='))?.slice(12) ||
  'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
const apply = process.argv.includes('--apply');

const charactersPath = path.join(workspaceRoot, 'library', 'characters.json');
const reportPath = path.join(
  workspaceRoot,
  'library',
  'asset_role_card_cleanup_report.json',
);

const tagListFields = [
  'upperBodyTags',
  'upperClothingTags',
  'lowerBodyTags',
  'lowerClothingTags',
  'weaponTags',
];

const actionExactTags = new Set([
  'closed_eyes',
  'one_eye_closed',
  'half-closed_eyes',
  'half_closed_eyes',
  'smile',
  'slight_smile',
  'open_mouth',
  'closed_mouth',
  'expressionless',
  'wavy_mouth',
  'wavy_eyes',
  'looking_at_viewer',
  'looking_away',
  'looking_down',
  'looking_up',
  'standing',
  'sitting',
  'lying',
  'running',
  'walking',
  'jumping',
  'kneeling',
  'squatting',
  'pose',
  'dynamic_pose',
  'arms_up',
  'arm_up',
  'hand_up',
  'hands_up',
  'holding',
  'grabbing',
  'reaching',
  'head_tilt',
  'tail_raised',
  'tail_up',
  'tail_down',
  'tail_wagging',
  'wagging_tail',
  'expressive_tail',
  'stiff_tail',
]);

const actionPattern =
  /(^|_)(closed_eyes|one_eye_closed|half.*closed_eyes|smile|mouth|expression|looking|standing|sitting|lying|running|walking|jumping|kneeling|squatting|pose|arms?|hands?|holding|grabbing|reaching|head_tilt|facing|view)($|_)/;

const upperBodyPattern =
  /(^|_)(ahoge|animal_ear|animal_ears|animal_ear_fluff|bangs|blunt_bangs|bonnet|bow|braid|choker|collarbone|ear|ears|earring|earrings|eye|eyes|fang|flower|glasses|hair|hairband|halo|hat|head|headpiece|headdress|horn|horns|jewelry|mark|necklace|ornament|ribbon|skin|twintails|veil)($|_)/;

const lowerBodyPattern =
  /(^|_)(anklet|bare_legs|cat_tail|dog_tail|leg|legs|tail|tails|tail_bow|tail_ornament|tail_ring|thigh|thighs|thigh_belt|thigh_strap)($|_)/;

const clothingPattern =
  /(^|_)(apron|belt|bikini|blouse|bodystocking|bodysuit|boot|boots|cape|capelet|china_dress|chinese_clothes|clothes|clothing|coat|dress|glove|gloves|hood|hoodie|jacket|kimono|kneehighs|leggings|pants|pantyhose|robe|sandal|sandals|shirt|shoe|shoes|shorts|skirt|sock|socks|stocking|stockings|sweater|swimsuit|thigh_boots|thighhighs|thigh_highs|uniform|vest)($|_)/;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function backup(filePath) {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(
    now.getDate(),
  )}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const backupDir = path.join(
    workspaceRoot,
    'library',
    `backup-${stamp}-role-card-cleanup`,
  );
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, path.basename(filePath)));
  return backupDir;
}

function cleanTag(value) {
  return String(value || '')
    .trim()
    .replace(/^[{\[\s]+/, '')
    .replace(/[}\]\s]+$/, '')
    .replace(/^-?\d+(?:\.\d+)?::\s*/, '')
    .replace(/\s*::-?\d+(?:\.\d+)?$/, '')
    .replace(/\\+/g, '')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .replace(/\(_/g, '(')
    .replace(/_\)/g, ')')
    .toLowerCase()
    .replace(/^_+|_+$/g, '');
}

function splitTags(value) {
  return String(value || '')
    .replace(/\r\n?/g, '\n')
    .split(/[,\n]/)
    .map((part) => part.trim())
    .filter(Boolean);
}

function uniqueTags(values) {
  const seen = new Set();
  const result = [];
  for (const value of values || []) {
    const tag = cleanTag(value);
    if (!tag || seen.has(tag)) continue;
    seen.add(tag);
    result.push(tag);
  }
  return result;
}

function sameTags(left, right) {
  const a = uniqueTags(left);
  const b = uniqueTags(right);
  return a.length === b.length && a.every((tag, index) => tag === b[index]);
}

function promptFromTags(tags) {
  return uniqueTags(tags).join(', ');
}

function isActionOrExpressionTag(tag) {
  const key = cleanTag(tag);
  return actionExactTags.has(key) || actionPattern.test(key);
}

function isLowerBodyTag(tag) {
  const key = cleanTag(tag);
  if (/(^|_)(thighhighs|thigh_highs|thigh_boots)($|_)/.test(key)) {
    return false;
  }
  return lowerBodyPattern.test(key);
}

function isUpperBodyTag(tag) {
  const key = cleanTag(tag);
  if (isLowerBodyTag(key)) return false;
  return upperBodyPattern.test(key) && !clothingPattern.test(key);
}

function cleanBodyPromptParts(upperPrompt, lowerPrompt, context, report) {
  const upper = [];
  const lower = [];

  for (const raw of splitTags(upperPrompt)) {
    const tag = cleanTag(raw);
    if (!tag) continue;
    if (isActionOrExpressionTag(tag)) {
      report.removedActionTags.push({ ...context, field: 'front_upper', tag });
      continue;
    }
    if (isLowerBodyTag(tag)) {
      lower.push(tag);
      report.movedBodyTags.push({
        ...context,
        tag,
        from: 'front_upper',
        to: 'front_lower',
      });
      continue;
    }
    upper.push(tag);
  }

  for (const raw of splitTags(lowerPrompt)) {
    const tag = cleanTag(raw);
    if (!tag) continue;
    if (isActionOrExpressionTag(tag)) {
      report.removedActionTags.push({ ...context, field: 'front_lower', tag });
      continue;
    }
    lower.push(tag);
  }

  return {
    upper: uniqueTags(upper),
    lower: uniqueTags(lower),
  };
}

function cleanClothingPromptParts(upperPrompt, lowerPrompt, context, report) {
  const upper = uniqueTags(splitTags(upperPrompt)).filter((tag) => {
    if (!isActionOrExpressionTag(tag)) return true;
    report.removedActionTags.push({ ...context, field: 'front_upper', tag });
    return false;
  });
  const upperKeys = new Set(upper.map(cleanTag));
  const lower = [];

  for (const raw of splitTags(lowerPrompt)) {
    const tag = cleanTag(raw);
    if (!tag) continue;
    if (isActionOrExpressionTag(tag)) {
      report.removedActionTags.push({ ...context, field: 'front_lower', tag });
      continue;
    }
    if (upperKeys.has(tag)) {
      report.removedCrossFieldDuplicates.push({
        ...context,
        tag,
        from: 'front_lower',
        keptIn: 'front_upper',
      });
      continue;
    }
    lower.push(tag);
  }

  return {
    upper,
    lower: uniqueTags(lower),
  };
}

function addMovedTag(target, tag, context, report, from, to) {
  target.push(tag);
  report.movedBodyTags.push({ ...context, tag, from, to });
}

function normalizePartTags(partTags, context, report) {
  const source = partTags || {};
  const next = {
    upperBodyTags: [],
    upperClothingTags: [],
    lowerBodyTags: [],
    lowerClothingTags: [],
    weaponTags: [],
  };

  for (const field of tagListFields) {
    for (const raw of source[field] || []) {
      const tag = cleanTag(raw);
      if (!tag) continue;
      if (isActionOrExpressionTag(tag)) {
        report.removedActionTags.push({ ...context, field, tag });
        continue;
      }
      if (field === 'upperClothingTags' && isUpperBodyTag(tag)) {
        addMovedTag(next.upperBodyTags, tag, context, report, field, 'upperBodyTags');
        continue;
      }
      if (field === 'lowerClothingTags' && isLowerBodyTag(tag)) {
        addMovedTag(next.lowerBodyTags, tag, context, report, field, 'lowerBodyTags');
        continue;
      }
      if (field === 'upperBodyTags' && isLowerBodyTag(tag)) {
        addMovedTag(next.lowerBodyTags, tag, context, report, field, 'lowerBodyTags');
        continue;
      }
      next[field].push(tag);
    }
  }

  next.upperBodyTags = uniqueTags(next.upperBodyTags);
  next.upperClothingTags = uniqueTags(next.upperClothingTags);
  next.lowerBodyTags = uniqueTags(next.lowerBodyTags);
  next.lowerClothingTags = uniqueTags(next.lowerClothingTags);
  next.weaponTags = uniqueTags(next.weaponTags);

  const upperBodyKeys = new Set(next.upperBodyTags.map(cleanTag));
  next.lowerBodyTags = next.lowerBodyTags.filter((tag) => {
    if (!upperBodyKeys.has(tag)) return true;
    report.removedCrossFieldDuplicates.push({
      ...context,
      tag,
      from: 'lowerBodyTags',
      keptIn: 'upperBodyTags',
    });
    return false;
  });

  const lowerBodyKeys = new Set(next.lowerBodyTags.map(cleanTag));
  next.upperBodyTags = next.upperBodyTags.filter((tag) => {
    if (!lowerBodyKeys.has(tag) || !isLowerBodyTag(tag)) return true;
    report.removedCrossFieldDuplicates.push({
      ...context,
      tag,
      from: 'upperBodyTags',
      keptIn: 'lowerBodyTags',
    });
    return false;
  });

  const upperClothingKeys = new Set(next.upperClothingTags.map(cleanTag));
  next.lowerClothingTags = next.lowerClothingTags.filter((tag) => {
    if (!upperClothingKeys.has(tag)) return true;
    report.removedCrossFieldDuplicates.push({
      ...context,
      tag,
      from: 'lowerClothingTags',
      keptIn: 'upperClothingTags',
    });
    return false;
  });

  return Object.fromEntries(
    Object.entries(next).filter(([, tags]) => tags.length > 0),
  );
}

function setPromptParts(target, upperKey, lowerKey, parts) {
  const upperPrompt = promptFromTags(parts.upper);
  const lowerPrompt = promptFromTags(parts.lower);
  if (upperPrompt) {
    target[upperKey] = upperPrompt;
  } else {
    delete target[upperKey];
  }
  if (lowerPrompt) {
    target[lowerKey] = lowerPrompt;
  } else {
    delete target[lowerKey];
  }
}

function changedObjectJson(left, right) {
  return JSON.stringify(left || {}) !== JSON.stringify(right || {});
}

function cleanCharacters(characters) {
  const report = {
    generatedAt: new Date().toISOString(),
    mode: apply ? 'apply' : 'dry-run',
    workspaceRoot,
    charactersPath,
    backupDir: '',
    removedActionTags: [],
    removedCrossFieldDuplicates: [],
    movedBodyTags: [],
    affectedCharacters: [],
    affectedOutfits: [],
  };

  for (const character of characters) {
    const characterBefore = JSON.stringify(character);
    character.traits ||= {};
    const bodyParts = cleanBodyPromptParts(
      character.traits.front_upper,
      character.traits.front_lower,
      { characterId: character.id, characterName: character.name, scope: 'character' },
      report,
    );
    setPromptParts(character.traits, 'front_upper', 'front_lower', bodyParts);

    for (const outfit of character.outfits || []) {
      const outfitBefore = JSON.stringify(outfit);
      outfit.tags ||= {};
      const partTagsBefore = outfit.partTags || {};
      const cleanedPartTags = normalizePartTags(
        partTagsBefore,
        {
          characterId: character.id,
          characterName: character.name,
          outfitId: outfit.id,
          outfitName: outfit.name,
          scope: 'outfit.partTags',
        },
        report,
      );
      if (changedObjectJson(partTagsBefore, cleanedPartTags)) {
        outfit.partTags = cleanedPartTags;
      }

      const clothingParts = cleanClothingPromptParts(
        outfit.tags.front_upper,
        outfit.tags.front_lower,
        {
          characterId: character.id,
          characterName: character.name,
          outfitId: outfit.id,
          outfitName: outfit.name,
          scope: 'outfit.tags',
        },
        report,
      );
      setPromptParts(outfit.tags, 'front_upper', 'front_lower', clothingParts);

      if (JSON.stringify(outfit) !== outfitBefore) {
        report.affectedOutfits.push({
          characterId: character.id,
          characterName: character.name,
          outfitId: outfit.id,
          outfitName: outfit.name,
        });
      }
    }

    if (JSON.stringify(character) !== characterBefore) {
      report.affectedCharacters.push({
        characterId: character.id,
        characterName: character.name,
      });
    }
  }

  report.summary = {
    affectedCharacterCount: report.affectedCharacters.length,
    affectedOutfitCount: report.affectedOutfits.length,
    removedActionTagCount: report.removedActionTags.length,
    removedDuplicateCount: report.removedCrossFieldDuplicates.length,
    movedBodyTagCount: report.movedBodyTags.length,
  };

  return report;
}

const characters = readJson(charactersPath);
const report = cleanCharacters(characters);

if (apply) {
  report.backupDir = backup(charactersPath);
  writeJson(charactersPath, characters);
}
writeJson(reportPath, report);

console.log(JSON.stringify(report.summary, null, 2));
console.log(JSON.stringify({ reportPath, backupDir: report.backupDir }, null, 2));
