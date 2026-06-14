import fs from 'node:fs';
import path from 'node:path';

const FIELD_KEYS = [
  'identity',
  'upper_body',
  'lower_body',
  'upper_clothing',
  'lower_clothing',
];

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
  "foot on another's face",
  'hair spread out',
  "hands in another's clothes",
  'hands on another',
  "hands on another's clothes",
  "hands on another's legs",
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

const options = parseArgs(process.argv.slice(2));
if (!options.cacheDir) throw new Error('Missing --cache-dir');
if (!fs.existsSync(options.cacheDir)) {
  throw new Error(`Missing cache dir: ${options.cacheDir}`);
}

const files = fs
  .readdirSync(options.cacheDir)
  .filter((file) => /^script-.*\.json$/u.test(file))
  .sort();

const bannedReport = {
  cache_dir: options.cacheDir,
  hit_count: 0,
  file_count: 0,
  byTerm: {},
  topFiles: [],
  samples: [],
};
const genericReport = {
  cache_dir: options.cacheDir,
  hit_count: 0,
  hits: [],
};
const duplicateReport = {
  cache_dir: options.cacheDir,
  hit_count: 0,
  hits: [],
};

for (const file of files) {
  const cache = JSON.parse(fs.readFileSync(path.join(options.cacheDir, file), 'utf8'));
  scanBannedFields(cache, file, bannedReport);
  scanPreciseGenericNamed(cache, file, genericReport);
  scanDuplicateSourceRoleIds(cache, file, duplicateReport);
}

bannedReport.file_count = new Set(bannedReport.samples.map((hit) => hit.file)).size;
bannedReport.topFiles = summarizeTopFiles(bannedReport.samples);

writeJson(options.bannedReport, bannedReport);
writeJson(options.genericReport, genericReport);
writeJson(options.duplicateReport, duplicateReport);

const summary = {
  banned_field_terms: bannedReport.hit_count,
  precise_generic_named: genericReport.hit_count,
  duplicate_source_role_id: duplicateReport.hit_count,
  banned_report: options.bannedReport,
  generic_report: options.genericReport,
  duplicate_report: options.duplicateReport,
};
console.log(JSON.stringify(summary, null, 2));

function scanBannedFields(cache, file, report) {
  const scriptName = stringValue(cache.scriptName);
  let fileHits = 0;
  for (const role of rolesOf(cache)) {
    const roleId = stringValue(role.source_role_id);
    for (const stage of Array.isArray(role.stages) ? role.stages : []) {
      for (const field of FIELD_KEYS) {
        for (const term of splitTerms(stage[field])) {
          const key = termKey(term);
          if (!BANNED_FIELD_TERM_KEYS.has(key)) continue;
          report.hit_count += 1;
          fileHits += 1;
          report.byTerm[key] = (report.byTerm[key] ?? 0) + 1;
          if (report.samples.length < options.maxSamples) {
            report.samples.push({
              file,
              scriptName,
              role: roleId,
              stage: stringValue(stage.stage_id),
              field,
              term: key,
              value: stringValue(stage[field]),
            });
          }
        }
      }
    }
  }
  if (fileHits > 0 && report.samples.length < options.maxSamples) {
    // Counted above; samples remain term-level for compatibility with prior reports.
  }
}

function scanPreciseGenericNamed(cache, file, report) {
  const scriptName = stringValue(cache.scriptName);
  const frames = new Map();
  for (const frame of Array.isArray(cache.scriptSnapshot?.frames)
    ? cache.scriptSnapshot.frames
    : []) {
    frames.set(Number(frame.index), frame);
  }

  for (const role of rolesOf(cache)) {
    if (!isGenericRole(role)) continue;
    const samples = [];
    let hitCount = 0;
    for (const appearance of Array.isArray(role.appearances) ? role.appearances : []) {
      const sourceId = stringValue(appearance.source_id);
      const slotMatch = /^slot-(\d+)$/u.exec(sourceId);
      if (!slotMatch) continue;
      const slotIndex = Number(slotMatch[1]);
      for (const frameIndex of Array.isArray(appearance.frame_indexes)
        ? appearance.frame_indexes
        : []) {
        const frame = frames.get(Number(frameIndex));
        const caption = stringValue(frame?.parsed?.charCaptions?.[slotIndex]);
        const namedTerms = extractNamedTermsFromCaption(caption);
        if (namedTerms.length === 0) continue;
        hitCount += 1;
        if (samples.length < 8) {
          samples.push({
            frame: Number(frameIndex),
            source_id: sourceId,
            named_terms: namedTerms.slice(0, 4),
            caption: caption.slice(0, 240),
          });
        }
      }
    }
    if (hitCount > 0) {
      report.hit_count += 1;
      report.hits.push({
        file,
        scriptName,
        source_role_id: stringValue(role.source_role_id),
        display_name: stringValue(role.display_name),
        samples,
        hit_count: hitCount,
      });
    }
  }
}

function scanDuplicateSourceRoleIds(cache, file, report) {
  const byId = new Map();
  for (const role of rolesOf(cache)) {
    const id = stringValue(role.source_role_id);
    if (!id) continue;
    if (!byId.has(id)) byId.set(id, []);
    byId.get(id).push(role);
  }
  for (const [sourceRoleId, roles] of byId.entries()) {
    if (roles.length < 2) continue;
    report.hit_count += 1;
    report.hits.push({
      file,
      scriptName: stringValue(cache.scriptName),
      source_role_id: sourceRoleId,
      count: roles.length,
      display_names: roles.map((role) => stringValue(role.display_name)),
    });
  }
}

function rolesOf(cache) {
  return Array.isArray(cache.aiRoleExtraction?.roles) ? cache.aiRoleExtraction.roles : [];
}

function isGenericRole(role) {
  const id = termKey(role.source_role_id);
  const display = termKey(role.display_name);
  const canonical = termKey(role.canonical_name);
  return (
    /^role source slot \d+/.test(id) ||
    /^(girl|boy|male|female|man|woman|faceless female|faceless male|unresolved role)$/.test(
      display,
    ) ||
    /^(girl|boy|male|female|man|woman|faceless female|faceless male|unresolved role)$/.test(
      canonical,
    )
  );
}

function extractNamedTermsFromCaption(caption) {
  return uniqueTerms(normalizeSourceTerms(splitTerms(caption)).filter(isNamedSourceTerm));
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

function normalizeSourceTerms(terms) {
  const result = [];
  for (let index = 0; index < terms.length; index += 1) {
    const term = cleanDisplayTerm(terms[index]);
    if (!term) continue;
    const next = cleanDisplayTerm(terms[index + 1]);
    if (next && isPureFranchiseQualifierTerm(next) && canPrefixFranchiseQualifier(term)) {
      result.push(`${term} ${next}`);
      index += 1;
      continue;
    }
    if (isPureFranchiseQualifierTerm(term)) continue;
    result.push(term);
  }
  return result;
}

function isNamedSourceTerm(term) {
  const clean = cleanDisplayTerm(term);
  const key = termKey(clean);
  if (!clean || !key || isPureFranchiseQualifierTerm(clean)) return false;
  const parens = [...clean.matchAll(/\(([^)]+)\)/gu)].map((item) => item[1].trim());
  const base = clean.slice(0, clean.indexOf('(') >= 0 ? clean.indexOf('(') : clean.length).trim();
  if (base && parens.some(isFranchiseQualifier)) return true;
  if (!clean.includes('_')) return false;
  if (isDropTermKey(key) || isGarmentTerm(key) || isBodyDescriptorTerm(key)) return false;
  return /^[a-z][a-z0-9_]*(?:\([^)]+\)|_[a-z0-9]+)*(?:\s+cosplay)?$/iu.test(clean);
}

function canPrefixFranchiseQualifier(term) {
  const key = termKey(term);
  if (!key || isDropTermKey(key)) return false;
  if (/^(1girl|1boy|girl|boy|woman|man|male|female|loli|child)$/u.test(key)) return false;
  if (isGarmentTerm(key) || isBodyDescriptorTerm(key)) return false;
  return /^[a-z][a-z0-9_'\- ]{1,80}$/iu.test(cleanDisplayTerm(term));
}

function isPureFranchiseQualifierTerm(term) {
  const match = /^\(([^)]+)\)$/u.exec(cleanDisplayTerm(term));
  return Boolean(match && isFranchiseQualifier(match[1]));
}

function isFranchiseQualifier(value) {
  const key = termKey(value);
  return /\b(princess connect|blue archive|genshin|honkai|star rail|azur lane|fate|date a live|girls und panzer|hololive|touhou|vocaloid|project sekai|arknights|umamusume|nikke|granblue|glanblue|kancolle|idolmaster|re:?zero|re zero|rezero)\b/u.test(key);
}

function isDropTermKey(key) {
  if (BANNED_FIELD_TERM_KEYS.has(key)) return true;
  if (/^(none|null|nil|unknown|n\/a|empty|other)$/u.test(key)) return true;
  return /\b(looking|smile|open mouth|closed eyes|dashed eyes|covering eyes|covering one eye|blush|tears?|crying|holding|hands on|hands in|grabbing|touching|licking|sucking|fingering|sex|intercourse|cum|orgasm|pussy|penis|nipples?|ass|spread legs|m legs|pantyhose pull|pants pull|shirt pull|swimsuit pull|magic wand|spoken|solo|background|camera|pov)\b/u.test(
    key,
  );
}

function isGarmentTerm(key) {
  return /\b(shirt|blouse|jacket|coat|hoodie|sweater|dress|uniform|bra|bikini|neckerchief|sailor collar|leotard|bodysuit|swimsuit|kimono|robe|armor|apron|vest|suit|gloves?|sleeves?|towel|cloak|cape|belt|strap|bowtie|necktie|tie|frills?|lingerie|outfit|costume|clothes|clothing|pajamas|tank top|pants|trousers|shorts|skirt|panties|underwear|briefs|leggings|stockings?|socks?|thighhighs?|pantyhose|garter|shoes?|boots?|sandals?|heels?|loafers?|sneakers?|footwear|legwear)\b/u.test(
    key,
  );
}

function isBodyDescriptorTerm(key) {
  return /\b(hair|bangs|twintails?|ponytails?|braids?|ahoge|eyes?|pupils?|iris|ears?|horns?|halo|headband|headdress|hat|ornament|ribbon|bow|necklace|choker|collar|earrings?|fangs?|breasts?|chest|skin|scar|tattoo|mole|mask|glasses|tail|legs?|feet|foot|anklet|thigh strap)\b/u.test(
    key,
  );
}

function summarizeTopFiles(samples) {
  const counts = new Map();
  for (const sample of samples) {
    counts.set(sample.file, (counts.get(sample.file) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 20)
    .map(([file, hit_count]) => ({ file, hit_count }));
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
      pushTerm(terms, current);
      current = '';
    } else {
      current += char;
    }
  }
  pushTerm(terms, current);
  return terms;
}

function pushTerm(terms, value) {
  const term = cleanDisplayTerm(value);
  if (term) terms.push(term);
}

function cleanDisplayTerm(value) {
  return stringValue(value)
    .replace(/\b-?\d+(?:\.\d+)?::/gu, '')
    .replace(/::/gu, '')
    .replace(/[{}[\]]/gu, '')
    .replace(/^[\s:|,+]+|[\s:|,+]+$/gu, '')
    .replace(/\s+/gu, ' ')
    .trim();
}

function termKey(value) {
  return cleanDisplayTerm(value)
    .toLowerCase()
    .replace(/[_-]+/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
}

function stringValue(value) {
  return typeof value === 'string' ? value : value == null ? '' : String(value);
}

function writeJson(filePath, value) {
  if (!filePath) return;
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function parseArgs(args) {
  const parsed = {
    maxSamples: 100,
    bannedReport: path.join('build', 'ntr_story_semantic_rework2_banned_field_terms.json'),
    genericReport: path.join('build', 'ntr_story_semantic_rework2_precise_generic_named.json'),
    duplicateReport: path.join('build', 'ntr_story_semantic_rework2_duplicate_source_role_id.json'),
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
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
    if (key === 'banned-report') parsed.bannedReport = value;
    if (key === 'generic-report') parsed.genericReport = value;
    if (key === 'duplicate-report') parsed.duplicateReport = value;
    if (key === 'max-print' || key === 'max-samples') {
      parsed.maxSamples = Number(value) || parsed.maxSamples;
    }
  }
  return parsed;
}
