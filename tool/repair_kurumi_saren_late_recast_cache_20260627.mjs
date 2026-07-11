import fs from 'node:fs';
import path from 'node:path';

const options = parseArgs(process.argv.slice(2));
if (!options.cache) {
  console.error(
    'Usage: node tool/repair_kurumi_saren_late_recast_cache_20260627.mjs --cache <cache.json> [--apply] [--backup-dir <dir>]',
  );
  process.exit(64);
}

const cachePath = path.resolve(options.cache);
const cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
const originalText = JSON.stringify(cache);
const report = repair(cache);
report.cache = cachePath;
report.apply = options.apply;

if (JSON.stringify(cache) !== originalText) {
  report.changed = true;
  cache.updatedAt = new Date().toISOString();
  if (options.apply) {
    const backupDir =
      options.backupDir ??
      path.join(path.dirname(cachePath), 'cache_backup_kurumi_saren_late_20260627');
    fs.mkdirSync(backupDir, { recursive: true });
    const backupPath = path.join(backupDir, path.basename(cachePath));
    if (!fs.existsSync(backupPath)) {
      fs.copyFileSync(cachePath, backupPath);
    }
    fs.writeFileSync(cachePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    report.backup = backupPath;
  }
}

console.log(JSON.stringify(report, null, 2));

function repair(cache) {
  const frames = cache.scriptSnapshot?.frames ?? [];
  const sarenFrames = framesForSlot0(frames, /^saren(?:\s|\()/i);
  const suzumeFrames = framesForSlot0(frames, /^suzume(?:\s|\()/i);
  const result = {
    scriptId: stringValue(cache.scriptId),
    changed: false,
    sarenFramesAddedToAppearance: 0,
    suzumeFramesAddedToAppearance: 0,
    promptTermsUpserted: 0,
    replacementRulesUpserted: 0,
    emptySarenRulesRemoved: 0,
    sarenLateFrames: sarenFrames.filter((frame) => frame >= 336),
    suzumeLateFrames: suzumeFrames.filter((frame) => frame >= 335),
  };

  const sarenRole = roleById(cache, 'role-saren-princess-connect');
  const sarenReplacement = replacementById(cache, 'role-saren-princess-connect');
  if (sarenRole && sarenReplacement) {
    result.sarenFramesAddedToAppearance += mergeSlot0Appearance(
      sarenRole,
      sarenFrames,
      { snakeCase: true },
    );
    result.sarenFramesAddedToAppearance += mergeSlot0Appearance(
      assemblyById(cache, 'role-saren-princess-connect'),
      sarenFrames,
      { snakeCase: false },
    );
    const sarenRepair = repairSarenTerms({
      frames,
      frameIndexes: sarenFrames,
      role: sarenRole,
      replacement: sarenReplacement,
    });
    result.promptTermsUpserted += sarenRepair.promptTermsUpserted;
    result.replacementRulesUpserted += sarenRepair.replacementRulesUpserted;
    result.emptySarenRulesRemoved += sarenRepair.emptyRulesRemoved;
  }

  const suzumeRole = roleById(cache, 'role-suzume-princess-connect');
  const suzumeReplacement = replacementById(cache, 'role-suzume-princess-connect');
  if (suzumeRole && suzumeReplacement) {
    result.suzumeFramesAddedToAppearance += mergeSlot0Appearance(
      suzumeRole,
      suzumeFrames,
      { snakeCase: true },
    );
    result.suzumeFramesAddedToAppearance += mergeSlot0Appearance(
      assemblyById(cache, 'role-suzume-princess-connect'),
      suzumeFrames,
      { snakeCase: false },
    );
    const suzumeRepair = mergeConcreteIdentityTerms({
      frames,
      frameIndexes: suzumeFrames,
      role: suzumeRole,
      replacement: suzumeReplacement,
      pattern: /^suzume\b/i,
    });
    result.promptTermsUpserted += suzumeRepair.promptTermsUpserted;
    result.replacementRulesUpserted += suzumeRepair.replacementRulesUpserted;
  }

  result.changed =
    result.sarenFramesAddedToAppearance > 0 ||
    result.suzumeFramesAddedToAppearance > 0 ||
    result.promptTermsUpserted > 0 ||
    result.replacementRulesUpserted > 0 ||
    result.emptySarenRulesRemoved > 0;
  return result;
}

function repairSarenTerms({ frames, frameIndexes, role, replacement }) {
  const identityTarget =
    identityRuleTarget(replacement) ||
    'animal_ear_fluff, animal_ears, cat_ears, cat_girl, pepe_(arknights), -5:: hood ::';
  const targetHair = 'long_hair';
  const targetUpperClothing =
    'lotus_flower_headdress, hair_ornament, jewelry, black_jacket, jacket, long_sleeves';
  const targetLowerClothing = 'black_shorts, shoes, shorts';
  const specs = [
    {
      text: 'saren (sarasaria) (princess connect!)',
      category: 'character',
      targetPrompt: identityTarget,
      group: 'identity',
    },
    { text: 'long hair', category: 'upperBody', targetPrompt: targetHair, group: 'hair' },
    {
      text: 'braided ponytail',
      category: 'upperBody',
      targetPrompt: targetHair,
      group: 'hair',
    },
    { text: 'curly hair', category: 'upperBody', targetPrompt: targetHair, group: 'hair' },
    {
      text: 'harem outfit',
      category: 'upperClothing',
      targetPrompt: `${targetUpperClothing}, ${targetLowerClothing}`,
      group: 'clothing',
    },
    {
      text: 'bare shoulders',
      category: 'upperBody',
      targetPrompt: 'black_jacket, jacket, long_sleeves',
      group: 'bare-shoulders',
    },
    {
      text: 'orange veil',
      category: 'clothing',
      targetPrompt: 'lotus_flower_headdress, hair_ornament',
      group: 'veil',
    },
    {
      text: 'belly chain',
      category: 'clothing',
      targetPrompt: 'jewelry',
      group: 'jewelry',
    },
    {
      text: 'orange bikini',
      category: 'upperClothing',
      targetPrompt: `${targetUpperClothing}, ${targetLowerClothing}`,
      group: 'clothing',
    },
    {
      text: 'detached sleeves',
      category: 'upperClothing',
      targetPrompt: 'black_jacket, jacket, long_sleeves',
      group: 'sleeves',
    },
    {
      text: 'sarong',
      category: 'lowerClothing',
      targetPrompt: targetLowerClothing,
      group: 'lower-clothing',
    },
    {
      text: 'mouth veil',
      category: 'clothing',
      targetPrompt: 'lotus_flower_headdress, hair_ornament',
      group: 'veil',
    },
  ];

  let promptTermsUpserted = 0;
  let replacementRulesUpserted = 0;
  for (const spec of specs) {
    const termFrames = framesContainingTerm(frames, frameIndexes, spec.text);
    if (termFrames.length === 0) continue;
    const term = promptTerm(role.source_role_id, spec, termFrames);
    promptTermsUpserted += upsertAiPromptTerm(role, term);
    replacementRulesUpserted += upsertReplacementRule(replacement, term, {
      targetPrompt: spec.targetPrompt,
      group: spec.group,
    });
  }

  const before = replacement.rules?.length ?? 0;
  replacement.rules = (replacement.rules ?? []).filter((rule) => {
    if (stringValue(rule.targetPrompt).trim()) return true;
    return !(rule.sourceTerms ?? []).some(
      (term) => normalizedTagKey(term.text) === normalizedTagKey('saren (sarasaria) (princess connect!)'),
    );
  });
  const emptyRulesRemoved = before - replacement.rules.length;
  replacement.sourcePreview = sourcePreviewFromTerms(role.prompt_terms ?? []);

  return {
    promptTermsUpserted,
    replacementRulesUpserted,
    emptyRulesRemoved,
  };
}

function mergeConcreteIdentityTerms({ frames, frameIndexes, role, replacement, pattern }) {
  let promptTermsUpserted = 0;
  let replacementRulesUpserted = 0;
  const seen = new Set();
  const identityTarget = identityRuleTarget(replacement);
  if (!identityTarget) return { promptTermsUpserted, replacementRulesUpserted };
  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    if (!frameIndexes.includes(frameIndex)) continue;
    for (const tag of parseTags(frame.parsed?.charCaptions?.[0])) {
      if (!pattern.test(tag)) continue;
      const key = normalizedTagKey(tag);
      if (!key || !seen.add(key)) continue;
      const termFrames = framesContainingTerm(frames, frameIndexes, tag);
      const term = promptTerm(role.source_role_id, {
        text: tag,
        category: 'character',
      }, termFrames);
      promptTermsUpserted += upsertAiPromptTerm(role, term);
      replacementRulesUpserted += upsertReplacementRule(replacement, term, {
        targetPrompt: identityTarget,
        group: 'identity',
      });
    }
  }
  replacement.sourcePreview = sourcePreviewFromTerms(role.prompt_terms ?? []);
  return { promptTermsUpserted, replacementRulesUpserted };
}

function framesForSlot0(frames, identityPattern) {
  const result = [];
  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    const caption = stringValue(frame.parsed?.charCaptions?.[0]);
    const tags = parseTags(caption);
    if (tags.some((tag) => identityPattern.test(tag))) {
      result.push(frameIndex);
    }
  }
  return sortedInts(result);
}

function framesContainingTerm(frames, frameIndexes, term) {
  const key = normalizedTagKey(term);
  const allowed = new Set(frameIndexes);
  const result = [];
  for (const frame of frames) {
    const frameIndex = Number(frame.index);
    if (!allowed.has(frameIndex)) continue;
    const tags = parseTags(frame.parsed?.charCaptions?.[0]);
    if (tags.some((tag) => normalizedTagKey(tag) === key)) {
      result.push(frameIndex);
    }
  }
  return sortedInts(result);
}

function mergeSlot0Appearance(target, frameIndexes, { snakeCase }) {
  if (!target) return 0;
  const listKey = snakeCase ? 'appearances' : 'sourceAppearances';
  const idKey = snakeCase ? 'source_id' : 'sourceId';
  const kindKey = snakeCase ? 'source_kind' : 'sourceKind';
  const frameKey = snakeCase ? 'frame_indexes' : 'frameIndexes';
  if (!Array.isArray(target[listKey])) target[listKey] = [];
  let appearance = target[listKey].find(
    (item) => stringValue(item?.[idKey]) === 'slot-0' && stringValue(item?.[kindKey]) === 'slot',
  );
  if (!appearance) {
    appearance = { [idKey]: 'slot-0', [kindKey]: 'slot', [frameKey]: [] };
    target[listKey].push(appearance);
  }
  const before = new Set(appearance[frameKey] ?? []);
  appearance[frameKey] = sortedInts([...before, ...frameIndexes]);
  return appearance[frameKey].length - before.size;
}

function upsertAiPromptTerm(role, incoming) {
  if (!Array.isArray(role.prompt_terms)) role.prompt_terms = [];
  const key = replacementTermKey(incoming);
  const existing = role.prompt_terms.find((term) => replacementTermKey(term) === key);
  if (!existing) {
    role.prompt_terms.push(incoming);
    return 1;
  }
  const before = JSON.stringify(existing);
  existing.id = stringValue(existing.id).trim() || incoming.id;
  existing.text = incoming.text;
  existing.category = incoming.category;
  existing.source_phrase = incoming.source_phrase;
  existing.source_location = incoming.source_location;
  existing.frame_indexes = sortedInts([
    ...(existing.frame_indexes ?? existing.frameIndexes ?? []),
    ...incoming.frame_indexes,
  ]);
  return JSON.stringify(existing) === before ? 0 : 1;
}

function upsertReplacementRule(replacement, incomingTerm, { targetPrompt, group }) {
  if (!Array.isArray(replacement.rules)) replacement.rules = [];
  const key = replacementTermKey(incomingTerm);
  let rule = replacement.rules.find((candidate) =>
    (candidate.sourceTerms ?? []).some((term) => replacementTermKey(term) === key),
  );
  let changed = 0;
  if (!rule) {
    rule = {
      id: `role-${safeId(replacement.sourceRoleId)}-${safeId(group)}-${safeId(incomingTerm.text)}`,
      sourceTerms: [promptReplacementTerm(incomingTerm)],
    };
    replacement.rules.push(rule);
    changed = 1;
  } else {
    const before = JSON.stringify(rule);
    rule.sourceTerms = (rule.sourceTerms ?? []).filter(
      (term) => replacementTermKey(term) !== key,
    );
    rule.sourceTerms.push(promptReplacementTerm(incomingTerm));
    if (JSON.stringify(rule) !== before) changed = 1;
  }
  const beforeRule = JSON.stringify(rule);
  rule.action = 'replace';
  rule.targetPrompt = targetPrompt;
  if (JSON.stringify(rule) !== beforeRule) changed = 1;
  return changed;
}

function promptTerm(roleId, spec, frameIndexes) {
  return {
    id: `role-${safeId(roleId)}-${safeId(spec.category)}-${safeId(spec.text)}`,
    text: spec.text,
    category: spec.category,
    source_phrase: spec.text,
    source_location: 'slot-0 prompt',
    frame_indexes: sortedInts(frameIndexes),
  };
}

function promptReplacementTerm(term) {
  return {
    id: stringValue(term.id),
    text: stringValue(term.text),
    category: stringValue(term.category),
    sourcePhrase: stringValue(term.source_phrase ?? term.sourcePhrase),
    sourceLocation: stringValue(term.source_location ?? term.sourceLocation),
    frameIndexes: sortedInts(term.frame_indexes ?? term.frameIndexes ?? []),
  };
}

function identityRuleTarget(replacement) {
  for (const rule of replacement.rules ?? []) {
    const target = stringValue(rule.targetPrompt).trim();
    if (!target) continue;
    if (
      (rule.sourceTerms ?? []).some(
        (term) =>
          stringValue(term.category) === 'character' &&
          /\([^)]*princess connect!?[^)]*\)/i.test(stringValue(term.text)),
      )
    ) {
      return target;
    }
  }
  return '';
}

function roleById(cache, roleId) {
  return (cache.aiRoleExtraction?.roles ?? []).find(
    (role) => stringValue(role.source_role_id ?? role.sourceRoleId) === roleId,
  );
}

function replacementById(cache, roleId) {
  return (cache.mapping?.rolePromptReplacements ?? []).find(
    (replacement) => stringValue(replacement.sourceRoleId) === roleId,
  );
}

function assemblyById(cache, roleId) {
  return (cache.mapping?.roleAssemblies ?? []).find(
    (assembly) => stringValue(assembly.sourceRoleId) === roleId,
  );
}

function parseTags(text) {
  return stringValue(text)
    .replace(/\r?\n/g, ',')
    .replace(/::\s*[+-]?\d+(?:\.\d+)?\s*::/g, ',')
    .replace(/::+/g, ',')
    .replace(/[，、；;|]+/g, ',')
    .split(',')
    .map(cleanTag)
    .filter(Boolean);
}

function cleanTag(value) {
  let text = stringValue(value).trim();
  if (!text) return '';
  text = text.replace(/^["']|["']$/g, '').trim();
  text = text.replace(/^[+]?\d+(?:\.\d+)?\s*::\s*/g, '').trim();
  text = text.replace(/::+$/g, '').replace(/^:+|:+$/g, '').trim();
  const weighted = text.match(/^\((.*):([+-]?\d+(?:\.\d+)?)\)$/);
  if (weighted) text = weighted[1].trim();
  return text.replace(/\s+/g, ' ').trim();
}

function sourcePreviewFromTerms(terms) {
  const seen = new Set();
  const parts = [];
  for (const term of terms) {
    const text = cleanTag(term.text);
    const key = normalizedTagKey(text);
    if (!key || !seen.add(key)) continue;
    parts.push(text);
  }
  return parts.join(', ');
}

function replacementTermKey(term) {
  return `${stringValue(term?.category)}\u001f${normalizedTagKey(term?.text)}`;
}

function normalizedTagKey(value) {
  return cleanTag(value).toLowerCase().replace(/[_\s-]+/g, ' ').trim();
}

function safeId(value) {
  return normalizedTagKey(value).replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

function sortedInts(values) {
  return [...new Set((values ?? []).map(Number).filter(Number.isInteger))].sort((a, b) => a - b);
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function parseArgs(args) {
  const result = { apply: false };
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--apply') {
      result.apply = true;
    } else if (arg === '--cache') {
      result.cache = args[++i];
    } else if (arg === '--backup-dir') {
      result.backupDir = args[++i];
    }
  }
  return result;
}
