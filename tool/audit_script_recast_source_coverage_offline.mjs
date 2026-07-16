import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const toolName = 'audit_script_recast_source_coverage_offline';
const imageExtensions = new Set(['.png', '.jpg', '.jpeg', '.webp']);
const pngTextChunkOrder = ['tEXt', 'zTXt', 'iTXt'];

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

let options;
try {
  options = parseArgs(process.argv.slice(2));
} catch (error) {
  console.error(errorMessage(error));
  process.exitCode = 1;
}

if (options) {
  run(options);
}

function run(parsedOptions) {
  const cacheDir = path.resolve(parsedOptions.cacheDir);
  const sourceRoot = path.resolve(parsedOptions.sourceRoot);
  const reportPath = path.resolve(parsedOptions.reportPath);
  const report = emptyReport(cacheDir, sourceRoot);
  let reportPathIsSafe = false;

  try {
    assertSafeReportPath(reportPath, cacheDir, sourceRoot);
    reportPathIsSafe = true;
    assertDirectory(cacheDir, 'Cache directory');
    assertDirectory(sourceRoot, 'Source root');
    auditCoverage(report, cacheDir, sourceRoot);
  } catch (error) {
    report.errors.push({
      scope: 'audit',
      message: errorMessage(error),
    });
  }

  report.errors.sort(compareErrorRows);
  report.summary.audit_error_count = report.errors.length;
  finalizeCoverageReview(report);

  if (reportPathIsSafe) {
    try {
      fs.mkdirSync(path.dirname(reportPath), { recursive: true });
      fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    } catch (error) {
      console.error(`Could not write report: ${errorMessage(error)}`);
      process.exitCode = 1;
      return;
    }
  }

  console.log(JSON.stringify(report, null, 2));
  if (!report.source_coverage_reviewed) {
    process.exitCode = 1;
  }
}

function emptyReport(cacheDir, sourceRoot) {
  return {
    tool: toolName,
    schema_version: 1,
    api_used: false,
    read_only: true,
    source_coverage_reviewed: false,
    cache_dir: cacheDir,
    source_root: sourceRoot,
    summary: {
      cache_file_count: 0,
      cache_source_group_count: 0,
      source_directory_count: 0,
      source_image_count: 0,
      frame_image_reference_count: 0,
      existing_frame_image_reference_count: 0,
      unique_existing_frame_image_count: 0,
      missing_cache_directory_count: 0,
      cache_source_issue_count: 0,
      uncached_image_count: 0,
      uncached_png_with_prompt_metadata_count: 0,
      uncached_png_without_prompt_metadata_count: 0,
      uncached_png_metadata_error_count: 0,
      missing_frame_image_count: 0,
      audit_error_count: 0,
    },
    cache_source_groups: [],
    source_directories: [],
    missing_cache_directories: [],
    cache_source_issues: [],
    uncached_images: [],
    uncached_png_with_prompt_metadata: [],
    uncached_png_without_prompt_metadata: [],
    uncached_png_metadata_errors: [],
    missing_frame_images: [],
    uncached_png_without_prompt_metadata_review: {
      status: 'not_reviewed',
      count: 0,
      images: [],
    },
    checks: {
      errors: false,
      missing_cache_directory_count: false,
      cache_source_issue_count: false,
      missing_frame_image_count: false,
      uncached_png_with_prompt_metadata_count: false,
      uncached_png_metadata_error_count: false,
      uncached_png_without_prompt_metadata_reviewed: false,
      source_coverage_reviewed: false,
    },
    violations: [],
    errors: [],
  };
}

function finalizeCoverageReview(report) {
  const hardGates = [
    {
      check: 'errors',
      count: report.errors.length,
      items: report.errors,
    },
    {
      check: 'missing_cache_directory_count',
      count: report.summary.missing_cache_directory_count,
      items: report.missing_cache_directories,
    },
    {
      check: 'cache_source_issue_count',
      count: report.summary.cache_source_issue_count,
      items: report.cache_source_issues,
    },
    {
      check: 'missing_frame_image_count',
      count: report.summary.missing_frame_image_count,
      items: report.missing_frame_images,
    },
    {
      check: 'uncached_png_with_prompt_metadata_count',
      count: report.summary.uncached_png_with_prompt_metadata_count,
      items: report.uncached_png_with_prompt_metadata,
    },
    {
      check: 'uncached_png_metadata_error_count',
      count: report.summary.uncached_png_metadata_error_count,
      items: report.uncached_png_metadata_errors,
    },
  ];
  const noMetadataImages = [...report.uncached_png_without_prompt_metadata];

  report.uncached_png_without_prompt_metadata_review = {
    status: 'reviewed_unrecoverable_without_metadata',
    count: noMetadataImages.length,
    images: noMetadataImages,
  };
  report.checks = Object.fromEntries(
    hardGates.map((gate) => [gate.check, gate.count === 0]),
  );
  report.checks.uncached_png_without_prompt_metadata_reviewed = true;
  report.checks.source_coverage_reviewed = hardGates.every(
    (gate) => gate.count === 0,
  );
  report.violations = hardGates
    .filter((gate) => gate.count !== 0)
    .map((gate) => ({
      check: gate.check,
      requirement: 'must_be_zero',
      count: gate.count,
      items: gate.items,
    }));
  report.source_coverage_reviewed = report.checks.source_coverage_reviewed;
}

function auditCoverage(report, cacheDir, sourceRoot) {
  const sourceDirectories = collectSourceDirectories(sourceRoot);
  const sourceDirectoryByKey = new Map(
    sourceDirectories.map((directory) => [
      canonicalPathKey(directory.sourceRootPath),
      directory,
    ]),
  );
  const cacheFiles = collectFilesRecursively(cacheDir, (filePath) =>
    filePath.toLowerCase().endsWith('.json'),
  );
  const cacheGroups = new Map();
  const referencedImageKeys = new Set();
  const existingReferencedImageKeys = new Set();
  const missingFrameImages = [];
  let frameImageReferenceCount = 0;
  let existingFrameImageReferenceCount = 0;

  for (const cachePath of cacheFiles) {
    const cacheFile = portableRelative(cacheDir, cachePath);
    let cache;
    try {
      cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
      if (!cache || typeof cache !== 'object' || Array.isArray(cache)) {
        throw new Error('The cache root must be a JSON object.');
      }
    } catch (error) {
      report.errors.push({
        scope: 'cache_parse',
        cache_file: cacheFile,
        message: errorMessage(error),
      });
      continue;
    }

    const sourceRootPath = stringValue(cache.sourceRootPath).trim();
    if (!sourceRootPath) {
      report.errors.push({
        scope: 'cache_schema',
        cache_file: cacheFile,
        message: 'cache.sourceRootPath must be a non-empty string.',
      });
      continue;
    }

    const resolvedSourceRoot = path.resolve(sourceRootPath);
    const groupKey = canonicalPathKey(resolvedSourceRoot);
    let group = cacheGroups.get(groupKey);
    if (!group) {
      group = {
        key: groupKey,
        sourcePaths: new Set(),
        cacheFiles: [],
      };
      cacheGroups.set(groupKey, group);
    }
    group.sourcePaths.add(resolvedSourceRoot);
    group.cacheFiles.push(cacheFile);

    const frames = Array.isArray(cache.scriptSnapshot?.frames)
      ? cache.scriptSnapshot.frames
      : [];
    for (let frameOffset = 0; frameOffset < frames.length; frameOffset += 1) {
      const frame = frames[frameOffset];
      if (!frame || typeof frame !== 'object' || Array.isArray(frame)) continue;
      const reference = frameImageReference(frame, resolvedSourceRoot);
      if (!reference) continue;
      frameImageReferenceCount += 1;
      const imageKey = canonicalPathKey(reference.imagePath);
      referencedImageKeys.add(imageKey);
      if (isFile(reference.imagePath)) {
        existingFrameImageReferenceCount += 1;
        existingReferencedImageKeys.add(imageKey);
        continue;
      }
      missingFrameImages.push({
        cache_file: cacheFile,
        frame_index: normalizedFrameIndex(frame.index, frameOffset),
        frame_file_name: stringValue(frame.fileName ?? frame.file_name),
        image_reference_field: reference.field,
        image_path: reference.imagePath,
      });
    }
  }

  const cacheGroupRows = [...cacheGroups.values()]
    .map((group) => cacheGroupRow(group, sourceDirectoryByKey))
    .sort((left, right) => compareText(left.source_root_path, right.source_root_path));

  const sourceDirectoryRows = [];
  const uncachedImages = [];
  for (const directory of sourceDirectories) {
    const group = cacheGroups.get(canonicalPathKey(directory.sourceRootPath));
    const cacheFilesForDirectory = group
      ? [...group.cacheFiles].sort(compareText)
      : [];
    const uncachedForDirectory = directory.images.filter(
      (imagePath) => !referencedImageKeys.has(canonicalPathKey(imagePath)),
    );
    const sourceDirectoryRow = {
      source_root_path: directory.sourceRootPath,
      relative_source_path: directory.relativeSourcePath,
      image_count: directory.images.length,
      cache_files: cacheFilesForDirectory,
      cached_image_count: directory.images.length - uncachedForDirectory.length,
      uncached_image_count: uncachedForDirectory.length,
    };
    sourceDirectoryRows.push(sourceDirectoryRow);

    for (const imagePath of uncachedForDirectory) {
      uncachedImages.push(
        inspectUncachedImage(
          report,
          sourceRoot,
          directory.sourceRootPath,
          imagePath,
        ),
      );
    }
  }

  sourceDirectoryRows.sort((left, right) =>
    compareText(left.source_root_path, right.source_root_path),
  );
  uncachedImages.sort((left, right) => compareText(left.image_path, right.image_path));
  missingFrameImages.sort(compareMissingFrameRows);

  report.cache_source_groups = cacheGroupRows;
  report.source_directories = sourceDirectoryRows;
  report.missing_cache_directories = sourceDirectoryRows
    .filter((row) => row.cache_files.length === 0)
    .map((row) => ({
      source_root_path: row.source_root_path,
      relative_source_path: row.relative_source_path,
      image_count: row.image_count,
      uncached_image_count: row.uncached_image_count,
    }));
  report.cache_source_issues = cacheGroupRows.filter(
    (row) => row.status !== 'ok',
  );
  report.uncached_images = uncachedImages;
  report.uncached_png_with_prompt_metadata = uncachedImages
    .filter((row) => row.prompt_metadata_status === 'usable')
    .map((row) => row.image_path);
  report.uncached_png_without_prompt_metadata = uncachedImages
    .filter((row) => row.prompt_metadata_status === 'not_usable')
    .map((row) => row.image_path);
  report.uncached_png_metadata_errors = uncachedImages
    .filter((row) => row.prompt_metadata_status === 'parse_error')
    .map((row) => ({
      image_path: row.image_path,
      message: row.png_metadata_error,
    }));
  report.missing_frame_images = missingFrameImages;

  report.summary.cache_file_count = cacheFiles.length;
  report.summary.cache_source_group_count = cacheGroupRows.length;
  report.summary.source_directory_count = sourceDirectoryRows.length;
  report.summary.source_image_count = sourceDirectories.reduce(
    (total, directory) => total + directory.images.length,
    0,
  );
  report.summary.frame_image_reference_count = frameImageReferenceCount;
  report.summary.existing_frame_image_reference_count =
    existingFrameImageReferenceCount;
  report.summary.unique_existing_frame_image_count =
    existingReferencedImageKeys.size;
  report.summary.missing_cache_directory_count =
    report.missing_cache_directories.length;
  report.summary.cache_source_issue_count = report.cache_source_issues.length;
  report.summary.uncached_image_count = uncachedImages.length;
  report.summary.uncached_png_with_prompt_metadata_count =
    report.uncached_png_with_prompt_metadata.length;
  report.summary.uncached_png_without_prompt_metadata_count =
    report.uncached_png_without_prompt_metadata.length;
  report.summary.uncached_png_metadata_error_count =
    report.uncached_png_metadata_errors.length;
  report.summary.missing_frame_image_count = missingFrameImages.length;
}

function collectSourceDirectories(sourceRoot) {
  const result = [];

  function visit(directory) {
    const entries = fs
      .readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => compareText(left.name, right.name));
    const images = entries
      .filter((entry) => entry.isFile() && isImagePath(entry.name))
      .map((entry) => path.join(directory, entry.name))
      .sort(compareText);
    if (images.length > 0) {
      result.push({
        sourceRootPath: path.resolve(directory),
        relativeSourcePath: portableRelative(sourceRoot, directory) || '.',
        images,
      });
    }
    for (const entry of entries) {
      if (entry.isDirectory()) visit(path.join(directory, entry.name));
    }
  }

  visit(sourceRoot);
  return result.sort((left, right) =>
    compareText(left.sourceRootPath, right.sourceRootPath),
  );
}

function collectFilesRecursively(root, predicate) {
  const result = [];

  function visit(directory) {
    const entries = fs
      .readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => compareText(left.name, right.name));
    for (const entry of entries) {
      const current = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        visit(current);
      } else if (entry.isFile() && predicate(current)) {
        result.push(current);
      }
    }
  }

  visit(root);
  return result.sort(compareText);
}

function cacheGroupRow(group, sourceDirectoryByKey) {
  const matchingSourceDirectory = sourceDirectoryByKey.get(group.key);
  const sourceRootPath = matchingSourceDirectory
    ? matchingSourceDirectory.sourceRootPath
    : [...group.sourcePaths].sort(compareText)[0];
  let status = 'ok';
  let imageCount = 0;
  if (!fs.existsSync(sourceRootPath)) {
    status = 'path_not_found';
  } else {
    const stat = fs.statSync(sourceRootPath);
    if (!stat.isDirectory()) {
      status = 'not_directory';
    } else if (matchingSourceDirectory) {
      imageCount = matchingSourceDirectory.images.length;
    } else {
      imageCount = directImageFiles(sourceRootPath).length;
      if (imageCount === 0) status = 'no_images';
    }
  }
  return {
    source_root_path: sourceRootPath,
    cache_files: [...group.cacheFiles].sort(compareText),
    status,
    image_count: imageCount,
  };
}

function directImageFiles(directory) {
  return fs
    .readdirSync(directory, { withFileTypes: true })
    .filter((entry) => entry.isFile() && isImagePath(entry.name))
    .map((entry) => path.join(directory, entry.name))
    .sort(compareText);
}

function frameImageReference(frame, sourceRootPath) {
  const candidates = [
    ['sourceImagePath', frame.sourceImagePath ?? frame.source_image_path],
    ['sourcePath', frame.sourcePath ?? frame.source_path],
    ['fileName', frame.fileName ?? frame.file_name],
  ];
  for (const [field, value] of candidates) {
    const text = stringValue(value).trim();
    if (!text) continue;
    const imagePath = path.isAbsolute(text)
      ? path.resolve(text)
      : path.resolve(sourceRootPath, text);
    if (isImagePath(imagePath)) return { field, imagePath };
  }
  return null;
}

function inspectUncachedImage(
  report,
  sourceRoot,
  sourceDirectory,
  imagePath,
) {
  const extension = path.extname(imagePath).toLowerCase();
  const row = {
    source_root_path: sourceDirectory,
    image_path: path.resolve(imagePath),
    relative_path: portableRelative(sourceRoot, imagePath),
    file_name: path.basename(imagePath),
    extension,
    prompt_metadata_status: 'not_applicable',
    png_text_chunk_types: [],
    png_text_keywords: [],
  };
  if (extension !== '.png') return row;

  try {
    const metadata = inspectPngPromptMetadata(imagePath);
    row.prompt_metadata_status = metadata.usable ? 'usable' : 'not_usable';
    row.png_text_chunk_types = metadata.chunkTypes;
    row.png_text_keywords = metadata.keywords;
  } catch (error) {
    const message = errorMessage(error);
    row.prompt_metadata_status = 'parse_error';
    row.png_metadata_error = message;
    report.errors.push({
      scope: 'png_metadata_parse',
      image_path: row.image_path,
      message,
    });
  }
  return row;
}

function inspectPngPromptMetadata(filePath) {
  const buffer = fs.readFileSync(filePath);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (buffer.length < signature.length || !buffer.subarray(0, 8).equals(signature)) {
    throw new Error('Invalid PNG signature.');
  }

  const payload = {};
  const chunkTypes = new Set();
  let offset = 8;
  let foundEnd = false;
  while (offset < buffer.length) {
    if (offset + 12 > buffer.length) {
      throw new Error(`Truncated PNG chunk at byte ${offset}.`);
    }
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const chunkEnd = dataEnd + 4;
    if (dataEnd < dataStart || chunkEnd > buffer.length) {
      throw new Error(`Truncated ${type || 'unknown'} PNG chunk at byte ${offset}.`);
    }
    const data = buffer.subarray(dataStart, dataEnd);
    if (type === 'tEXt') {
      const entry = parseTextChunk(data);
      payload[entry.key] = entry.value;
      chunkTypes.add(type);
    } else if (type === 'zTXt') {
      const entry = parseCompressedTextChunk(data);
      payload[entry.key] = entry.value;
      chunkTypes.add(type);
    } else if (type === 'iTXt') {
      const entry = parseInternationalTextChunk(data);
      payload[entry.key] = entry.value;
      chunkTypes.add(type);
    }
    offset = chunkEnd;
    if (type === 'IEND') {
      foundEnd = true;
      break;
    }
  }
  if (!foundEnd) throw new Error('PNG has no complete IEND chunk.');

  return {
    usable: hasPromptMetadata(parsePromptMetadata(payload)),
    chunkTypes: pngTextChunkOrder.filter((type) => chunkTypes.has(type)),
    keywords: Object.keys(payload).sort(compareText),
  };
}

function parseTextChunk(data) {
  const separator = data.indexOf(0);
  if (separator <= 0) throw new Error('Malformed tEXt PNG chunk.');
  return {
    key: data.subarray(0, separator).toString('utf8'),
    value: data.subarray(separator + 1).toString('utf8'),
  };
}

function parseCompressedTextChunk(data) {
  const separator = data.indexOf(0);
  if (separator <= 0 || separator + 2 > data.length || data[separator + 1] !== 0) {
    throw new Error('Malformed zTXt PNG chunk.');
  }
  return {
    key: data.subarray(0, separator).toString('utf8'),
    value: zlib.inflateSync(data.subarray(separator + 2)).toString('utf8'),
  };
}

function parseInternationalTextChunk(data) {
  const keywordEnd = data.indexOf(0);
  if (keywordEnd <= 0 || keywordEnd + 5 > data.length) {
    throw new Error('Malformed iTXt PNG chunk.');
  }
  const key = data.subarray(0, keywordEnd).toString('utf8');
  let cursor = keywordEnd + 1;
  const compressionFlag = data[cursor++];
  const compressionMethod = data[cursor++];
  if ((compressionFlag !== 0 && compressionFlag !== 1) || compressionMethod !== 0) {
    throw new Error('Unsupported iTXt PNG compression.');
  }
  const languageEnd = data.indexOf(0, cursor);
  if (languageEnd < 0) throw new Error('Malformed iTXt PNG language field.');
  cursor = languageEnd + 1;
  const translatedEnd = data.indexOf(0, cursor);
  if (translatedEnd < 0) throw new Error('Malformed iTXt PNG translated field.');
  cursor = translatedEnd + 1;
  const textBytes = data.subarray(cursor);
  return {
    key,
    value: (compressionFlag === 0 ? textBytes : zlib.inflateSync(textBytes)).toString(
      'utf8',
    ),
  };
}

function parsePromptMetadata(payload) {
  const merged = {};
  mergeIfStructured(merged, payload);
  absorb(payload.Comment, merged);
  absorb(payload.fullContent, merged);
  absorb(payload.Stealth_PNGInfo, merged);
  return {
    prompt:
      firstString([
        payload.Description,
        payload.prompt,
        payload.Prompt,
        merged.Description,
        merged.prompt,
        merged.Prompt,
        v4BaseCaption(merged, 'v4_prompt'),
      ]) || '',
    charCaptions: extractCharCaptions(merged, 'v4_prompt'),
  };
}

function absorb(value, merged) {
  if (value == null) return;
  const decoded = decodePayload(value);
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return;
  mergeIfStructured(merged, decoded);
  absorb(decoded.Comment, merged);
  absorb(decoded.Description, merged);
  absorb(decoded.fullContent, merged);
  absorb(decoded.Stealth_PNGInfo, merged);
}

function mergeIfStructured(target, source) {
  if (!source || typeof source !== 'object' || Array.isArray(source)) return;
  if (!Object.keys(source).some((key) => structuredKeys.has(key))) return;
  for (const [key, value] of Object.entries(source)) {
    if (
      key === 'parameters' &&
      value &&
      typeof value === 'object' &&
      !Array.isArray(value)
    ) {
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
  if (!trimmed || !/^[{[\"]/.test(trimmed)) return value;
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
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
  return (
    firstString([
      caption.base_caption,
      caption.baseCaption,
      caption.prompt,
      caption.caption,
    ]) || ''
  );
}

function extractCharCaptions(parameters, key) {
  const caption = v4Caption(parameters, key);
  const entries = caption?.char_captions ?? parameters.char_captions;
  if (!Array.isArray(entries)) return [];
  return entries
    .filter((entry) => entry && typeof entry === 'object' && !Array.isArray(entry))
    .map((entry) =>
      firstString([
        entry.char_caption,
        entry.caption,
        entry.prompt,
        entry.base_caption,
      ]),
    )
    .filter(Boolean);
}

function hasPromptMetadata(metadata) {
  return Boolean(
    metadata.prompt.trim() ||
      metadata.charCaptions.some((caption) => stringValue(caption).trim()),
  );
}

function firstString(values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim()) return value;
  }
  return null;
}

function parseArgs(values) {
  const parsed = {
    cacheDir: '',
    sourceRoot: '',
    reportPath: '',
  };
  for (let index = 0; index < values.length; index += 1) {
    const argument = values[index];
    if (!argument.startsWith('--')) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const equalIndex = argument.indexOf('=');
    const key = equalIndex < 0 ? argument.slice(2) : argument.slice(2, equalIndex);
    const value = equalIndex < 0 ? values[++index] : argument.slice(equalIndex + 1);
    if (value == null || value === '' || value.startsWith('--')) {
      throw new Error(`Missing value for --${key}.`);
    }
    if (key === 'cache-dir') parsed.cacheDir = value;
    else if (key === 'source-root') parsed.sourceRoot = value;
    else if (key === 'report') parsed.reportPath = value;
    else throw new Error(`Unknown option: --${key}`);
  }
  if (!parsed.cacheDir || !parsed.sourceRoot || !parsed.reportPath) {
    throw new Error(
      'Pass --cache-dir <directory> --source-root <directory> --report <file>.',
    );
  }
  return parsed;
}

function assertSafeReportPath(reportPath, cacheDir, sourceRoot) {
  if (pathIsWithin(reportPath, cacheDir) || pathIsWithin(reportPath, sourceRoot)) {
    throw new Error('The report path must be outside --cache-dir and --source-root.');
  }
}

function assertDirectory(directory, label) {
  if (!fs.existsSync(directory)) throw new Error(`${label} does not exist: ${directory}`);
  if (!fs.statSync(directory).isDirectory()) {
    throw new Error(`${label} is not a directory: ${directory}`);
  }
}

function pathIsWithin(candidate, parent) {
  const relative = path.relative(parent, candidate);
  return (
    relative === '' ||
    (!relative.startsWith(`..${path.sep}`) &&
      relative !== '..' &&
      !path.isAbsolute(relative))
  );
}

function canonicalPathKey(value) {
  let resolved = path.resolve(value);
  try {
    if (fs.existsSync(resolved)) resolved = fs.realpathSync.native(resolved);
  } catch {
    // A later stat/read reports the actionable filesystem failure.
  }
  const portable = resolved.replaceAll('\\', '/').replace(/\/+$/, '');
  return process.platform === 'win32' ? portable.toLowerCase() : portable;
}

function portableRelative(root, target) {
  return path.relative(root, target).replaceAll('\\', '/');
}

function isImagePath(value) {
  return imageExtensions.has(path.extname(value).toLowerCase());
}

function isFile(value) {
  try {
    return fs.statSync(value).isFile();
  } catch {
    return false;
  }
}

function normalizedFrameIndex(value, offset) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : offset + 1;
}

function compareMissingFrameRows(left, right) {
  return (
    compareText(left.cache_file, right.cache_file) ||
    left.frame_index - right.frame_index ||
    compareText(left.image_path, right.image_path)
  );
}

function compareErrorRows(left, right) {
  return (
    compareText(left.scope, right.scope) ||
    compareText(left.cache_file, right.cache_file) ||
    compareText(left.image_path, right.image_path) ||
    compareText(left.message, right.message)
  );
}

function compareText(left, right) {
  const leftText = stringValue(left);
  const rightText = stringValue(right);
  return leftText < rightText ? -1 : leftText > rightText ? 1 : 0;
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
