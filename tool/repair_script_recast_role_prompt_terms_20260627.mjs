import fs from 'node:fs';
import path from 'node:path';

console.error(
  [
    'Deprecated: repair_script_recast_role_prompt_terms_20260627.mjs used local semantic rules to synthesize role prompt terms.',
    'Use tool/script_recast_complete_term_audit.mjs for local-only audit, and pass an explicit --schema for offline repair.',
    'No cache files were changed.',
  ].join('\n'),
);
process.exit(1);

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',
  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);
const defaultSourceRoot = 'E:/NAI\u7684\u811a\u672c\u7fa4/\u4f5c\u54c1\u96c6/\u5e26\u56fe\u7cbe\u54c1';

const options = parseArgs(process.argv.slice(2));
const cacheDir = path.resolve(options.cacheDir ?? defaultCacheDir);
const sourceRoot = normalizePath(options.sourceRoot ?? defaultSourceRoot);
const backupDir =
  options.backupDir ??
  path.join(
    cacheDir,
    `_backup_role_prompt_terms_${new Date().toISOString().replace(/[:.]/g, '-')}`,
  );

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => file.endsWith('.json'))
  .sort();

const report = {
  cache_dir: cacheDir,
  source_root: sourceRoot,
  apply: options.apply,
  backup_dir: options.apply ? backupDir : undefined,
  files_scanned: files.length,
  eligible_cache_files: 0,
  files_changed: 0,
  role_prompt_terms_added: 0,
  replacement_rules_added: 0,
  target_regression_missing_after: [],
  rows: [],
};

for (const file of files) {
  const filePath = path.join(cacheDir, file);
  const cache = loadJson(filePath);
  if (!cache || !looksLikeRecastCache(cache)) continue;
  if (!isUnderSourceRoot(cache.sourceRootPath, sourceRoot)) continue;
  report.eligible_cache_files += 1;

  const beforeTargetMissing = targetMissingRows(cache);
  const repair = repairCache(cache);
  const afterTargetMissing = targetMissingRows(repair.cache);
  if (afterTargetMissing.length > 0) {
    report.target_regression_missing_after.push(
      ...afterTargetMissing.map((row) => ({
        file_name: file,
        script_id: stringValue(cache.scriptId),
        script_name: stringValue(cache.scriptName),
        ...row,
      })),
    );
  }

  if (!repair.changed) {
    if (beforeTargetMissing.length > 0 || options.reportUnchanged) {
      report.rows.push({
        file_name: file,
        script_id: stringValue(cache.scriptId),
        script_name: stringValue(cache.scriptName),
        changed: false,
        prompt_terms_added: 0,
        replacement_rules_added: 0,
        missing_before: beforeTargetMissing,
        missing_after: afterTargetMissing,
      });
    }
    continue;
  }

  report.files_changed += 1;
  report.role_prompt_terms_added += repair.promptTermsAdded;
  report.replacement_rules_added += repair.replacementRulesAdded;
  report.rows.push({
    file_name: file,
    script_id: stringValue(cache.scriptId),
    script_name: stringValue(cache.scriptName),
    changed: true,
    prompt_terms_added: repair.promptTermsAdded,
    replacement_rules_added: repair.replacementRulesAdded,
    missing_before: beforeTargetMissing,
    missing_after: afterTargetMissing,
  });

  if (!options.apply) continue;
  fs.mkdirSync(backupDir, { recursive: true });
  fs.copyFileSync(filePath, path.join(backupDir, file));
  fs.writeFileSync(filePath, `${JSON.stringify(repair.cache, null, 2)}\n`, 'utf8');
}

console.log(JSON.stringify(report, null, 2));
if (options.report) {
  fs.mkdirSync(path.dirname(options.report), { recursive: true });
  fs.writeFileSync(options.report, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
if (options.assertTargets && report.target_regression_missing_after.length > 0) {
  process.exitCode = 2;
}

function repairCache(cache) {
  const next = structuredClone(cache);
  const extraction = next.aiRoleExtraction;
  if (!extraction || extraction.status !== 'ready' || !Array.isArray(extraction.roles)) {
    return { cache: next, changed: false, promptTermsAdded: 0, replacementRulesAdded: 0 };
  }
  const framesByIndex = framesByIndexMap(next);
  let changed = false;
  let promptTermsAdded = 0;
  for (const role of extraction.roles) {
    if (!Array.isArray(role.prompt_terms)) role.prompt_terms = [];
    const before = role.prompt_terms.length;
    role.prompt_terms = promptTermsWithSourceEvidence(role, framesByIndex);
    promptTermsAdded += Math.max(0, role.prompt_terms.length - before);
    changed = changed || role.prompt_terms.length !== before;
  }

  if (!next.mapping || typeof next.mapping !== 'object') {
    next.mapping = {
      id: `mapping-${stringValue(next.scriptId)}`,
      scriptId: stringValue(next.scriptId),
      roleSwaps: [],
      artistSwap: null,
    };
  }
  const replacementResult = rolePromptReplacementsWithAiTerms(
    Array.isArray(next.mapping.rolePromptReplacements)
      ? next.mapping.rolePromptReplacements
      : [],
    extraction.roles,
  );
  if (replacementResult.changed) {
    next.mapping.rolePromptReplacements = replacementResult.replacements;
    changed = true;
  }
  if (changed) {
    next.updatedAt = new Date().toISOString();
  }
  return {
    cache: next,
    changed,
    promptTermsAdded,
    replacementRulesAdded: replacementResult.rulesAdded,
  };
}

function promptTermsWithSourceEvidence(role, framesByIndex) {
  const terms = new Map();
  const order = [];
  const addTerm = (term) => {
    const text = cleanTag(term?.text);
    const category = stringValue(term?.category || 'identity');
    if (!text) return;
    const key = `${category}\u001f${normalizedTagKey(text)}`;
    const existing = terms.get(key);
    if (!existing) {
      terms.set(key, {
        id: stringValue(term.id).trim() || promptTermId(role.source_role_id, category, text),
        text,
        category,
        source_phrase: cleanTag(term.source_phrase ?? term.sourcePhrase ?? text),
        source_location: stringValue(term.source_location ?? term.sourceLocation),
        frame_indexes: sortedInts(term.frame_indexes ?? term.frameIndexes ?? []),
      });
      order.push(key);
      return;
    }
    existing.frame_indexes = sortedInts([
      ...existing.frame_indexes,
      ...(term.frame_indexes ?? term.frameIndexes ?? []),
    ]);
    if (!existing.source_phrase) {
      existing.source_phrase = cleanTag(term.source_phrase ?? term.sourcePhrase ?? text);
    }
    if (!existing.source_location) {
      existing.source_location = stringValue(term.source_location ?? term.sourceLocation);
    }
  };

  for (const term of role.prompt_terms ?? []) addTerm(term);
  for (const row of sourceCaptionRowsForRole(role, framesByIndex)) {
    for (const tag of parseTags(row.caption)) {
      const candidate = promptTermCandidate(tag);
      if (!candidate) continue;
      addTerm({
        id: promptTermId(role.source_role_id, candidate.category, candidate.text),
        text: candidate.text,
        category: candidate.category,
        source_phrase: tag,
        source_location: `${row.sourceId} prompt`,
        frame_indexes: [row.frameIndex],
      });
    }
  }
  return order.map((key) => terms.get(key));
}

function sourceCaptionRowsForRole(role, framesByIndex) {
  const rows = [];
  for (const appearance of role.appearances ?? []) {
    const sourceId = stringValue(appearance.source_id ?? appearance.sourceId);
    const slotMatch = /^slot-(\d+)$/i.exec(sourceId);
    const isBase =
      sourceId === 'base' ||
      stringValue(appearance.source_kind ?? appearance.sourceKind).toLowerCase() === 'base';
    for (const frameIndex of appearance.frame_indexes ?? appearance.frameIndexes ?? []) {
      const frame = framesByIndex.get(Number(frameIndex));
      if (!frame) continue;
      if (slotMatch) {
        const caption = frame.charCaptions[Number(slotMatch[1])] ?? '';
        if (caption.trim()) rows.push({ frameIndex: Number(frameIndex), sourceId, caption });
      } else if (isBase && frame.baseCaption.trim()) {
        rows.push({ frameIndex: Number(frameIndex), sourceId: 'base', caption: frame.baseCaption });
      }
    }
  }
  return rows;
}

function framesByIndexMap(cache) {
  const result = new Map();
  for (const frame of cache.scriptSnapshot?.frames ?? []) {
    const parsed = frame?.parsed ?? {};
    result.set(Number(frame.index), {
      baseCaption: stringValue(parsed.baseCaption),
      charCaptions: Array.isArray(parsed.charCaptions) ? parsed.charCaptions.map(stringValue) : [],
    });
  }
  return result;
}

function rolePromptReplacementsWithAiTerms(existing, roles) {
  const existingByRoleId = new Map(
    existing
      .filter((replacement) => stringValue(replacement.sourceRoleId).trim())
      .map((replacement) => [stringValue(replacement.sourceRoleId).trim(), replacement]),
  );
  const replacements = [];
  const applied = new Set();
  let rulesAdded = 0;
  let changed = false;
  for (const role of roles) {
    const sourceRoleId = stringValue(role.source_role_id).trim();
    const promptTerms = (role.prompt_terms ?? []).filter((term) => cleanTag(term?.text));
    if (!sourceRoleId || promptTerms.length === 0) continue;
    const current = existingByRoleId.get(sourceRoleId);
    const next = replacementWithTerms(current, role, promptTerms);
    rulesAdded += next.rulesAdded;
    changed = changed || next.changed || !current;
    replacements.push(next.replacement);
    applied.add(sourceRoleId);
  }
  for (const replacement of existing) {
    if (!applied.has(stringValue(replacement.sourceRoleId).trim())) {
      replacements.push(replacement);
    }
  }
  changed = changed || JSON.stringify(existing) !== JSON.stringify(replacements);
  return { replacements, changed, rulesAdded };
}

function replacementWithTerms(existing, role, promptTerms) {
  const existingRules = Array.isArray(existing?.rules) ? existing.rules : [];
  const existingRulesByTerm = new Map();
  for (const rule of existingRules) {
    for (const term of rule.sourceTerms ?? []) {
      existingRulesByTerm.set(replacementTermKey(term), rule);
    }
  }
  const rules = [];
  const emitted = new Set();
  let rulesAdded = 0;
  for (const term of promptTerms) {
    const key = replacementTermKey(term);
    const existingRule = existingRulesByTerm.get(key);
    if (existingRule) {
      if (!emitted.has(existingRule.id)) {
        rules.push(existingRule);
        emitted.add(existingRule.id);
      }
      continue;
    }
    const replacementTerm = promptReplacementTermFromAi(term);
    const id = `role-${safeId(role.source_role_id)}-${replacementTerm.id}`;
    if (emitted.has(id)) continue;
    rules.push({ id, sourceTerms: [replacementTerm] });
    emitted.add(id);
    rulesAdded += 1;
  }
  for (const rule of existingRules) {
    if (!emitted.has(rule.id)) {
      rules.push(rule);
      emitted.add(rule.id);
    }
  }
  const replacement = {
    sourceRoleId: stringValue(role.source_role_id),
    displayLabel:
      stringValue(existing?.displayLabel).trim() ||
      stringValue(role.display_name).trim() ||
      stringValue(role.source_role_id),
    sourcePreview: promptTerms.map((term) => cleanTag(term.text)).filter(Boolean).join(', '),
    ...(existing?.targetCharacterId ? { targetCharacterId: existing.targetCharacterId } : {}),
    ...(stringValue(existing?.targetIdentityPrompt).trim()
      ? { targetIdentityPrompt: existing.targetIdentityPrompt }
      : {}),
    rules,
  };
  return {
    replacement,
    rulesAdded,
    changed: JSON.stringify(existing ?? null) !== JSON.stringify(replacement),
  };
}

function promptReplacementTermFromAi(term) {
  return {
    id: stringValue(term.id).trim() || promptTermId('', stringValue(term.category), term.text),
    text: cleanTag(term.text),
    category: stringValue(term.category || 'identity'),
    ...(cleanTag(term.source_phrase ?? term.sourcePhrase)
      ? { sourcePhrase: cleanTag(term.source_phrase ?? term.sourcePhrase) }
      : {}),
    ...(stringValue(term.source_location ?? term.sourceLocation).trim()
      ? { sourceLocation: stringValue(term.source_location ?? term.sourceLocation).trim() }
      : {}),
    ...(sortedInts(term.frame_indexes ?? term.frameIndexes ?? []).length > 0
      ? { frameIndexes: sortedInts(term.frame_indexes ?? term.frameIndexes ?? []) }
      : {}),
  };
}

function promptTermCandidate(tag) {
  const text = cleanTag(tag);
  const normalized = normalizedTagKey(text);
  if (!normalized || isGenericPromptIdentity(normalized) || isSceneOrActionTerm(normalized)) {
    return null;
  }
  if (isIdentityDescriptor(normalized) || looksLikeConcreteCharacterTag(text)) {
    return { text, category: 'identity' };
  }
  if (isBodyDescriptor(normalized)) return { text, category: 'body' };
  if (isAccessoryDescriptor(normalized)) return { text, category: 'accessory' };
  return null;
}

function isIdentityDescriptor(normalized) {
  return /\b(gyaru|kogal|onee gyaru|amesuku gyaru|demon girl|devil girl|dragon girl|succubus|demoness)\b/.test(
    normalized,
  );
}

function isBodyDescriptor(normalized) {
  return /\b(hair|hair buns?|double buns?|twin buns?|bun hair|twintails?|twin tails?|pony ?tail|pigtails?|braids?|bangs?|eyes?|iris|pupils?|ears?|animal ears|cat ears|fox ears|dog ears|wolf ears|rabbit ears|bunny ears|pointy ears|horns?|demon horns?|devil horns?|halo|fangs?|skin|face|tail|demon tail|devil tail|wings?|cristal wings?|crystal wings?|demon wings?|angel wings?|bat wings?|tattoo|mole|cleavage|collarbone|shoulders?|armpits?|chest|breasts?|bust|flat chest|midriff|abs|navel|stomach|thighs?|legs?|feet|toes?|hips?|waist)\b/.test(
    normalized,
  );
}

function isAccessoryDescriptor(normalized) {
  return /\b(glasses|sunglasses|eyewear|goggles|hat|cap|crown|tiara|hair ornament|hairclip|hair clip|hairband|headband|headdress|necklace|choker|collar|bracelet|ring|hair ribbon|ribbon|bow)\b/.test(
    normalized,
  );
}

function isSceneOrActionTerm(normalized) {
  return /\b(artist|quality|masterpiece|aesthetic|looking|sitting|standing|lying|kneeling|closed eyes|open mouth|blush|crying|grabbing|holding|hitting|pulling|lifting|touching|sex|cum|penetration|spread legs|censored|mosaic|bathroom|classroom|bedroom|outdoors|indoors)\b/.test(
    normalized,
  );
}

function isGenericPromptIdentity(normalized) {
  return /^(?:solo|1girl|2girls|girls?|1boy|2boys|boys?|female|male|woman|man|women|men)$/.test(
    normalized,
  );
}

function looksLikeConcreteCharacterTag(text) {
  return /[_\s]*\([^)]{3,}\)/.test(text) && !/^artist[:\s]/i.test(text);
}

function targetMissingRows(cache) {
  const rows = [];
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const sourceRows = sourceCaptionRowsForRole(role, framesByIndexMap(cache));
    const sourceTargets = new Set();
    for (const row of sourceRows) {
      for (const tag of parseTags(row.caption)) {
        const candidate = promptTermCandidate(tag);
        if (candidate && isRegressionTarget(candidate.text)) {
          sourceTargets.add(normalizedTagKey(candidate.text));
        }
      }
    }
    if (sourceTargets.size === 0) continue;
    const replacement = (cache.mapping?.rolePromptReplacements ?? []).find(
      (item) => stringValue(item.sourceRoleId) === stringValue(role.source_role_id),
    );
    const replacementTerms = new Set(
      (replacement?.rules ?? []).flatMap((rule) =>
        (rule.sourceTerms ?? []).map((term) => normalizedTagKey(term.text)),
      ),
    );
    const missing = [...sourceTargets].filter((term) => !replacementTerms.has(term));
    if (missing.length > 0) {
      rows.push({
        role_id: stringValue(role.source_role_id),
        missing_terms: missing,
      });
    }
  }
  return rows;
}

function isRegressionTarget(text) {
  const normalized = normalizedTagKey(text);
  return /\b(hair bun|double bun|twintails?|twin tails?|wings?|cristal wings?|crystal wings?|gyaru|kogal|demon girl|devil girl|dragon girl|demon horns?|demon tail)\b/.test(
    normalized,
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

function replacementTermKey(term) {
  return `${stringValue(term?.category || 'identity')}\u001f${normalizedTagKey(term?.text)}`;
}

function promptTermId(roleId, category, text) {
  const prefix = safeId(roleId) ? `role-${safeId(roleId)}-` : '';
  return `${prefix}${category || 'term'}-${safeId(text)}`;
}

function safeId(value) {
  return normalizedTagKey(value)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function sortedInts(values) {
  return (Array.isArray(values) ? values : [])
    .map(Number)
    .filter((value) => Number.isInteger(value))
    .sort((left, right) => left - right);
}

function normalizedTagKey(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/[_-]+/g, ' ')
    .replace(/[(){}\[\]'":!?，、；;]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function looksLikeRecastCache(cache) {
  return cache && typeof cache === 'object' && (cache.scriptId || cache.aiRoleExtraction || cache.mapping);
}

function isUnderSourceRoot(sourcePath, root) {
  const source = normalizePath(sourcePath);
  return source && root && (source === root || source.startsWith(`${root}/`));
}

function normalizePath(value) {
  return stringValue(value).replace(/\\/g, '/').replace(/\/+$/g, '');
}

function loadJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
  } catch {
    return null;
  }
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    assertTargets: false,
    reportUnchanged: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (arg === '--assert-targets') {
      parsed.assertTargets = true;
      continue;
    }
    if (arg === '--report-unchanged') {
      parsed.reportUnchanged = true;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    const value = args[++index];
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}
