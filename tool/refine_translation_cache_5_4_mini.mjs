import fs from 'node:fs';
import path from 'node:path';

const MODEL = process.env.REFINE_MODEL || 'gpt-5.4-mini';
const BATCH_SIZE = Number.parseInt(process.env.REFINE_BATCH_SIZE || '60', 10);
const MAX_ITEMS = Number.parseInt(process.env.REFINE_MAX_ITEMS || '0', 10);
const DRY_RUN = process.env.REFINE_DRY_RUN === '1';
const ALLOW_MODEL_CALLS = process.env.REFINE_ALLOW_MODEL_CALLS === '1';
const SOURCE = 'gpt-5.4-mini-refine';
const ROOT = process.env.REFINE_ROOT || 'E:/';
const ARTIST_CHAIN_PATHS = [
  process.env.REFINE_ARTIST_CHAINS_PATH,
  path.join(
    process.env.APPDATA || '',
    'Novel Studio',\n  'Novel Studio',
    'novel_studio',
    'library',
    'artist_chains.json',
  ),
  path.join(process.cwd(), 'assets/json/legacy_artist_studio_seed.json'),
].filter(Boolean);
const ALLOWED_CATEGORIES = new Set([
  'character',
  'upperBody',
  'lowerBody',
  'upperClothing',
  'lowerClothing',
  'clothing',
  'action',
  'scene',
  'camera',
  'artist',
  'style',
  'quality',
  'negativeQuality',
  'negativeBody',
  'negativeArtist',
  'negativeContent',
  'promptSyntax',
  'other',
]);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const payload = `${JSON.stringify(value, null, 2)}\n`;
  for (let attempt = 1; attempt <= 8; attempt += 1) {
    try {
      fs.writeFileSync(filePath, payload, 'utf8');
      return;
    } catch (error) {
      if (!['EBUSY', 'EPERM'].includes(error?.code) || attempt === 8) {
        throw error;
      }
      sleepSync(150 * attempt);
    }
  }
}

function sleepSync(milliseconds) {
  const buffer = new SharedArrayBuffer(4);
  const view = new Int32Array(buffer);
  Atomics.wait(view, 0, 0, milliseconds);
}

function walkFiles(root, fileName) {
  const found = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isFile() && entry.name === fileName) {
        found.push(fullPath);
      } else if (entry.isDirectory()) {
        stack.push(fullPath);
      }
    }
  }
  return found;
}

function findSettings(root) {
  for (const filePath of walkFiles(root, 'settings.json')) {
    try {
      const settings = readJson(filePath);
      if (settings.ai_url && settings.ai_key) {
        return settings;
      }
    } catch {
      // Ignore malformed unrelated settings files.
    }
  }
  throw new Error('No settings.json with ai_url and ai_key was found.');
}

function findTranslationCache(root) {
  const candidates = walkFiles(root, 'trans_cache.json').filter(
    (filePath) => !filePath.includes('.bak'),
  );
  if (candidates.length === 0) {
    throw new Error('trans_cache.json was not found.');
  }
  candidates.sort((a, b) => {
    const aSize = fs.statSync(a).size;
    const bSize = fs.statSync(b).size;
    return bSize - aSize;
  });
  return candidates[0];
}

function textFromCacheKey(key) {
  return key.replace(/_(en2zh|zh2en)$/, '').trim();
}

function cleanTagDisplay(text) {
  let value = text.replace(/\r|\n/g, ' ').replace(/[{}\[\]]/g, ' ').trim();
  value = value.replace(/^\s*[-+]?\d*\.?\d+::/, '');
  value = value.replace(/\s*::\s*$/, '');
  value = value.replace(/\s*:\s*[-+]?\d*\.?\d+\s*$/, '');
  return value.replace(/\s+/g, ' ').trim();
}

function normalizeMatchKey(text) {
  return cleanTagDisplay(text)
    .replace(/[()\[\]{}]+/g, ' ')
    .replace(/_/g, ' ')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

function entryTranslation(value) {
  if (typeof value === 'string') {
    return value;
  }
  if (value && typeof value === 'object') {
    return value.translation || value.text || '';
  }
  return '';
}

function entrySource(value) {
  if (typeof value === 'string') {
    return 'legacy';
  }
  if (value && typeof value === 'object') {
    return String(value.source || 'legacy');
  }
  return 'legacy';
}

function shouldPreserveManual(value) {
  return entrySource(value).toLowerCase().includes('manual');
}

function shouldPreserveManualClassification(value) {
  return String(value?.source || '').toLowerCase().includes('manual');
}

function loadProgress(progressPath) {
  if (!fs.existsSync(progressPath)) {
    return { results: {} };
  }
  const progress = readJson(progressPath);
  return {
    results: progress.results || {},
  };
}

function backupFile(filePath, stamp) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const backupPath = `${filePath}.${stamp}.bak`;
  fs.copyFileSync(filePath, backupPath);
  return backupPath;
}

function categoryOrOther(value) {
  return ALLOWED_CATEGORIES.has(value) ? value : 'other';
}

function parseModelJson(text) {
  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error('Model response was not JSON.');
    }
    return JSON.parse(match[0]);
  }
}

async function callModel(settings, batch) {
  const endpoint = `${String(settings.ai_url).replace(/\/+$/, '')}/chat/completions`;
  const payload = {
    model: MODEL,
    messages: [
      {
        role: 'system',
        content: [
          'You refine an AI art prompt tag cache.',
          'Return strict JSON only: {"items":[{"id":"...","translation":"...","category":"..."}]}.',
          'Translate each tag into concise Simplified Chinese for display in a prompt/tag tool.',
          'Use known official Chinese names for game/anime character tags when possible.',
          'If a tag is a named character, including forms like "wakamo blue archive" or "firefly (honkai: star rail)", category must be character.',
          'If a tag starts with artist: or is clearly an artist name, use artist.',
          'If an unprefixed tag is a bare artist alias used in an artist chain, such as "eonsang", "freng", "ratatatat74", or "null (nyanpyoun)", use artist.',
          'Treat "official style", "official art", and close variants as artist-chain style tags, so category must be artist.',
          'Use neutral terminology for adult, anatomy, defect, and negative prompt terms.',
          `Allowed categories: ${Array.from(ALLOWED_CATEGORIES).join(', ')}.`,
          'Do not add explanations, markdown, or extra keys.',
        ].join(' '),
      },
      {
        role: 'user',
        content: JSON.stringify({
          items: batch.map((item) => ({
            id: item.id,
            tag: item.text,
            cleanedTag: item.cleanedText,
            currentTranslation: item.currentTranslation,
            currentCategory: item.currentCategory,
          })),
        }),
      },
    ],
    temperature: 0,
    response_format: { type: 'json_object' },
    max_tokens: 12000,
  };

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${settings.ai_key}`,
    },
    body: JSON.stringify(payload),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${body.slice(0, 300)}`);
  }
  const decoded = parseModelJson(body);
  const content = decoded.choices?.[0]?.message?.content;
  if (typeof content !== 'string') {
    throw new Error('Model response missing choices[0].message.content.');
  }
  const result = parseModelJson(content);
  if (!Array.isArray(result.items)) {
    throw new Error('Model JSON missing items array.');
  }
  return result.items;
}

async function refineBatch(settings, batch) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const items = await callModel(settings, batch);
      const byId = new Map(items.map((item) => [String(item.id), item]));
      return batch.map((source) => {
        const refined = byId.get(source.id);
        if (!refined) {
          throw new Error(`Model omitted id ${source.id}`);
        }
        const translation = String(refined.translation || '').trim();
        return {
          translation: translation || source.currentTranslation || source.cleanedText,
          category: categoryOrOther(String(refined.category || 'other')),
        };
      });
    } catch (error) {
      lastError = error;
      if (/sensitive words/i.test(String(error))) {
        break;
      }
      console.log(
        `[retry] batch ${batch[0]?.index ?? '?'} attempt ${attempt} failed: ${String(error).slice(0, 220)}`,
      );
      await new Promise((resolve) => setTimeout(resolve, attempt * 2500));
    }
  }
  if (batch.length > 1) {
    const mid = Math.ceil(batch.length / 2);
    console.log(
      `[split] batch ${batch[0]?.index ?? '?'} size=${batch.length} after failure: ${String(lastError).slice(0, 180)}`,
    );
    return [
      ...(await refineBatch(settings, batch.slice(0, mid))),
      ...(await refineBatch(settings, batch.slice(mid))),
    ];
  }
  console.log(
    `[fallback] ${batch[0]?.text ?? '?'} kept local value after failure: ${String(lastError).slice(0, 180)}`,
  );
  return [
    {
      translation: batch[0].currentTranslation || batch[0].cleanedText,
      category: fallbackCategory(batch[0].normalized),
    },
  ];
}

function fallbackCategory(key) {
  if (!key) {
    return 'other';
  }
  if (isMetadataKey(key)) {
    return 'promptSyntax';
  }
  if (isPromptSyntaxKey(key)) {
    return 'promptSyntax';
  }
  if (isOfficialArtistStyleTag(key)) {
    return 'artist';
  }
  if (key.startsWith('artist:') || key.startsWith('artist ')) {
    return 'artist';
  }
  if (/\b\d+\s*(girls?|boys?|others?)\b/.test(key)) {
    return 'character';
  }
  if (/^year\s*\d{4}$/.test(key)) {
    return 'scene';
  }
  if (
    /(lowres|worst|bad quality|jpeg artifacts|blurry|error|bad anatomy|bad hands|extra|missing|finger|censor)/.test(
      key,
    )
  ) {
    return /(anatomy|hands|arms|legs|finger|body)/.test(key)
      ? 'negativeBody'
      : 'negativeQuality';
  }
  if (
    /(blue archive|arknights|honkai|genshin|granblue|princess connect|touhou|azur lane|hololive|nijisanji)/.test(
      key,
    ) &&
    !/^(blue archive|arknights|honkai|genshin impact|granblue fantasy|princess connect|touhou|azur lane|hololive|nijisanji)$/.test(
      key,
    )
  ) {
    return 'character';
  }
  if (/(masterpiece|quality|highres|absurdres|aesthetic)/.test(key)) {
    return 'quality';
  }
  if (/(style|anime|manga|realistic|lighting|shadow|color|cg|3d|monochrome|palette|lineart|sketch|dithering|halftone|screentone|gleaming|100-layer)/.test(key)) {
    return 'style';
  }
  if (/(shirt|blouse|jacket|coat|hoodie|sweater|sleeve|glove|bra|bikini top|top|upper clothes|hood|rope|head wreath|wreath|sticker|tattoo|cage)/.test(key)) {
    return 'upperClothing';
  }
  if (/(skirt|pants|shorts|panties|thighhigh|stocking|sock|shoe|boots|leggings|bottom|lower clothes)/.test(key)) {
    return 'lowerClothing';
  }
  if (/(dress|uniform|kimono|robe|armor|belt|bikini|tanktop|swimsuit|clothes|outfit|costume|choker)/.test(key)) {
    return 'clothing';
  }
  if (/(breast|nipple|arm|hand|wrist|torso|shoulder|areola|neck|collar|necklace|ribbon|hair ornament|hairclip|hair clip|headband|large breasts|small breasts|navel|stomach|body|nude|cleft of venus|cameltoe|cleavage|pubic tattoo|pink tattoo|steaming body|white aura cover body)/.test(key)) {
    return 'upperBody';
  }
  if (/(leg|thigh|feet|foot|barefoot|ass|tail|hip|hips|pussy|testicles|penis|erection|vaginal|anal|stomach bulge)/.test(key)) {
    return 'lowerBody';
  }
  if (/(from above|from below|cowboy shot|close up|close-up|pov|view|looking|solo focus|fisheye|dutch angle|portrait|out of frame|full body|depth of field|x-ray|size difference|look up)/.test(key)) {
    return 'camera';
  }
  if (/(standing|sitting|walking|running|holding|pose|lying|smile|crying|tears|hetero|kiss|hug|grab|spread|kneeling|arms|hands|heavy breathing|breathing|tearing up|tearing|tongue out|seductive|disgust|motion lines|notice lines|sweat|heart|blood|cum|bukkake|paizuri|gangbang|bondage|mind control|defeated|shy|horny|steaming|aura|multiple expressions|hit effect|heavy breath|parted lips|drunk|overflow|penetration|prone bone|mating press|folded|knees to chest|orgasm|tongue|saliva|snot|bdsm|wince|torogao|6 9|half-closed eye|cross-eyed|:d|:o)/.test(key)) {
    return 'action';
  }
  if (/(indoors|outdoors|background|room|street|castle|city|sky|forest|water|bed|day|night|sun|moon|cloud|snow|rain|flower|grass|tree|japanese text|text|sound effects|blank page|negative space|recording|battery indicator|liquid|bacterie|midden|cup|sake|tokkuri|pizza)/.test(key)) {
    return 'scene';
  }
  if (/(hair|eyes|ears|horns|halo|girl|boy|woman|man|loli|mature|face|mouth|nose|skin|animal ears|animal ear fluff|pointy ears|fang|teeth|pupil|eyewear|bald|petite|curvy|muscular|sidelocks|mesugaki|animalization|slim|monster|goblin|interspecies|bestiality|interracial|inflation|eyelashes|sanpaku|wide-eyed)/.test(key)) {
    return 'character';
  }
  return 'other';
}

function isPromptSyntaxKey(key) {
  return /^[\"'.!?。！？…:;=\-+_^\s]+$/.test(key) ||
    /^[-+]?\d+(?:\.\d+)?(?:::)??$/.test(key) ||
    /^character#\d+ at /.test(key) ||
    /^示例角色/.test(key) ||
    /^内容:/.test(key) ||
    /\b(unnamed config|fur dataset)\b/.test(key);
}

function isMetadataKey(key) {
  return (
    /^"?\d+"?\s*:/.test(key) ||
    /^"?(description|stealth pnginfo|base caption|prompt|v4 prompt|char caption|char captions|caption|comment|software|source|cfg|eta|sampler|seed|steps|height|width|scale|uncond scale|n samples|noise schedule|reference strength multiple|uc|hide debug overlay|negative momentum|centers|x|y|r|use coords|use order|controlnet strength|controlnet model|sm|sm dyn|skip cfg above sigma|skip cfg below sigma|lora unet weights|lora clip weights|generation time)"?/.test(
      key,
    ) ||
    /\b(inputs|lora name|safetensors|stealth pnginfo|novelai diffusion|controlnet|reference strength)\b/.test(key)
  );
}

function isOfficialArtistStyleTag(key) {
  return /^(official (style|art|illustration)|official style illustration|official art style)$/.test(
    key,
  );
}

function isArtistPrefixed(text) {
  return /^\s*artist\s*:/.test(cleanTagDisplay(text).toLowerCase());
}

function normalizeArtistAlias(text) {
  let value = cleanTagDisplay(text).replace(/^\s*artist\s*:\s*/i, '');
  value = value.replace(/\s*\(画师\)\s*$/i, '');
  return normalizeMatchKey(value);
}

function isPlausibleArtistAlias(alias) {
  if (!alias || alias.length > 80) {
    return false;
  }
  if (/[,，;；\n\r]|::/.test(alias)) {
    return false;
  }
  return alias.split(/\s+/).filter(Boolean).length <= 6;
}

function addArtistAlias(aliases, text) {
  const alias = normalizeArtistAlias(text);
  if (isPlausibleArtistAlias(alias)) {
    aliases.add(alias);
  }
}

function parseArtistAliasesFromPrompt(prompt) {
  const aliases = [];
  const pattern = /artist\s*:\s*([^,，;；]+?)(?=\s*(?:::|[,，;；]|$))/gi;
  for (const match of prompt.matchAll(pattern)) {
    aliases.push(match[1]);
  }
  return aliases;
}

function collectArtistAliasesFromChain(chain, aliases) {
  if (!chain || typeof chain !== 'object') {
    return;
  }
  if (Array.isArray(chain.artists)) {
    for (const artist of chain.artists) {
      if (typeof artist === 'string') {
        addArtistAlias(aliases, artist);
      } else if (artist?.name) {
        addArtistAlias(aliases, artist.name);
      }
    }
  }
  if (typeof chain.prompt === 'string') {
    for (const alias of parseArtistAliasesFromPrompt(chain.prompt)) {
      addArtistAlias(aliases, alias);
    }
  }
}

function collectArtistAliasesFromJson(value, aliases) {
  if (Array.isArray(value)) {
    for (const entry of value) {
      collectArtistAliasesFromChain(entry, aliases);
    }
    return;
  }
  if (value && typeof value === 'object') {
    if (Array.isArray(value.artistChains)) {
      for (const entry of value.artistChains) {
        collectArtistAliasesFromChain(entry, aliases);
      }
    }
  }
}

function buildKnownArtistAliases(entries, progress) {
  const aliases = new Set();
  for (const filePath of ARTIST_CHAIN_PATHS) {
    if (!filePath || !fs.existsSync(filePath)) {
      continue;
    }
    try {
      collectArtistAliasesFromJson(readJson(filePath), aliases);
    } catch {
      // Artist-chain evidence is helpful but should not block cache repair.
    }
  }
  for (const entry of entries) {
    if (isArtistPrefixed(entry.cleanedText)) {
      addArtistAlias(aliases, entry.cleanedText);
    }
    const refined = progress.results?.[entry.key];
    if (refined?.category === 'artist') {
      addArtistAlias(aliases, entry.cleanedText);
    }
  }
  return aliases;
}

function categoryForEntry(entry, refined, knownArtistAliases) {
  const existing = entry.classEntry;
  if (shouldPreserveManualClassification(existing)) {
    return categoryOrOther(existing.category);
  }
  if (isOfficialArtistStyleTag(entry.normalized)) {
    return 'artist';
  }
  if (isArtistPrefixed(entry.cleanedText)) {
    return 'artist';
  }
  if (knownArtistAliases.has(normalizeArtistAlias(entry.cleanedText))) {
    return 'artist';
  }
  const refinedCategory = categoryOrOther(refined.category);
  const fallback = fallbackCategory(entry.normalized);
  if (refinedCategory === 'other' && fallback !== 'other') {
    return fallback;
  }
  if (
    entry.currentCategory === 'other' &&
    fallback !== 'other' &&
    refinedCategory === entry.currentCategory
  ) {
    return fallback;
  }
  return refinedCategory;
}

function buildExistingClassifications(paths) {
  const merged = {};
  for (const filePath of paths) {
    if (!fs.existsSync(filePath)) {
      continue;
    }
    try {
      Object.assign(merged, readJson(filePath));
    } catch {
      // Keep going; malformed caches should not block translation repair.
    }
  }
  return merged;
}

async function main() {
  const settings = findSettings(ROOT);
  const translationPath = findTranslationCache(ROOT);
  const translationDir = path.dirname(translationPath);
  const realClassificationPath = path.join(
    translationDir,
    'tag_classification_cache.json',
  );
  const discoveredClassificationPaths = walkFiles(
    ROOT,
    'tag_classification_cache.json',
  );
  const classificationPaths = Array.from(
    new Set([realClassificationPath, ...discoveredClassificationPaths]),
  );
  const progressPath = path.join(
    translationDir,
    'cache_refine_5_4_mini_progress.json',
  );
  const translationCache = readJson(translationPath);
  const classificationCache = buildExistingClassifications(classificationPaths);
  const entries = Object.entries(translationCache).map(([key, value], index) => {
    const text = textFromCacheKey(key);
    const cleanedText = cleanTagDisplay(text);
    const normalized = normalizeMatchKey(cleanedText);
    const classEntry =
      classificationCache[`positive:${normalized}`] || classificationCache[normalized];
    return {
      id: String(index),
      index,
      key,
      value,
      text,
      cleanedText,
      normalized,
      currentTranslation: entryTranslation(value),
      currentCategory: classEntry?.category || '',
      classEntry,
      preserveManual: shouldPreserveManual(value),
    };
  });
  const selectedEntries = MAX_ITEMS > 0 ? entries.slice(0, MAX_ITEMS) : entries;
  const progress = loadProgress(progressPath);
  const pending = selectedEntries.filter((entry) => !progress.results[entry.key]);

  console.log(
    `[start] model=${MODEL} translation=${translationPath} entries=${entries.length} selected=${selectedEntries.length} pending=${pending.length} dryRun=${DRY_RUN} allowModelCalls=${ALLOW_MODEL_CALLS}`,
  );

  if (pending.length > 0 && !ALLOW_MODEL_CALLS) {
    console.log(
      `[offline] skipped ${pending.length} pending items; set REFINE_ALLOW_MODEL_CALLS=1 to call ${MODEL}`,
    );
  } else {
    for (let offset = 0; offset < pending.length; offset += BATCH_SIZE) {
      const batch = pending.slice(offset, offset + BATCH_SIZE);
      const refined = await refineBatch(settings, batch);
      for (let i = 0; i < batch.length; i += 1) {
        progress.results[batch[i].key] = refined[i];
      }
      writeJson(progressPath, {
        model: MODEL,
        updatedAt: new Date().toISOString(),
        total: selectedEntries.length,
        results: progress.results,
      });
      console.log(
        `[progress] ${Math.min(offset + batch.length, pending.length)}/${pending.length} pending processed; total results=${Object.keys(progress.results).length}`,
      );
    }
  }

  if (DRY_RUN) {
    const knownArtistAliases = buildKnownArtistAliases(selectedEntries, progress);
    const preview = selectedEntries.slice(0, 10).map((entry) => ({
      tag: entry.text,
      before: entry.currentTranslation,
      after: progress.results[entry.key],
      finalCategory: progress.results[entry.key]
        ? categoryForEntry(entry, progress.results[entry.key], knownArtistAliases)
        : '',
    }));
    console.log(
      JSON.stringify({ artistAliases: knownArtistAliases.size, preview }, null, 2),
    );
    return;
  }

  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\..+$/, '')
    .replace('T', '-');
  const backups = [
    backupFile(translationPath, stamp),
    ...classificationPaths.map((filePath) => backupFile(filePath, stamp)),
  ].filter(Boolean);

  let translated = 0;
  let manualPreserved = 0;
  let artistOverrides = 0;
  const knownArtistAliases = buildKnownArtistAliases(selectedEntries, progress);
  const now = Math.floor(Date.now() / 1000);
  for (const entry of selectedEntries) {
    const refined = progress.results[entry.key];
    if (!refined) {
      continue;
    }
    if (entry.preserveManual) {
      manualPreserved += 1;
    } else {
      translationCache[entry.key] = {
        translation: String(refined.translation || entry.currentTranslation || '').trim(),
        source: SOURCE,
        ts: now,
      };
      translated += 1;
    }
    if (entry.normalized) {
      const rawCategory = categoryOrOther(refined.category);
      const category = categoryForEntry(entry, refined, knownArtistAliases);
      if (category === 'artist' && rawCategory !== 'artist') {
        artistOverrides += 1;
      }
      classificationCache[`positive:${entry.normalized}`] = {
        category,
        source: SOURCE,
        updatedAt: now,
      };
      if (category.startsWith('negative')) {
        classificationCache[`negative:${entry.normalized}`] = {
          category,
          source: SOURCE,
          updatedAt: now,
        };
      }
    }
  }
  const localClassificationRepairs = repairOtherClassificationsByLocalRules(
    classificationCache,
    now,
  );

  writeJson(translationPath, translationCache);
  for (const filePath of classificationPaths) {
    writeJson(filePath, classificationCache);
  }
  console.log(
    `[done] translated=${translated} manualPreserved=${manualPreserved} artistOverrides=${artistOverrides} localClassificationRepairs=${localClassificationRepairs} artistAliases=${knownArtistAliases.size} classifications=${Object.keys(classificationCache).length} backups=${backups.join(' | ')}`,
  );
}

function repairOtherClassificationsByLocalRules(classificationCache, now) {
  let repaired = 0;
  for (const [key, entry] of Object.entries(classificationCache)) {
    if (!key.startsWith('positive:')) {
      continue;
    }
    if (shouldPreserveManualClassification(entry)) {
      continue;
    }
    if (entry?.category !== 'other') {
      continue;
    }
    const normalized = key.replace(/^positive:/, '');
    const category = fallbackCategory(normalized);
    if (category === 'other') {
      continue;
    }
    classificationCache[key] = {
      category,
      source: 'local-rules-refine',
      updatedAt: now,
    };
    repaired += 1;
  }
  return repaired;
}

main().catch((error) => {
  console.error(`[fatal] ${error?.stack || error}`);
  process.exit(1);
});
