import fs from 'node:fs';
import path from 'node:path';

const defaultCacheDir = path.join(
  process.env.APPDATA ?? '',
  'Novel Studio',
  'Novel Studio',
  'novel_studio',
  'script_recast',
  'cache',
);

const options = parseArgs(process.argv.slice(2));
const cacheDir = options.cacheDir ?? defaultCacheDir;
const backupDir =
  options.backupDir ??
  path.join('build', 'script_recast_role_field_proofread_backup_20260610');
const reportPath =
  options.report ??
  path.join('build', 'script_recast_role_field_proofread_20260610.json');

if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const files = fs
  .readdirSync(cacheDir)
  .filter((file) => /^script-.*\.json$/.test(file))
  .sort();

const summary = {
  cache_dir: cacheDir,
  backup_dir: path.resolve(backupDir),
  apply: options.apply,
  files_scanned: files.length,
  files_changed: 0,
  ai_stages_changed: 0,
  mapping_stages_changed: 0,
  role_fields_changed: 0,
  source_part_fields_changed: 0,
  non_role_fields_cleared: 0,
  raw_responses_removed: 0,
  diagnostics_cleared: 0,
  labels_changed: 0,
  removed_terms: 0,
  moved_terms: 0,
  duplicate_terms_removed: 0,
  no_source_terms_removed: 0,
  transient_terms_removed: 0,
  files: [],
};

const BANNED_FIELD_TERM_KEYS = new Set([
  'adjusting hair',
  'averting eyes',
  'avertising eyes',
  'bound legs',
  'breasts squeezed together',
  'covering one eye',
  'covering eyes',
  'dashed eyes',
  'feet up',
  'fingering through clothes',
  'foot on another',
  'foot on another s face',
  'hair spread out',
  'hands in another s clothes',
  'hands on another',
  'hands on another s clothes',
  'hands on another s legs',
  'hands on skirt',
  'heart in eye',
  'heart in eyes',
  'leg hold',
  'leg lock',
  'legs behind head',
  'm legs',
  'fetal position',
  'imminent attack',
  'narrowed eyes',
  'one breast out',
  'pants pull',
  'pantyhose pull',
  'partially submerged',
  'presenting removed panties',
  'presenting_removed_panties',
  'shirt lift',
  'sideways glance',
  'strap slip',
  'strap slips',
  'swimsuit pull',
  'one piece swimsuit pull',
  'tail grab',
  'uneven eyes',
  'upturned eyes',
  'upright straddle',
  'washing hair',
]);

for (const fileName of files) {
  const filePath = path.join(cacheDir, fileName);
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const original = JSON.stringify(cache);
  const frameTextByIndex = buildFrameTextByIndex(cache);
  const fileReport = {
    file_name: fileName,
    script_name: stringValue(cache.scriptName),
    ai_stages_changed: 0,
    mapping_stages_changed: 0,
    removed_terms: 0,
    samples: [],
  };

  cleanExtraction(cache, frameTextByIndex, fileReport);
  cleanMapping(cache, frameTextByIndex, fileReport);

  if (JSON.stringify(cache) !== original) {
    summary.files_changed += 1;
    summary.files.push(fileReport);
    if (options.apply) {
      fs.mkdirSync(backupDir, { recursive: true });
      const backupPath = path.join(backupDir, fileName);
      if (!fs.existsSync(backupPath)) {
        fs.copyFileSync(filePath, backupPath);
      }
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
}

fs.mkdirSync(path.dirname(reportPath), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function cleanExtraction(cache, frameTextByIndex, fileReport) {
  patchKnownRoleIds(cache);
  const extraction = cache.aiRoleExtraction;
  if (!extraction || typeof extraction !== 'object') return;

  if (stringValue(extraction.raw_response).trim()) {
    delete extraction.raw_response;
    summary.raw_responses_removed += 1;
  }
  for (const role of Array.isArray(extraction.roles) ? extraction.roles : []) {
    const roleBefore = JSON.stringify(role);
    const allRoleTerms = [];

    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      const before = JSON.stringify(stage);
      const corpus = evidenceCorpus(frameTextByIndex, stage.frame_indexes ?? role.frame_indexes);
      const clean = sanitizeFiveFields(
        {
          identity: stage.identity,
          upperBody: stage.upper_body,
          lowerBody: stage.lower_body,
          upperClothing: stage.upper_clothing,
          lowerClothing: stage.lower_clothing,
        },
        corpus,
        fileReport,
      );

      stage.identity = clean.identity;
      stage.upper_body = clean.upperBody;
      stage.lower_body = clean.lowerBody;
      stage.upper_clothing = clean.upperClothing;
      stage.lower_clothing = clean.lowerClothing;
      stage.evidence_terms = stableEvidenceTerms(clean);
      stage.missing_fields = Array.isArray(stage.missing_fields)
        ? stage.missing_fields.filter((field) => field.startsWith('missing_'))
        : [];
      stage.field_reasons = cleanFieldReasons(stage.field_reasons);
      sanitizeStageNonRole(stage, corpus, fileReport);
      stage.label = labelForStage(stage.label, clean);

      allRoleTerms.push(...stage.evidence_terms);
      if (JSON.stringify(stage) !== before) {
        fileReport.ai_stages_changed += 1;
        summary.ai_stages_changed += 1;
      }
    }

    role.evidence_terms = uniqueTerms(allRoleTerms);
    role.raw_identity_tags = filterIdentityList(role.raw_identity_tags, role.evidence_terms);
    role.variant_tags = filterVariantList(role.variant_tags, role.evidence_terms);
    if (isStructuralLabel(role.display_name)) {
      role.display_name = displayNameFromRole(role);
    }
    if (JSON.stringify(role) !== roleBefore) {
      // Count role-level diagnostics once; stage field counts are tracked in sanitizeFiveFields.
    }
  }
}

function sanitizeStageNonRole(stage, corpus, fileReport) {
  if (!('non_role' in stage) && !('non_role_materialized' in stage)) return;
  const before = stringValue(stage.non_role);
  const kept = [];
  for (const term of splitTerms(before)) {
    if (!termHasEvidence(term, corpus)) {
      summary.non_role_fields_cleared += 1;
      if (fileReport.samples.length < 20) {
        fileReport.samples.push({
          reason: 'non_role_no_source_evidence',
          term: redactIfNeeded(term),
        });
      }
      continue;
    }
    kept.push(term);
  }
  const after = uniqueTerms(kept).join(', ');
  if (after) {
    stage.non_role = after;
    stage.non_role_materialized = true;
    if (after !== before || stage.non_role_materialized !== true) {
      summary.non_role_fields_cleared += 1;
    }
    return;
  }
  summary.non_role_fields_cleared += 1;
  delete stage.non_role;
  delete stage.non_role_materialized;
}

function cleanMapping(cache, frameTextByIndex, fileReport) {
  const assemblies = cache.mapping?.roleAssemblies;
  if (!Array.isArray(assemblies)) return;
  for (const assembly of assemblies) {
    for (const stage of Array.isArray(assembly.stages) ? assembly.stages : []) {
      const before = JSON.stringify(stage);
      const corpus = evidenceCorpus(frameTextByIndex, stage.frameIndexes);
      const clean = sanitizeFiveFields(
        {
          identity: stage.sourceParts?.identity,
          upperBody: stage.sourceParts?.upperBody,
          lowerBody: stage.sourceParts?.lowerBody,
          upperClothing: stage.sourceParts?.upperClothing,
          lowerClothing: stage.sourceParts?.lowerClothing,
        },
        corpus,
        fileReport,
        { sourceParts: true },
      );
      stage.sourceParts = dropEmptyObject({
        identity: clean.identity,
        upperBody: clean.upperBody,
        lowerBody: clean.lowerBody,
        upperClothing: clean.upperClothing,
        lowerClothing: clean.lowerClothing,
      });
      stage.sourceSummary = sourceSummary(stage.sourceParts);
      stage.label = labelForStage(stage.label, clean);
      if (JSON.stringify(stage) !== before) {
        fileReport.mapping_stages_changed += 1;
        summary.mapping_stages_changed += 1;
      }
    }
  }
}

function sanitizeFiveFields(rawParts, corpus, fileReport, context = {}) {
  const buckets = {
    identity: [],
    upperBody: [],
    lowerBody: [],
    upperClothing: [],
    lowerClothing: [],
  };
  const seen = new Set();

  for (const field of Object.keys(buckets)) {
    for (const rawTerm of splitTerms(rawParts[field])) {
      const term = cleanDisplayTerm(rawTerm);
      const key = termKey(term);
      if (!key) continue;
      const routed = routeTerm(field, term);
      if (!routed) {
        recordRemoval(fileReport, term, 'transient_or_invalid', context);
        continue;
      }
      if (!termHasEvidence(term, corpus)) {
        recordRemoval(fileReport, term, 'no_source_evidence', context);
        continue;
      }
      const dedupeKey = `${routed}\u001f${key}`;
      const crossFieldKey = key;
      if (seen.has(dedupeKey) || seen.has(crossFieldKey)) {
        summary.duplicate_terms_removed += 1;
        recordRemoval(fileReport, term, 'duplicate', context);
        continue;
      }
      seen.add(dedupeKey);
      seen.add(crossFieldKey);
      if (routed !== field) {
        summary.moved_terms += 1;
      }
      buckets[routed].push(term);
    }
  }

  for (const [field, values] of Object.entries(buckets)) {
    const before = stringValue(rawParts[field]);
    const after = values.join(', ');
    if (before !== after) {
      if (context.sourceParts) {
        summary.source_part_fields_changed += 1;
      } else {
        summary.role_fields_changed += 1;
      }
    }
  }

  return {
    identity: buckets.identity.join(', '),
    upperBody: buckets.upperBody.join(', '),
    lowerBody: buckets.lowerBody.join(', '),
    upperClothing: buckets.upperClothing.join(', '),
    lowerClothing: buckets.lowerClothing.join(', '),
  };
}

function routeTerm(field, term) {
  if (shouldDropTerm(term)) return null;
  const key = termKey(term);
  if (!key) return null;
  if (isNamedCharacterTerm(term)) return 'identity';
  if (field === 'identity') {
    if (isIdentityTerm(term)) return 'identity';
  }
  if (isLowerClothingTerm(term)) return 'lowerClothing';
  if (isUpperClothingTerm(term)) return 'upperClothing';
  if (isLowerBodyTerm(term)) return 'lowerBody';
  if (isUpperBodyTerm(term)) return 'upperBody';
  if (field === 'upperBody' || field === 'lowerBody') return field;
  return null;
}

function shouldDropTerm(term) {
  const normalized = termKey(term);
  if (!normalized) return true;
  if (BANNED_FIELD_TERM_KEYS.has(normalized)) return true;
  if (isPureFranchiseQualifierTerm(term)) return true;
  if (/^(none|null|nil|unknown|n\/a|empty|other|stage|slot|source slot)$/u.test(normalized)) {
    return true;
  }
  if (/^(pose|poses|action|actions|explicit|adult|nsfw|safe|safety|review|warning)$/u.test(normalized)) {
    return true;
  }
  if (/\b(in later frames|in some frames|where present|when present|only coverage|not consistently|varies by frame|if visible|when visible)\b/u.test(normalized)) {
    return true;
  }
  if (isGarmentTerm(term)) {
    return false;
  }
  return transientPattern().test(normalized);
}

function transientPattern() {
  return /\b(gym|exercise|workout|yoga pose|pose|push up|wooden floor|floor|bed|pillow|room|hallway|background|camera|pov|close up|from side|side view|dutch angle|looking|sideways glance|standing|sitting|kneeling|lying|running|walking|stretching|bending|squatting|spread legs|m legs|fetal position|upright straddle|arms up|hands up|holding|grabbing|touching|hands on|hands in|hand over mouth|stun gun|toward another|licking|sucking|fingering|sex|intercourse|masturbat|penetrat|cum|semen|orgasm|saliva|pussy|penis|nipples?|areola|pubic|vibrator|sex toy|toy|navel|ass|butt|stomach bulge|thighs?|blush|nose blush|smile|open mouth|dashed eyes|covering eyes|covering one eye|heavy breathing|tears|crying|angry|embarrassed|wet|sweaty|sweat|stained|torn|ripped|damaged|naked|nude|open towel|open clothes|taking off|take off|undressing|lifted|lifting|pulled|pulling|pants pull|pantyhose pull|partially submerged|imminent attack|covered nipples|facial|leash handling)\b/u;
}

function patchKnownRoleIds(cache) {
  const renames = {
    'role-star-shaped-pupils': 'role-bunny-girl',
  };
  const json = JSON.stringify(cache);
  let next = json;
  for (const [from, to] of Object.entries(renames)) {
    next = next.replaceAll(from, to);
  }
  if (next !== json) {
    const patched = JSON.parse(next);
    for (const key of Object.keys(cache)) delete cache[key];
    Object.assign(cache, patched);
  }
}

function isIdentityTerm(term) {
  const key = termKey(term);
  if (isNamedCharacterTerm(term)) return true;
  if (/^(1?girl|1?boy|woman|man|male|female|loli|child|boy|girl|multiple boys|multiple girls)$/u.test(key)) {
    return true;
  }
  if (/^(pekomama|elf|monster|dog|cat|animal)$/u.test(key)) return true;
  if (isStructuralLabel(term) || shouldDropTerm(term)) return false;
  if (/[()]/u.test(term)) return true;
  if (isGarmentTerm(term) || isBodyDescriptorTerm(term)) return false;
  return key.includes('(') || /^[a-z0-9]+(?: [a-z0-9]+){1,5}$/u.test(key);
}

function isNamedCharacterTerm(term) {
  const clean = cleanDisplayTerm(term);
  if (!clean || isPureFranchiseQualifierTerm(clean)) return false;
  const parens = [...clean.matchAll(/\(([^)]+)\)/gu)].map((item) => item[1].trim());
  const base = clean.slice(0, clean.indexOf('(') >= 0 ? clean.indexOf('(') : clean.length).trim();
  if (base && parens.some(isFranchiseQualifier)) return true;
  const lower = clean.toLowerCase();
  if (!lower.includes('_')) return false;
  const key = termKey(clean);
  if (isGarmentTerm(clean) || isBodyDescriptorTerm(clean) || transientPattern().test(key)) {
    return false;
  }
  return /^[a-z][a-z0-9_]*(?:\([^)]+\)|_[a-z0-9]+)*(?:\s+cosplay)?$/iu.test(clean);
}

function isPureFranchiseQualifierTerm(term) {
  const match = /^\(([^)]+)\)$/u.exec(cleanDisplayTerm(term));
  return Boolean(match && isFranchiseQualifier(match[1]));
}

function isFranchiseQualifier(value) {
  const key = normalizeForEvidence(value);
  return /\b(princess connect|blue archive|genshin|honkai|star rail|azur lane|fate|date a live|girls und panzer|hololive|touhou|vocaloid|project sekai|arknights|umamusume|nikke|granblue|glanblue|kancolle|idolmaster|re zero|rezero)\b/u.test(key);
}

function isStructuralLabel(value) {
  return /^(slot|stage|source slot|role source slot|role slot)[-\s]?\d*$/iu.test(
    stringValue(value).trim(),
  );
}

function isUpperBodyTerm(term) {
  const key = termKey(term);
  if (/\b(covering eyes|covering one eye|dashed eyes)\b/u.test(key)) return false;
  return /\b(hair|twintails?|twin tails?|ponytails?|braids?|headdress|ahoge|eyes?|ears?|horns?|halo|headband|headwear|hat|beret|ornament|ribbon|bow|tiara|necklace|choker|collar|earrings?|fang|teeth|breasts?|chest|skin|tattoo|mask)\b/u.test(key);
}

function isLowerBodyTerm(term) {
  const key = termKey(term);
  return /\b(tail|legs?|feet|foot|anklet|thigh strap)\b/u.test(key);
}

function isUpperClothingTerm(term) {
  const key = termKey(term);
  return /\b(shirt|blouse|jacket|coat|overcoat|hoodie|sweater|dress|uniform|bra|bikini|bikini top|neckerchief|sailor collar|harness|leotard|bodysuit|swimsuit|school swimsuit|one piece swimsuit|kimono|robe|armor|apron|vest|suit|gloves?|sleeves?|sports bra|towel|mantle|cloak|cape|belt|strap|bowtie|necktie|tie|frills?|lingerie|outfit|costume|clothes|clothing|pajamas|tanktop|tank top|cheerleader|nun)\b/u.test(key);
}

function isLowerClothingTerm(term) {
  const key = termKey(term);
  return /\b(pants|trousers|shorts|skirt|miniskirt|panties|underwear|briefs|leggings|stockings?|socks?|thighhighs?|pantyhose|garter|shoes?|boots?|sandals?|heels?|loafers?|sneakers?|footwear|legwear|bikini bottom|swimsuit bottom|fundoshi|pelvic curtain|mary janes?)\b/u.test(key);
}

function isGarmentTerm(term) {
  return isUpperClothingTerm(term) || isLowerClothingTerm(term);
}

function isBodyDescriptorTerm(term) {
  return isUpperBodyTerm(term) || isLowerBodyTerm(term);
}

function termHasEvidence(term, corpus) {
  const key = termKey(term);
  if (!key) return false;
  if (key === 'girl') return /\b(1girl|girl)\b/u.test(corpus);
  if (key === 'boy') return /\b(1boy|boy)\b/u.test(corpus);
  if (key === 'man') return /\b(man|male|1boy|boy)\b/u.test(corpus);
  if (key === 'woman') return /\b(woman|female|1girl|girl)\b/u.test(corpus);
  return new RegExp(`(^|[^a-z0-9])${escapeRegExp(key)}([^a-z0-9]|$)`, 'u').test(corpus);
}

function buildFrameTextByIndex(cache) {
  const result = new Map();
  for (const frame of Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : []) {
    const parts = [];
    collectText(frame.parsed, parts);
    collectText(frame.rawJson, parts);
    result.set(Number(frame.index), normalizeForEvidence(parts.join(' ')));
  }
  return result;
}

function collectText(value, out) {
  if (typeof value === 'string') {
    out.push(value);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, out);
    return;
  }
  if (!value || typeof value !== 'object') return;
  for (const [key, nested] of Object.entries(value)) {
    if (/negative|uc|signed_hash|image|bytes|base64/i.test(key)) continue;
    collectText(nested, out);
  }
}

function evidenceCorpus(frameTextByIndex, frameIndexes) {
  const parts = [];
  for (const value of Array.isArray(frameIndexes) ? frameIndexes : []) {
    const frameIndex = Number(value);
    if (frameTextByIndex.has(frameIndex)) {
      parts.push(frameTextByIndex.get(frameIndex));
    }
  }
  return parts.join(' ');
}

function stableEvidenceTerms(parts) {
  return uniqueTerms([
    ...splitTerms(parts.identity),
    ...splitTerms(parts.upperBody),
    ...splitTerms(parts.lowerBody),
    ...splitTerms(parts.upperClothing),
    ...splitTerms(parts.lowerClothing),
  ]);
}

function filterIdentityList(values, evidenceTerms) {
  const evidenceKeys = new Set(evidenceTerms.map(termKey));
  return uniqueTerms(
    (Array.isArray(values) ? values : []).filter((value) => {
      const key = termKey(value);
      return key && evidenceKeys.has(key);
    }),
  );
}

function filterVariantList(values, evidenceTerms) {
  const evidence = evidenceTerms.map(termKey).join(' ');
  return uniqueTerms(
    (Array.isArray(values) ? values : []).filter((value) => {
      const key = termKey(value);
      return key && evidence.includes(key);
    }),
  );
}

function cleanFieldReasons(value) {
  if (!value || typeof value !== 'object') return {};
  const result = {};
  for (const key of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
    if (typeof value[key] === 'string' && value[key].trim()) {
      result[key] = value[key];
    }
  }
  return result;
}

function labelForStage(label, parts) {
  const current = stringValue(label).trim();
  if (hasChinese(current)) {
    return current;
  }
  const terms = [
    ...splitTerms(parts.upperClothing),
    ...splitTerms(parts.lowerClothing),
    ...splitTerms(parts.upperBody).filter((term) => /collar|choker|headband|hat|ornament|tail/i.test(term)),
  ];
  if (terms.length > 0) {
    const next = uniqueTerms(terms).slice(0, 4).join(' / ');
    if (next && next !== label) summary.labels_changed += 1;
    return next;
  }
  return stringValue(label);
}

function hasChinese(value) {
  return /[\u4e00-\u9fff]/u.test(stringValue(value));
}

function displayNameFromRole(role) {
  for (const stage of Array.isArray(role.stages) ? role.stages : []) {
    const identity = splitTerms(stage.identity).find((term) => !/^(girl|boy|man|woman)$/i.test(term));
    if (identity) return identity;
  }
  for (const stage of Array.isArray(role.stages) ? role.stages : []) {
    const identity = splitTerms(stage.identity)[0];
    if (identity) return identity;
  }
  return 'unnamed role';
}

function sourceSummary(sourceParts) {
  return ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']
    .map((key) => stringValue(sourceParts?.[key]).trim())
    .filter(Boolean)
    .join(', ');
}

function dropEmptyObject(value) {
  const result = {};
  for (const [key, nested] of Object.entries(value)) {
    if (stringValue(nested).trim()) result[key] = nested;
  }
  return result;
}

function splitTerms(value) {
  const source = stringValue(value);
  const terms = [];
  let current = '';
  let depth = 0;
  for (const char of source) {
    if ('([{'.includes(char)) depth += 1;
    if (')]}'.includes(char) && depth > 0) depth -= 1;
    if (char === ',' && depth === 0) {
      pushSplitTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushSplitTerm(terms, current);
  return terms;
}

function pushSplitTerm(terms, value) {
  const clean = cleanDisplayTerm(value);
  if (!clean) return;
  if (/^\|.*\|$/.test(clean) && clean.includes('|')) {
    for (const part of clean.split('|')) {
      const nested = cleanDisplayTerm(part);
      if (nested) terms.push(nested);
    }
    return;
  }
  terms.push(clean);
}

function cleanDisplayTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/g, '')
    .replace(/::/g, '')
    .replace(/[{}[\]]/g, '')
    .replace(/^[\s:|，、;；]+|[\s:|，、;；]+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function termKey(value) {
  return normalizeForEvidence(cleanDisplayTerm(value));
}

function normalizeForEvidence(value) {
  return stringValue(value)
    .toLowerCase()
    .replace(/\b-?\d+(?:\.\d+)?::/g, ' ')
    .replace(/::/g, ' ')
    .replace(/[_-]+/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function uniqueTerms(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const clean = cleanDisplayTerm(value);
    const key = termKey(clean);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(clean);
  }
  return result;
}

function recordRemoval(fileReport, term, reason, context) {
  summary.removed_terms += 1;
  fileReport.removed_terms += 1;
  if (reason === 'no_source_evidence') summary.no_source_terms_removed += 1;
  if (reason === 'transient_or_invalid') summary.transient_terms_removed += 1;
  if (context.sourceParts) {
    // Source-part removals are counted through source_part_fields_changed.
  }
  if (fileReport.samples.length < 20) {
    fileReport.samples.push({ reason, term: redactIfNeeded(term) });
  }
}

function redactIfNeeded(term) {
  return /sex|cum|penis|pussy|nipples?|areola|orgasm|semen|masturbat|penetrat/i.test(term)
    ? '[redacted]'
    : term;
}

function parseArgs(args) {
  const parsed = {
    apply: false,
    cacheDir: undefined,
    backupDir: undefined,
    report: undefined,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--apply') {
      parsed.apply = true;
      continue;
    }
    if (arg === '--dry-run') {
      parsed.apply = false;
      continue;
    }
    if (!arg.startsWith('--')) continue;
    const equal = arg.indexOf('=');
    const key = equal > 0 ? arg.slice(2, equal) : arg.slice(2);
    const value =
      equal > 0
        ? arg.slice(equal + 1)
        : args[index + 1]?.startsWith('--')
          ? ''
          : args[index + 1] ?? '';
    if (equal < 0 && value !== '') index += 1;
    if (key === 'cache-dir') parsed.cacheDir = value;
    if (key === 'backup-dir') parsed.backupDir = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}
