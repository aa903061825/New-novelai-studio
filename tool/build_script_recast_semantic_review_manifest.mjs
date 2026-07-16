import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const ROLE_WARNING = 'display_name_needs_manual_review';
const STAGE_WARNINGS = new Set([
  'label_needs_manual_review',
  'stage_label_needs_manual_review',
]);
const MAX_CAPTION_EVIDENCE = 3;

try {
  const options = parseArgs(process.argv.slice(2));
  const result = buildManifest(options);
  writeOutputs(options.outputDir, result);
  process.stdout.write(`${JSON.stringify(result.manifest.summary)}\n`);
} catch (error) {
  process.stderr.write(`Semantic review manifest failed: ${error.message}\n`);
  process.exitCode = 1;
}

function parseArgs(args) {
  const values = new Map();
  for (let index = 0; index < args.length; index += 1) {
    const flag = args[index];
    if (!['--cache-dir', '--output-dir', '--shards'].includes(flag)) {
      throw new Error(`Unknown argument: ${flag}`);
    }
    const value = args[index + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`Missing value for ${flag}`);
    }
    if (values.has(flag)) {
      throw new Error(`Duplicate argument: ${flag}`);
    }
    values.set(flag, value);
    index += 1;
  }

  for (const flag of ['--cache-dir', '--output-dir', '--shards']) {
    if (!values.has(flag)) {
      throw new Error(`Required argument missing: ${flag}`);
    }
  }

  const shardCount = Number(values.get('--shards'));
  if (!Number.isInteger(shardCount) || shardCount < 1 || shardCount > 128) {
    throw new Error('--shards must be an integer from 1 through 128');
  }

  const cacheDir = path.resolve(values.get('--cache-dir'));
  const outputDir = path.resolve(values.get('--output-dir'));
  if (!fs.existsSync(cacheDir) || !fs.statSync(cacheDir).isDirectory()) {
    throw new Error(`Cache directory does not exist: ${cacheDir}`);
  }
  if (isSameOrInside(outputDir, cacheDir)) {
    throw new Error('Output directory must not be the cache directory or its child');
  }

  return { cacheDir, outputDir, shardCount };
}

function buildManifest({ cacheDir, shardCount }) {
  const filenames = fs
    .readdirSync(cacheDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith('.json'))
    .map((entry) => entry.name)
    .sort(compareText);

  const groups = new Map();
  for (const filename of filenames) {
    const cache = readCache(path.join(cacheDir, filename), filename);
    const sourceRootPath = stringValue(cache.sourceRootPath);
    const sourceKey = normalizeWindowsPath(sourceRootPath);
    if (!sourceKey) {
      throw new Error(`${filename} has no sourceRootPath`);
    }
    if (!isObject(cache.aiRoleExtraction)) {
      throw new Error(`${filename} has no aiRoleExtraction object`);
    }

    const aiSignature = sha256(canonicalJson(cache.aiRoleExtraction));
    const cacheIdentity = {
      filename,
      script_id: stringValue(cache.scriptId ?? cache.script_id),
    };
    const existing = groups.get(sourceKey);
    if (existing) {
      if (existing.aiSignature !== aiSignature) {
        throw new Error(
          `Duplicate source has inconsistent AI structure: ` +
            `${existing.entries[0].filename} vs ${filename} (${sourceRootPath})`,
        );
      }
      existing.entries.push(cacheIdentity);
      continue;
    }

    groups.set(sourceKey, {
      key: sourceKey,
      aiSignature,
      entries: [cacheIdentity],
      representative: buildReviewSource(cache, filename, sourceRootPath),
    });
  }

  const sourceGroups = [...groups.values()].sort((left, right) =>
    compareText(left.key, right.key),
  );
  const reviewSources = sourceGroups
    .filter(
      (group) =>
        group.representative.roles.length > 0 ||
        group.representative.stages.length > 0,
    )
    .map((group) => {
      const entries = [...group.entries].sort((left, right) =>
        compareText(left.filename, right.filename),
      );
      const data = {
        api_used: false,
        source_root_path: group.representative.source_root_path,
        representative_cache_file:
          group.representative.representative_cache_file,
        cache_files: entries.map((entry) => entry.filename),
        script_ids: entries.map((entry) => entry.script_id),
        caches: entries,
        script_name: group.representative.script_name,
        roles: group.representative.roles,
        stages: group.representative.stages,
        item_count: group.representative.item_count,
        frame_reference_count: group.representative.frame_reference_count,
        workload: group.representative.workload,
      };
      return { key: group.key, data };
    });

  const shardAssignments = assignShards(reviewSources, shardCount);
  const summary = summarizeSources(reviewSources.map((source) => source.data));
  const duplicateCacheCount = filenames.length - groups.size;
  const manifest = {
    schema_version: 1,
    kind: 'script_recast_semantic_review_manifest',
    mode: 'read_only',
    api_used: false,
    cache_dir: cacheDir,
    shard_count: shardCount,
    summary: {
      cache_file_count: filenames.length,
      source_group_count: groups.size,
      duplicate_cache_count: duplicateCacheCount,
      review_source_count: reviewSources.length,
      ...summary,
    },
    sources: reviewSources.map((source) => source.data),
    shards: shardAssignments.map((assignment, index) => ({
      shard_index: index + 1,
      filename: `shard_${index + 1}.json`,
      ...summarizeSources(assignment.map((source) => source.data)),
    })),
  };

  const shards = shardAssignments.map((assignment, index) => ({
    schema_version: 1,
    kind: 'script_recast_semantic_review_shard',
    mode: 'read_only',
    api_used: false,
    cache_dir: cacheDir,
    shard_index: index + 1,
    shard_count: shardCount,
    summary: summarizeSources(assignment.map((source) => source.data)),
    sources: assignment.map((source) => source.data),
  }));

  return { manifest, shards };
}

function readCache(cachePath, filename) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  } catch (error) {
    throw new Error(`Could not parse ${filename}: ${error.message}`);
  }
  if (!isObject(parsed)) {
    throw new Error(`${filename} does not contain a JSON object`);
  }
  return parsed;
}

function buildReviewSource(cache, filename, sourceRootPath) {
  const frames = new Map(
    arrayValue(cache.scriptSnapshot?.frames)
      .filter((frame) => isObject(frame) && Number.isFinite(Number(frame.index)))
      .map((frame) => [Number(frame.index), frame]),
  );
  const roles = [];
  const stages = [];

  for (const role of arrayValue(cache.aiRoleExtraction?.roles)) {
    if (!isObject(role)) continue;
    const appearances = normalizeAppearances(role.appearances);
    const roleFrameIndexes = numberList(role.frame_indexes ?? role.frameIndexes);
    if (hasWarning(role.warnings, ROLE_WARNING)) {
      roles.push({
        role_id: stringValue(role.source_role_id ?? role.sourceRoleId ?? role.id),
        display_name: stringValue(role.display_name ?? role.displayName),
        canonical_name: stringValue(role.canonical_name ?? role.canonicalName),
        raw_identity_tags: stringList(
          role.raw_identity_tags ?? role.rawIdentityTags,
        ),
        frame_indexes: roleFrameIndexes,
        evidence_terms: stringList(role.evidence_terms ?? role.evidenceTerms),
        warnings: stringList(role.warnings),
        char_caption_evidence: captionEvidence(
          frames,
          appearances,
          roleFrameIndexes,
        ),
      });
    }

    for (const stage of arrayValue(role.stages)) {
      if (!isObject(stage) || !hasAnyWarning(stage.warnings, STAGE_WARNINGS)) {
        continue;
      }
      const stageFrameIndexes = numberList(
        stage.frame_indexes ?? stage.frameIndexes,
      );
      stages.push({
        role_id: stringValue(role.source_role_id ?? role.sourceRoleId ?? role.id),
        stage_id: stringValue(stage.stage_id ?? stage.stageId ?? stage.id),
        current_label: stringValue(stage.label),
        appearance_group_id: stringValue(
          stage.appearance_group_id ?? stage.appearanceGroupId,
        ),
        frame_indexes: stageFrameIndexes,
        evidence_terms: stringList(stage.evidence_terms ?? stage.evidenceTerms),
        identity: stringValue(stage.identity),
        upper_body: stringValue(stage.upper_body ?? stage.upperBody),
        lower_body: stringValue(stage.lower_body ?? stage.lowerBody),
        upper_clothing: stringValue(
          stage.upper_clothing ?? stage.upperClothing,
        ),
        lower_clothing: stringValue(
          stage.lower_clothing ?? stage.lowerClothing,
        ),
        field_reasons: normalizedFieldReasons(
          stage.field_reasons ?? stage.fieldReasons,
        ),
        missing_fields: stringList(stage.missing_fields ?? stage.missingFields),
        confidence: numberOrNull(stage.confidence),
        warnings: stringList(stage.warnings),
        char_caption_evidence: captionEvidence(
          frames,
          appearances,
          stageFrameIndexes,
        ),
      });
    }
  }

  roles.sort(compareRoleItems);
  stages.sort(compareStageItems);
  const itemCount = roles.length + stages.length;
  const frameReferenceCount =
    roles.reduce((total, role) => total + role.frame_indexes.length, 0) +
    stages.reduce((total, stage) => total + stage.frame_indexes.length, 0);
  return {
    source_root_path: sourceRootPath,
    representative_cache_file: filename,
    script_name: stringValue(cache.scriptName ?? cache.scriptSnapshot?.name),
    roles,
    stages,
    item_count: itemCount,
    frame_reference_count: frameReferenceCount,
    workload: itemCount + frameReferenceCount,
  };
}

function normalizeAppearances(value) {
  return arrayValue(value)
    .filter(isObject)
    .map((appearance) => {
      const sourceId = stringValue(
        appearance.source_id ?? appearance.sourceId,
      );
      const sourceKind = stringValue(
        appearance.source_kind ?? appearance.sourceKind,
      );
      const slotMatch = /^slot-(\d+)$/i.exec(sourceId);
      return {
        source_id: sourceId,
        source_kind: sourceKind,
        slot_index:
          sourceKind.toLowerCase() === 'slot' && slotMatch
            ? Number(slotMatch[1])
            : null,
        frame_indexes: new Set(
          numberList(appearance.frame_indexes ?? appearance.frameIndexes),
        ),
      };
    })
    .filter((appearance) => Number.isInteger(appearance.slot_index))
    .sort((left, right) => {
      const slotOrder = left.slot_index - right.slot_index;
      return slotOrder || compareText(left.source_id, right.source_id);
    });
}

function captionEvidence(frames, appearances, frameIndexes) {
  const evidence = [];
  for (const frameIndex of frameIndexes) {
    const frame = frames.get(frameIndex);
    if (!frame) continue;
    const captions = arrayValue(
      frame.parsed?.charCaptions ?? frame.parsed?.char_captions,
    );
    for (const appearance of appearances) {
      if (!appearance.frame_indexes.has(frameIndex)) continue;
      const caption = captions[appearance.slot_index];
      if (typeof caption !== 'string' || caption.trim().length === 0) continue;
      evidence.push({
        frame_index: frameIndex,
        source_id: appearance.source_id,
        slot_index: appearance.slot_index,
        char_caption: caption,
      });
      if (evidence.length >= MAX_CAPTION_EVIDENCE) return evidence;
    }
  }
  return evidence;
}

function assignShards(sources, shardCount) {
  const assignments = Array.from({ length: shardCount }, () => []);
  const loads = Array.from({ length: shardCount }, () => ({
    workload: 0,
    itemCount: 0,
  }));
  const ordered = [...sources].sort((left, right) => {
    const workloadOrder = right.data.workload - left.data.workload;
    if (workloadOrder !== 0) return workloadOrder;
    const itemOrder = right.data.item_count - left.data.item_count;
    return itemOrder || compareText(left.key, right.key);
  });

  for (const source of ordered) {
    let target = 0;
    for (let index = 1; index < shardCount; index += 1) {
      const candidate = loads[index];
      const current = loads[target];
      if (
        candidate.workload < current.workload ||
        (candidate.workload === current.workload &&
          candidate.itemCount < current.itemCount)
      ) {
        target = index;
      }
    }
    assignments[target].push(source);
    loads[target].workload += source.data.workload;
    loads[target].itemCount += source.data.item_count;
  }

  for (const assignment of assignments) {
    assignment.sort((left, right) => compareText(left.key, right.key));
  }
  return assignments;
}

function summarizeSources(sources) {
  return {
    source_count: sources.length,
    role_item_count: sources.reduce(
      (total, source) => total + source.roles.length,
      0,
    ),
    stage_item_count: sources.reduce(
      (total, source) => total + source.stages.length,
      0,
    ),
    item_count: sources.reduce(
      (total, source) => total + source.item_count,
      0,
    ),
    frame_reference_count: sources.reduce(
      (total, source) => total + source.frame_reference_count,
      0,
    ),
    workload: sources.reduce(
      (total, source) => total + source.workload,
      0,
    ),
  };
}

function writeOutputs(outputDir, { manifest, shards }) {
  fs.mkdirSync(outputDir, { recursive: true });
  const outputs = [
    ['manifest.json', manifest],
    ...shards.map((shard, index) => [`shard_${index + 1}.json`, shard]),
  ];
  for (const [filename, value] of outputs) {
    fs.writeFileSync(
      path.join(outputDir, filename),
      `${JSON.stringify(value, null, 2)}\n`,
      'utf8',
    );
  }
}

function normalizedFieldReasons(value) {
  const reasons = isObject(value) ? value : {};
  return {
    identity: stringValue(reasons.identity),
    upper_body: stringValue(reasons.upper_body ?? reasons.upperBody),
    lower_body: stringValue(reasons.lower_body ?? reasons.lowerBody),
    upper_clothing: stringValue(
      reasons.upper_clothing ?? reasons.upperClothing,
    ),
    lower_clothing: stringValue(
      reasons.lower_clothing ?? reasons.lowerClothing,
    ),
  };
}

function normalizeWindowsPath(value) {
  let normalized = stringValue(value).trim().replaceAll('\\', '/');
  const uncPrefix = normalized.startsWith('//') ? '//' : '';
  if (uncPrefix) normalized = normalized.slice(2);
  normalized = `${uncPrefix}${normalized.replace(/\/{2,}/g, '/')}`;
  if (normalized !== '/' && !/^[a-z]:\/$/i.test(normalized)) {
    normalized = normalized.replace(/\/+$/, '');
  }
  return normalized.toLowerCase();
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (isObject(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function hasWarning(value, warning) {
  return arrayValue(value).some((entry) => stringValue(entry) === warning);
}

function hasAnyWarning(value, warnings) {
  return arrayValue(value).some((entry) => warnings.has(stringValue(entry)));
}

function numberList(value) {
  return [...new Set(arrayValue(value).map(Number).filter(Number.isFinite))].sort(
    (left, right) => left - right,
  );
}

function stringList(value) {
  return arrayValue(value).map(stringValue);
}

function stringValue(value) {
  return value == null ? '' : String(value);
}

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function arrayValue(value) {
  return Array.isArray(value) ? value : [];
}

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function compareText(left, right) {
  const normalizedLeft = stringValue(left).toLowerCase();
  const normalizedRight = stringValue(right).toLowerCase();
  if (normalizedLeft < normalizedRight) return -1;
  if (normalizedLeft > normalizedRight) return 1;
  const rawLeft = stringValue(left);
  const rawRight = stringValue(right);
  if (rawLeft < rawRight) return -1;
  if (rawLeft > rawRight) return 1;
  return 0;
}

function compareRoleItems(left, right) {
  return (
    compareText(left.role_id, right.role_id) ||
    compareText(left.display_name, right.display_name)
  );
}

function compareStageItems(left, right) {
  return (
    compareText(left.role_id, right.role_id) ||
    compareText(left.stage_id, right.stage_id) ||
    compareText(left.current_label, right.current_label)
  );
}

function isSameOrInside(candidate, parent) {
  const candidatePath = path.resolve(candidate).toLowerCase();
  const parentPath = path.resolve(parent).toLowerCase();
  return (
    candidatePath === parentPath ||
    candidatePath.startsWith(`${parentPath}${path.sep}`)
  );
}
