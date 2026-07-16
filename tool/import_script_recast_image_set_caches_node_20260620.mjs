import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const containerKeys = new Set([
  'Comment',
  'Description',
  'fullContent',
  'Stealth_PNGInfo',
  'parameters',
  'Source',
  'workflow',
]);

const structuredKeys = new Set([
  'Prompt',
  'prompt',
  'parameters',
  'width',
  'Width',
  'height',
  'Height',
  'resolution',
  'Resolution',
  'v4_prompt',
  'v4_negative_prompt',
  'char_captions',
  'coords',
  'steps',
  'seed',
  'scale',
  'sampler',
  'uc',
  'negative_prompt',
]);

const args = parseArgs(process.argv.slice(2));
if (!args.sourceRoot) {
  throw new Error('Pass --source-root <directory>.');
}
if (!args.workspace) {
  args.workspace =
    'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio';
}

const sourceRoot = path.resolve(args.sourceRoot);
const cacheDir = path.join(path.resolve(args.workspace), 'script_recast', 'cache');
const reportPath = args.report ? path.resolve(args.report) : '';
const rows = [];

if (!fs.existsSync(sourceRoot)) {
  throw new Error(`Missing source root: ${sourceRoot}`);
}
if (!fs.existsSync(cacheDir)) {
  throw new Error(`Missing cache dir: ${cacheDir}`);
}

const directories = candidateDirectories(sourceRoot, args.recursive);
for (const directory of directories) {
  try {
    const script = parseDirectory(directory);
    if (script.frames.length === 0) {
      rows.push({
        status: 'skipped_no_frames',
        script_id: script.id,
        script_name: script.name,
        source_root_path: directory,
        frame_count: 0,
      });
      continue;
    }
    const cache = cacheForScript(script);
    const fileName = `${safeWorkspaceEntityId('script', cache.scriptId)}.json`;
    if (args.apply) {
      fs.mkdirSync(cacheDir, { recursive: true });
      fs.writeFileSync(
        path.join(cacheDir, fileName),
        `${JSON.stringify(cache, null, 2)}\n`,
        'utf8',
      );
    }
    rows.push({
      status: args.apply ? 'written' : 'would_write',
      script_id: cache.scriptId,
      script_name: cache.scriptName,
      source_root_path: cache.sourceRootPath,
      frame_count: script.frames.length,
      cache_file_name: fileName,
    });
  } catch (error) {
    rows.push({
      status: 'error',
      script_name: path.basename(directory),
      source_root_path: directory,
      frame_count: 0,
      message: String(error?.stack || error),
    });
  }
}

const report = {
  source_root: sourceRoot,
  cache_dir: cacheDir,
  dry_run: !args.apply,
  written: rows.filter((row) => row.status === 'written').length,
  would_write: rows.filter((row) => row.status === 'would_write').length,
  skipped: rows.filter((row) => row.status.startsWith('skipped')).length,
  errors: rows.filter((row) => row.status === 'error').length,
  rows,
};

if (reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
console.log(JSON.stringify(report, null, 2));
if (report.errors > 0) {
  process.exitCode = 1;
}

function parseArgs(values) {
  const parsed = {
    sourceRoot: '',
    workspace: '',
    recursive: false,
    apply: false,
    debug: false,
    report: '',
  };
  for (let index = 0; index < values.length; index += 1) {
    const arg = values[index];
    if (!arg.startsWith('--')) continue;
    const key = arg.slice(2);
    if (key === 'recursive') {
      parsed.recursive = true;
      continue;
    }
    if (key === 'apply') {
      parsed.apply = true;
      continue;
    }
    if (key === 'debug') {
      parsed.debug = true;
      continue;
    }
    const value = values[index + 1];
    index += 1;
    if (key === 'source-root') parsed.sourceRoot = value;
    if (key === 'workspace') parsed.workspace = value;
    if (key === 'report') parsed.report = value;
  }
  return parsed;
}

function candidateDirectories(root, recursive) {
  const result = [];
  if (hasFrameSourceFiles(root)) result.push(root);
  if (recursive) {
    for (const directory of walkDirectories(root)) {
      if (hasFrameSourceFiles(directory)) result.push(directory);
    }
  }
  return result.sort(naturalCompare);
}

function* walkDirectories(root) {
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const current = path.join(root, entry.name);
    yield current;
    yield* walkDirectories(current);
  }
}

function hasFrameSourceFiles(directory) {
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .some(
      (entry) =>
        entry.isFile() &&
        (imageMetadataFileName(entry.name) ||
          frameJsonName(entry.name)),
    );
}

function parseDirectory(directory) {
  const sources = frameSources(directory);
  const frames = [];
  for (const source of sources) {
    const frame = parseFrameSource(source, frames.length + 1);
    if (frame) frames.push(frame);
  }
  const script = {
    id: scriptIdForDirectory(directory),
    name: path.basename(directory),
    rootPath: directory,
    frames,
    detectedSchema: voteSchema(frames),
    parseWarnings:
      frames.length === 0
        ? ['No prompt-bearing JSON or PNG script frames found in this directory.']
        : frames.flatMap((frame) => frame.warnings ?? []),
    meta: { frameCount: frames.length },
  };
  return script;
}

function frameSources(directory) {
  const jsonFiles = [];
  const pngFiles = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const full = path.join(directory, entry.name);
    if (frameJsonName(entry.name)) jsonFiles.push(full);
    if (imageMetadataFileName(entry.name)) pngFiles.push(full);
  }
  jsonFiles.sort((left, right) => naturalCompare(path.basename(left), path.basename(right)));
  pngFiles.sort((left, right) => naturalCompare(path.basename(left), path.basename(right)));
  if (shouldUsePngMetadataAsPrimary(jsonFiles, pngFiles)) {
    return pngFiles.map((file) => ({ file, kind: 'png', sourceImagePath: file }));
  }
  if (jsonFiles.length === 0) {
    return pngFiles.map((file) => ({ file, kind: 'png', sourceImagePath: file }));
  }
  const usedPng = new Set();
  const paired = [];
  for (const json of jsonFiles) {
    const jsonStem = sourceStem(path.basename(json));
    const png = pngFiles.find(
      (candidate) => !usedPng.has(candidate) && sourceStem(path.basename(candidate)) === jsonStem,
    );
    if (png) usedPng.add(png);
    paired.push({ file: json, kind: 'json', sourceImagePath: png || '' });
  }
  for (const png of pngFiles) {
    if (!usedPng.has(png)) paired.push({ file: png, kind: 'png', sourceImagePath: png });
  }
  return paired.sort((left, right) =>
    naturalCompare(path.basename(left.file), path.basename(right.file)),
  );
}

function parseFrameSource(source, index) {
  try {
    if (source.kind === 'json') {
      const rawJson = fs.readFileSync(source.file, 'utf8');
      const decoded = JSON.parse(rawJson);
      if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return null;
      const metadata = parseMetadata(decoded);
      if (!hasPromptMetadata(metadata)) return null;
      return frameFromMetadata(source, index, rawJson, decoded, metadata);
    }
    for (const payload of imageMetadataPayloads(source.file)) {
      const metadata = parseMetadata(payload);
      if (!hasPromptMetadata(metadata)) continue;
      const sourcePayload = sourcePayloadFromMetadata(metadata);
      const rawContent = metadata.rawContent || JSON.stringify(sourcePayload);
      return frameFromMetadata(source, index, rawContent, sourcePayload, metadata);
    }
    return null;
  } catch (error) {
    if (args.debug) {
      console.error(`Could not parse frame source: ${source.file}`);
      console.error(String(error?.stack || error));
    }
    return null;
  }
}

function parseMetadata(payload) {
  const merged = {};
  mergeIfStructured(merged, payload);
  absorb(payload.Comment, merged);
  absorb(payload.fullContent, merged);
  absorb(payload.Stealth_PNGInfo, merged);
  const prompt =
    firstString([
      payload.Description,
      payload.prompt,
      payload.Prompt,
      merged.Description,
      merged.prompt,
      merged.Prompt,
      v4BaseCaption(merged, 'v4_prompt'),
    ]) || '';
  const negativePrompt =
    firstString([
      payload.negative_prompt,
      payload.uc,
      merged.negative_prompt,
      merged.uc,
      v4BaseCaption(merged, 'v4_negative_prompt'),
    ]) || '';
  const width = firstInt([payload.width, payload.Width, merged.width, merged.Width]);
  const height = firstInt([payload.height, payload.Height, merged.height, merged.Height]);
  return {
    prompt,
    source: firstString([payload.Source, payload.source, merged.Source, merged.source]) || '',
    negativePrompt,
    rawContent: rawContentFor(payload),
    parameters: merged,
    width,
    height,
    charCaptions: extractCharCaptions(merged, 'v4_prompt'),
    negativeCharCaptions: extractCharCaptions(merged, 'v4_negative_prompt'),
    coords: extractCoords(merged),
  };
}

function absorb(value, merged) {
  if (value == null) return;
  const decoded = decodePayload(value);
  if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
    mergeIfStructured(merged, decoded);
    absorb(decoded.Comment, merged);
    absorb(decoded.Description, merged);
    absorb(decoded.fullContent, merged);
    absorb(decoded.Stealth_PNGInfo, merged);
  }
}

function mergeIfStructured(target, source) {
  if (!Object.keys(source).some((key) => structuredKeys.has(key))) return;
  for (const [key, value] of Object.entries(source)) {
    if (key === 'parameters' && value && typeof value === 'object' && !Array.isArray(value)) {
      Object.assign(target, value);
      continue;
    }
    if (containerKeys.has(key)) continue;
    if (value != null) target[key] = value;
  }
}

function decodePayload(value) {
  if (typeof value !== 'string') return value;
  const trimmed = value.trim();
  if (!trimmed || !/^[{["]/.test(trimmed)) return value;
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function rawContentFor(payload) {
  const parts = [];
  for (const key of ['Description', 'Comment', 'fullContent', 'Stealth_PNGInfo']) {
    if (payload[key] != null && String(payload[key]).trim()) parts.push(String(payload[key]));
  }
  return parts.length ? parts.join('\n') : JSON.stringify(payload);
}

function v4Caption(parameters, key) {
  const value = parameters[key];
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const caption = value.caption;
  if (!caption || typeof caption !== 'object' || Array.isArray(caption)) return null;
  return caption;
}

function v4BaseCaption(parameters, key) {
  const caption = v4Caption(parameters, key);
  if (!caption) return '';
  return firstString([caption.base_caption, caption.baseCaption, caption.prompt, caption.caption]) || '';
}

function extractCharCaptions(parameters, key) {
  return charCaptionEntries(parameters, key)
    .map((entry) => firstString([entry.char_caption, entry.caption, entry.prompt, entry.base_caption]))
    .filter(Boolean);
}

function charCaptionEntries(parameters, key) {
  const caption = v4Caption(parameters, key);
  const entries =
    key === 'v4_prompt'
      ? caption?.char_captions ?? parameters.char_captions
      : caption?.char_captions ?? parameters.negative_char_captions;
  if (!Array.isArray(entries)) return [];
  return entries.filter((entry) => entry && typeof entry === 'object' && !Array.isArray(entry));
}

function extractCoords(parameters) {
  const coords = [];
  addCoords(coords, parameters.coords);
  for (const entry of charCaptionEntries(parameters, 'v4_prompt')) {
    addCoords(coords, entry.coords);
    addCoords(coords, entry.centers);
    addCoords(coords, entry.center);
  }
  return coords;
}

function addCoords(target, value) {
  if (Array.isArray(value)) {
    for (const item of value) addCoords(target, item);
    return;
  }
  if (!value || typeof value !== 'object') return;
  const x = numberOrNull(value.x);
  const y = numberOrNull(value.y);
  if (x != null && y != null) target.push({ x, y });
}

function frameFromMetadata(source, index, rawContent, sourcePayload, metadata) {
  const parsed = {
    baseCaption: metadata.prompt || '',
    charCaptions: metadata.charCaptions,
    negativeBase: metadata.negativePrompt || '',
    negativeCharCaptions: metadata.negativeCharCaptions,
    coords: metadata.coords,
    generationParams: stableJsonValue(metadata.parameters),
    sourcePayload: stableJsonValue(sourcePayload),
  };
  return {
    index,
    fileName: path.basename(source.file),
    sourcePath: source.file,
    ...(source.sourceImagePath ? { sourceImagePath: source.sourceImagePath } : {}),
    rawJson: rawContent,
    parsed,
    detectedSchema: detectFrameSchema(parsed),
    parseStatus: 'parsed',
    warnings: [],
  };
}

function cacheForScript(script) {
  return {
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: sourceFingerprint(script),
    updatedAt: new Date().toISOString(),
    mapping: {
      id: `mapping-${script.id}`,
      scriptId: script.id,
      roleSwaps: [],
      artistSwap: null,
    },
    scriptSnapshot: stableJsonValue(script),
  };
}

function extractPngTextChunks(buffer) {
  const result = {};
  let offset = 8;
  while (offset + 8 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'tEXt') {
      const separator = data.indexOf(0);
      if (separator > 0) {
        result[data.subarray(0, separator).toString('utf8')] = data
          .subarray(separator + 1)
          .toString('utf8');
      }
    } else if (type === 'zTXt') {
      const separator = data.indexOf(0);
      if (separator > 0 && data[separator + 1] === 0) {
        result[data.subarray(0, separator).toString('utf8')] = zlib
          .inflateSync(data.subarray(separator + 2))
          .toString('utf8');
      }
    } else if (type === 'iTXt') {
      const entry = parseInternationalTextChunk(data);
      if (entry) result[entry.key] = entry.value;
    }
    offset += 12 + length;
    if (type === 'IEND') break;
  }
  return result;
}

function imageMetadataPayloads(file) {
  const lower = path.basename(file).toLowerCase();
  const buffer = fs.readFileSync(file);
  if (lower.endsWith('.png')) {
    const chunkMetadata = extractPngTextChunks(buffer);
    return Object.keys(chunkMetadata).length === 0 ? [] : [chunkMetadata];
  }
  if (lower.endsWith('.webp')) {
    return extractWebpMetadataPayloads(buffer);
  }
  return [];
}

function extractWebpMetadataPayloads(buffer) {
  if (
    buffer.length < 12 ||
    buffer.toString('ascii', 0, 4) !== 'RIFF' ||
    buffer.toString('ascii', 8, 12) !== 'WEBP'
  ) {
    return [];
  }
  const result = [];
  let offset = 12;
  while (offset + 8 <= buffer.length) {
    const type = buffer.toString('ascii', offset, offset + 4);
    const length = buffer.readUInt32LE(offset + 4);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd > buffer.length) break;
    if (type === 'EXIF' || type === 'XMP ') {
      for (const payload of webpTextPayloads(buffer.subarray(dataStart, dataEnd))) {
        result.push(payload);
      }
    }
    offset = dataEnd + (length % 2);
  }
  return result;
}

function webpTextPayloads(data) {
  const text = data.toString('utf8').trim();
  if (!text) return [];
  const result = [];
  const direct = decodePayload(text);
  if (direct && typeof direct === 'object' && !Array.isArray(direct)) {
    result.push(direct);
  }
  const embedded = embeddedJsonObject(text);
  if (embedded) result.push(embedded);
  return result;
}

function embeddedJsonObject(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  const decoded = decodePayload(text.slice(start, end + 1));
  return decoded && typeof decoded === 'object' && !Array.isArray(decoded) ? decoded : null;
}

function parseInternationalTextChunk(data) {
  const keywordEnd = data.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 5 > data.length) return null;
  const key = data.subarray(0, keywordEnd).toString('utf8');
  let cursor = keywordEnd + 1;
  const compressionFlag = data[cursor++];
  const compressionMethod = data[cursor++];
  if (compressionFlag !== 0 && compressionMethod !== 0) return null;
  const languageEnd = data.indexOf(0, cursor);
  if (languageEnd < 0) return null;
  cursor = languageEnd + 1;
  const translatedEnd = data.indexOf(0, cursor);
  if (translatedEnd < 0) return null;
  cursor = translatedEnd + 1;
  const bytes = data.subarray(cursor);
  return {
    key,
    value: (compressionFlag === 0 ? bytes : zlib.inflateSync(bytes)).toString('utf8'),
  };
}

function sourcePayloadFromMetadata(metadata) {
  const payload = {};
  if (metadata.prompt?.trim()) payload.Description = metadata.prompt;
  if (metadata.source?.trim()) payload.Source = metadata.source;
  const comment = { ...metadata.parameters };
  if (metadata.negativePrompt?.trim()) comment.uc ??= metadata.negativePrompt;
  if (Object.keys(comment).length > 0) payload.Comment = comment;
  if (metadata.width != null) payload.width = metadata.width;
  if (metadata.height != null) payload.height = metadata.height;
  return payload;
}

function hasPromptMetadata(metadata) {
  return Boolean(
    metadata.prompt?.trim() ||
      metadata.charCaptions.some((caption) => String(caption).trim()),
  );
}

function detectFrameSchema(parsed) {
  if (parsed.charCaptions.length > 0) {
    const base = parsed.baseCaption.toLowerCase();
    const hasInlineCharacter = parsed.charCaptions.some((caption) => {
      const anchor = String(caption).split(',')[0].trim().toLowerCase();
      return anchor && base.includes(anchor);
    });
    return hasInlineCharacter ? 'v4Partial' : 'v4Slotted';
  }
  return parsed.baseCaption.trim() ? 'baseInline' : 'unknown';
}

function voteSchema(frames) {
  const votes = new Map([
    ['v4Partial', 0],
    ['v4Slotted', 0],
    ['baseInline', 0],
    ['unknown', 0],
  ]);
  for (const frame of frames) {
    if (frame.parseStatus === 'parsed') {
      votes.set(frame.detectedSchema, (votes.get(frame.detectedSchema) ?? 0) + 1);
    }
  }
  return [...votes.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? 'unknown';
}

function shouldUsePngMetadataAsPrimary(jsonFiles, pngFiles) {
  if (jsonFiles.length === 0 || pngFiles.length === 0) return false;
  if (jsonFiles.length !== pngFiles.length) return true;
  const jsonStems = new Set(jsonFiles.map((file) => sourceStem(path.basename(file))));
  const pngStems = new Set(pngFiles.map((file) => sourceStem(path.basename(file))));
  if (jsonStems.size !== jsonFiles.length || pngStems.size !== pngFiles.length) return true;
  return (
    [...jsonStems].some((stem) => !pngStems.has(stem)) ||
    [...pngStems].some((stem) => !jsonStems.has(stem))
  );
}

function sourceFingerprint(script) {
  return [
    script.id,
    normalizeScriptPath(script.rootPath),
    ...script.frames.map(
      (frame) =>
        `${frame.index}:${frame.fileName}:${normalizeScriptPath(frame.sourcePath)}:${stableContentHash(
          frame.rawJson,
        )}`,
    ),
  ].join('|');
}

function scriptIdForDirectory(directory) {
  const normalizedPath = normalizeScriptIdPath(path.resolve(directory));
  const parts = normalizedPath.split('/').filter(Boolean);
  const label = parts.at(-1) || 'script';
  return stableIdFromText('script', normalizedPath, label);
}

function safeWorkspaceEntityId(prefix, id) {
  const trimmed = String(id).trim();
  if (/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(trimmed)) return trimmed;
  return stableIdFromText(prefix, trimmed);
}

function stableIdFromText(prefix, text, label = text) {
  const slug = asciiSlug(label);
  const hash = stableTextFingerprint(text);
  return slug ? `${prefix}-${slug}-${hash}` : `${prefix}-${hash}`;
}

function stableTextFingerprint(text) {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const mask = 0xffffffffffffffffn;
  for (const byte of Buffer.from(text, 'utf8')) {
    hash ^= BigInt(byte);
    hash = (hash * prime) & mask;
  }
  return hash.toString(16).padStart(16, '0');
}

function stableContentHash(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

function asciiSlug(value) {
  let output = '';
  let previousDash = false;
  for (const char of String(value).toLowerCase()) {
    if (/[a-z0-9]/.test(char)) {
      output += char;
      previousDash = false;
    } else if (!previousDash && output) {
      output += '-';
      previousDash = true;
    }
  }
  output = output.replace(/-+$/, '');
  return output.length <= 48 ? output : output.slice(0, 48).replace(/-+$/, '');
}

function normalizeScriptPath(value) {
  const normalized = String(value).replaceAll('\\', '/');
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function normalizeScriptIdPath(value) {
  return String(value).replaceAll('\\', '/');
}

function frameJsonName(name) {
  const lower = name.toLowerCase();
  return lower.endsWith('.json') && lower !== '.aitag-download-task.json';
}

function imageMetadataFileName(name) {
  const lower = name.toLowerCase();
  return lower.endsWith('.png') || lower.endsWith('.webp');
}

function sourceStem(fileName) {
  return fileName.replace(/\.[^.]+$/, '').toLowerCase();
}

function naturalCompare(left, right) {
  return String(left).localeCompare(String(right), undefined, {
    numeric: true,
    sensitivity: 'base',
  });
}

function firstString(values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value;
  }
  return '';
}

function firstInt(values) {
  for (const value of values) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function stableJsonValue(value) {
  if (Array.isArray(value)) return value.map(stableJsonValue);
  if (value && typeof value === 'object') {
    const result = {};
    for (const key of Object.keys(value).sort()) {
      result[key] = stableJsonValue(value[key]);
    }
    return result;
  }
  return value;
}
