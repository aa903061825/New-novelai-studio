import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:uuid/uuid.dart';

const _defaultSourceRoot = r'E:\NAI的脚本群\作品集\带图精品';

Future<void> main(List<String> arguments) async {
  final options = _parseOptions(arguments);
  final cacheDirectory = Directory(_requiredOption(options, 'cache-dir'));
  final libraryFile = File(_requiredOption(options, 'library'));
  final charactersFile = File(_requiredOption(options, 'characters'));
  final reportFile = File(_requiredOption(options, 'report'));
  final backupDirectory = Directory(
    options['backup-dir'] ??
        'build/role_mapping_profiles_backup_${_timestampForPath(DateTime.now().toUtc())}',
  );
  final sourceRoot = options['source-root'] ?? _defaultSourceRoot;
  final apply = options.containsKey('apply');

  if (!await cacheDirectory.exists()) {
    throw FileSystemException('剧本缓存目录不存在', cacheDirectory.path);
  }
  if (!await charactersFile.exists()) {
    throw FileSystemException('角色素材库不存在', charactersFile.path);
  }

  final charactersById = await _loadCharacterNames(charactersFile);
  final existingLibrary = await _loadLibrary(libraryFile);
  final cacheFiles = await cacheDirectory
      .list(followLinks: false)
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
  cacheFiles.sort((left, right) => left.path.compareTo(right.path));

  final candidates = <_RoleCandidate>[];
  final cacheRows = <_CacheRow>[];
  final parseFailures = <Map<String, Object?>>[];
  final logicalCacheWinners = <String, _CacheRank>{};

  for (final file in cacheFiles) {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('cache JSON root is not an object');
      }
      final cache = RecastScriptCache.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final logicalKey = _logicalCacheKey(cache);
      final rank = _CacheRank(
        filePath: file.path,
        updatedAt: cache.updatedAt.toUtc(),
      );
      final currentWinner = logicalCacheWinners[logicalKey];
      if (currentWinner == null || rank.isNewerThan(currentWinner)) {
        logicalCacheWinners[logicalKey] = rank;
      }
      final mappedRoles = <_RoleCandidate>[];
      for (final replacement in cache.mapping.rolePromptReplacements) {
        final candidate = _candidateFromReplacement(
          cache: cache,
          cacheFile: file,
          replacement: replacement,
          characterName: charactersById[replacement.targetCharacterId?.trim()],
        );
        if (candidate == null) continue;
        candidates.add(candidate);
        mappedRoles.add(candidate);
      }
      cacheRows.add(
        _CacheRow(
          filePath: file.path,
          scriptId: cache.scriptId,
          scriptName: cache.scriptName,
          sourceRootPath: cache.sourceRootPath,
          updatedAt: cache.updatedAt.toUtc(),
          logicalKey: logicalKey,
          frameCount: (cache.scriptSnapshot['frames'] as List?)?.length ?? 0,
          roleCount: cache.mapping.rolePromptReplacements.length,
          mappedRoleCount: mappedRoles.length,
          effectiveRuleCount: mappedRoles.fold(
            0,
            (total, role) => total + role.blocks.length,
          ),
        ),
      );
    } catch (error) {
      parseFailures.add({
        'file': file.path,
        'error': error.toString(),
      });
    }
  }

  final winnerPaths = {
    for (final rank in logicalCacheWinners.values) rank.filePath,
  };
  final currentCandidates = [
    for (final candidate in candidates)
      if (winnerPaths.contains(candidate.cacheFilePath)) candidate,
  ];
  final groups = <String, List<_RoleCandidate>>{};
  for (final candidate in currentCandidates) {
    groups.putIfAbsent(candidate.groupKey, () => []).add(candidate);
  }

  final existingProfilesByGroup = <String, RoleMappingProfile>{};
  final unmatchedExistingProfiles = <RoleMappingProfile>[];
  for (final profile in existingLibrary.profiles) {
    final groupKey = _groupKeyForProfile(profile);
    if (groupKey.isEmpty || existingProfilesByGroup.containsKey(groupKey)) {
      unmatchedExistingProfiles.add(profile);
    } else {
      existingProfilesByGroup[groupKey] = profile;
    }
  }

  final now = DateTime.now().toUtc();
  final usedNames = <String>{};
  final outputProfiles = <RoleMappingProfile>[];
  final profileReports = <Map<String, Object?>>[];
  final allConflicts = <Map<String, Object?>>[];
  final sortedGroupKeys = groups.keys.toList()..sort();

  for (final groupKey in sortedGroupKeys) {
    final groupCandidates = groups[groupKey]!
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    final existing = existingProfilesByGroup.remove(groupKey);
    final merge = _mergeGroup(
      groupKey: groupKey,
      candidates: groupCandidates,
      existing: existing,
      charactersById: charactersById,
      usedNames: usedNames,
      now: now,
    );
    outputProfiles.add(merge.profile);
    profileReports.add(merge.report);
    allConflicts.addAll(merge.conflicts);
  }

  for (final profile in [
    ...existingProfilesByGroup.values,
    ...unmatchedExistingProfiles,
  ]) {
    final uniqueName = _uniqueName(profile.name, usedNames);
    outputProfiles.add(
      uniqueName == profile.name ? profile : profile.copyWith(name: uniqueName),
    );
    profileReports.add({
      'profileId': profile.id,
      'name': uniqueName,
      'groupKey': _groupKeyForProfile(profile),
      'preservedWithoutCurrentCacheMatch': true,
      'blockCount': profile.blocks.length,
    });
  }

  outputProfiles.sort(
    (left, right) =>
        left.name.toLowerCase().compareTo(right.name.toLowerCase()),
  );
  validateRoleMappingProfileNames(outputProfiles);
  final outputLibrary = RoleMappingProfileLibrary(
    profiles: List.unmodifiable(outputProfiles),
  );
  final wouldWriteLibrary = jsonEncode(existingLibrary.toJson()) !=
      jsonEncode(outputLibrary.toJson());

  final normalizedSourceRoot = _normalizedWindowsPath(sourceRoot);
  final outsideSourceRoot = [
    for (final row in cacheRows)
      if (!_normalizedWindowsPath(row.sourceRootPath)
          .startsWith(normalizedSourceRoot))
        row,
  ];
  final shadowedRows = [
    for (final row in cacheRows)
      if (!winnerPaths.contains(row.filePath)) row,
  ];
  final selectedRows = [
    for (final row in cacheRows)
      if (winnerPaths.contains(row.filePath)) row,
  ];
  final report = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': now.toIso8601String(),
    'mode': apply ? 'apply' : 'dry-run',
    'cacheDirectory': cacheDirectory.path,
    'libraryPath': libraryFile.path,
    'sourceRootScope': sourceRoot,
    'summary': {
      'cacheFileCount': cacheFiles.length,
      'parsedCacheCount': cacheRows.length,
      'parseFailureCount': parseFailures.length,
      'logicalCurrentCacheCount': selectedRows.length,
      'shadowedCacheCount': shadowedRows.length,
      'outsideDefaultSourceRootCount': outsideSourceRoot.length,
      'mappedRoleOccurrenceCount': currentCandidates.length,
      'targetProfileCount': outputProfiles.length,
      'generatedOrMergedProfileCount': groups.length,
      'preservedExistingProfileCount': outputProfiles.length - groups.length,
      'inputEffectiveBlockCount': currentCandidates.fold(
        0,
        (total, candidate) => total + candidate.blocks.length,
      ),
      'outputBlockCount': outputProfiles.fold(
        0,
        (total, profile) => total + profile.blocks.length,
      ),
      'effectConflictCount': allConflicts.length,
      'changedProfileCount': profileReports
          .where((profile) => profile['contentChanged'] == true)
          .length,
      'wouldWriteLibrary': wouldWriteLibrary,
    },
    'profiles': profileReports,
    'conflicts': allConflicts,
    'parseFailures': parseFailures,
    'outsideDefaultSourceRoot': [
      for (final row in outsideSourceRoot) row.toJson(),
    ],
    'shadowedCaches': [
      for (final row in shadowedRows) row.toJson(),
    ],
  };

  await reportFile.parent.create(recursive: true);
  await reportFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  String? backupPath;
  if (apply && wouldWriteLibrary) {
    if (await libraryFile.exists()) {
      await backupDirectory.create(recursive: true);
      final backup = File(
        '${backupDirectory.path}${Platform.pathSeparator}'
        'role_mapping_profiles.json',
      );
      await libraryFile.copy(backup.path);
      backupPath = backup.path;
    }
    await _saveLibraryAtomically(libraryFile, outputLibrary);
  }

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'mode': apply ? 'apply' : 'dry-run',
      'report': reportFile.path,
      if (backupPath != null) 'backup': backupPath,
      'library': libraryFile.path,
      ...report['summary']! as Map<String, Object?>,
    }),
  );
}

_RoleCandidate? _candidateFromReplacement({
  required RecastScriptCache cache,
  required File cacheFile,
  required ScriptRolePromptReplacement replacement,
  required String? characterName,
}) {
  final blocks = <RoleMappingProfileBlock>[];
  for (final rule in replacement.rules) {
    if (!rule.hasEffect) continue;
    final includedTerms = [
      for (final term in rule.sourceTerms)
        if (!rule.excludedTermIds.contains(term.id)) term,
    ];
    if (includedTerms.isEmpty) continue;
    final normalizedRule = rule.copyWith(
      sourceTerms: List.unmodifiable(includedTerms),
      excludedTermIds: const [],
      anchorTermId: includedTerms.any((term) => term.id == rule.anchorTermId)
          ? rule.anchorTermId
          : '',
      matchMode: rule.matchMode == ScriptPromptReplacementMatchMode.anchor &&
              !includedTerms.any((term) => term.id == rule.anchorTermId)
          ? ScriptPromptReplacementMatchMode.any
          : rule.matchMode,
    );
    blocks.add(RoleMappingProfileBlock.fromRule(normalizedRule));
  }
  final targetCharacterId = replacement.targetCharacterId?.trim();
  final targetIdentityPrompt = replacement.targetIdentityPrompt.trim();
  if ((targetCharacterId == null || targetCharacterId.isEmpty) &&
      targetIdentityPrompt.isEmpty &&
      blocks.isEmpty) {
    return null;
  }
  final groupKey = _groupKey(
    targetCharacterId: targetCharacterId,
    targetIdentityPrompt: targetIdentityPrompt,
  );
  if (groupKey.isEmpty) return null;
  return _RoleCandidate(
    groupKey: groupKey,
    cacheFilePath: cacheFile.path,
    scriptId: cache.scriptId,
    scriptName: cache.scriptName,
    sourceRootPath: cache.sourceRootPath,
    sourceRoleId: replacement.sourceRoleId,
    sourceRoleLabel: replacement.displayLabel,
    updatedAt: cache.updatedAt.toUtc(),
    targetCharacterId: targetCharacterId == null || targetCharacterId.isEmpty
        ? null
        : targetCharacterId,
    targetCharacterNameSnapshot: characterName?.trim() ?? '',
    targetIdentityPrompt: targetIdentityPrompt,
    blocks: List.unmodifiable(blocks),
  );
}

_MergedProfile _mergeGroup({
  required String groupKey,
  required List<_RoleCandidate> candidates,
  required RoleMappingProfile? existing,
  required Map<String, String> charactersById,
  required Set<String> usedNames,
  required DateTime now,
}) {
  final existingBlocksBySignature = {
    if (existing != null)
      for (final block in existing.blocks) _sourceSignature(block): block,
  };
  final selectedBySignature = <String, _SelectedBlock>{};
  final conflicts = <Map<String, Object?>>[];

  for (final candidate in candidates) {
    for (final block in candidate.blocks) {
      final signature = _sourceSignature(block);
      if (signature.isEmpty) continue;
      final existingBlock = existingBlocksBySignature[signature];
      if (existingBlock != null) {
        if (!_sameBlockEffect(existingBlock, block)) {
          conflicts.add({
            'groupKey': groupKey,
            'sourceSignature': signature,
            'resolution': 'kept-existing-global-profile',
            'keptEffect': _blockEffect(existingBlock),
            'discardedEffect': _blockEffect(block),
            'discardedSourceScript': candidate.scriptName,
            'discardedSourceRole': candidate.sourceRoleLabel,
          });
        }
        selectedBySignature.putIfAbsent(
          signature,
          () => _SelectedBlock(
            block: existingBlock,
            source: 'existing-global-profile',
            updatedAt: existing!.updatedAt,
          ),
        );
        continue;
      }
      final selected = selectedBySignature[signature];
      if (selected == null) {
        selectedBySignature[signature] = _SelectedBlock(
          block: block,
          source: candidate.scriptName,
          updatedAt: candidate.updatedAt,
        );
        continue;
      }
      if (!_sameBlockEffect(selected.block, block)) {
        conflicts.add({
          'groupKey': groupKey,
          'sourceSignature': signature,
          'resolution': 'kept-newest-cache',
          'keptEffect': _blockEffect(selected.block),
          'keptSource': selected.source,
          'discardedEffect': _blockEffect(block),
          'discardedSourceScript': candidate.scriptName,
          'discardedSourceRole': candidate.sourceRoleLabel,
        });
      }
    }
  }

  final newest = candidates.first;
  final targetCharacterId =
      existing?.targetCharacterId ?? newest.targetCharacterId;
  final characterName = targetCharacterId == null
      ? ''
      : charactersById[targetCharacterId]?.trim() ?? '';
  final targetIdentityPrompt =
      existing?.targetIdentityPrompt.trim().isNotEmpty == true
          ? existing!.targetIdentityPrompt
          : candidates
                  .where(
                    (candidate) =>
                        candidate.targetIdentityPrompt.trim().isNotEmpty,
                  )
                  .firstOrNull
                  ?.targetIdentityPrompt ??
              '';
  final baseName = existing?.name.trim().isNotEmpty == true
      ? existing!.name.trim()
      : characterName.isNotEmpty
          ? characterName
          : newest.targetCharacterNameSnapshot.isNotEmpty
              ? newest.targetCharacterNameSnapshot
              : _nameFromIdentity(
                  targetIdentityPrompt,
                  fallback: newest.sourceRoleLabel,
                );
  final name = _uniqueName(baseName, usedNames);
  final blocks = selectedBySignature.values.map((entry) => entry.block).toList()
    ..sort(
      (left, right) =>
          _sourceSignature(left).compareTo(_sourceSignature(right)),
    );
  final identityVariants = {
    for (final candidate in candidates)
      if (candidate.targetIdentityPrompt.trim().isNotEmpty)
        candidate.targetIdentityPrompt.trim(),
  };
  final scripts = {for (final candidate in candidates) candidate.scriptName};
  final sourceRoles = {
    for (final candidate in candidates)
      '${candidate.scriptName} :: ${candidate.sourceRoleLabel}',
  };
  final proposedProfile = RoleMappingProfile(
    id: existing?.id ?? const Uuid().v4(),
    name: name,
    targetCharacterId: targetCharacterId,
    targetCharacterNameSnapshot: characterName.isNotEmpty
        ? characterName
        : existing?.targetCharacterNameSnapshot ??
            newest.targetCharacterNameSnapshot,
    targetIdentityPrompt: targetIdentityPrompt,
    blocks: List.unmodifiable(blocks),
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  );
  final contentChanged =
      existing == null || !_sameProfileContent(existing, proposedProfile);
  final profile = contentChanged
      ? proposedProfile
      : proposedProfile.copyWith(updatedAt: existing.updatedAt);
  return _MergedProfile(
    profile: profile,
    conflicts: conflicts,
    report: {
      'profileId': profile.id,
      'name': profile.name,
      'groupKey': groupKey,
      'targetCharacterId': profile.targetCharacterId,
      'targetCharacterNameSnapshot': profile.targetCharacterNameSnapshot,
      'sourceScriptCount': scripts.length,
      'sourceRoleOccurrenceCount': sourceRoles.length,
      'inputBlockCount': candidates.fold<int>(
        0,
        (total, candidate) => total + candidate.blocks.length,
      ),
      'outputBlockCount': profile.blocks.length,
      'identityVariantCount': identityVariants.length,
      'effectConflictCount': conflicts.length,
      'mergedIntoExistingProfile': existing != null,
      'contentChanged': contentChanged,
      'sourceScripts': scripts.toList()..sort(),
    },
  );
}

bool _sameProfileContent(
  RoleMappingProfile left,
  RoleMappingProfile right,
) {
  final leftJson = Map<String, dynamic>.from(left.toJson())
    ..remove('createdAt')
    ..remove('updatedAt');
  final rightJson = Map<String, dynamic>.from(right.toJson())
    ..remove('createdAt')
    ..remove('updatedAt');
  return jsonEncode(leftJson) == jsonEncode(rightJson);
}

String _groupKeyForProfile(RoleMappingProfile profile) {
  return _groupKey(
    targetCharacterId: profile.targetCharacterId,
    targetIdentityPrompt: profile.targetIdentityPrompt,
  );
}

String _groupKey({
  required String? targetCharacterId,
  required String targetIdentityPrompt,
}) {
  final characterId = targetCharacterId?.trim().toLowerCase() ?? '';
  if (characterId.isNotEmpty) return 'character:$characterId';
  final identity = targetIdentityPrompt
      .split(',')
      .map(normalizeRoleMappingProfileTerm)
      .where((term) => term.isNotEmpty)
      .join(',');
  return identity.isEmpty ? '' : 'identity:$identity';
}

String _sourceSignature(RoleMappingProfileBlock block) {
  final keys = block.terms
      .map((term) => normalizeRoleMappingProfileTerm(term.text))
      .where((key) => key.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return keys.join('|');
}

bool _sameBlockEffect(
  RoleMappingProfileBlock left,
  RoleMappingProfileBlock right,
) {
  return left.matchMode == right.matchMode &&
      left.anchorTermKey == right.anchorTermKey &&
      left.effectiveAction == right.effectiveAction &&
      left.targetPrompt.trim() == right.targetPrompt.trim() &&
      _sameNullableDouble(
        left.targetWeightMultiplier,
        right.targetWeightMultiplier,
      );
}

bool _sameNullableDouble(double? left, double? right) {
  if (left == null || right == null) return left == right;
  return (left - right).abs() < 0.000001;
}

Map<String, Object?> _blockEffect(RoleMappingProfileBlock block) => {
      'matchMode': block.matchMode.name,
      'anchorTermKey': block.anchorTermKey,
      'action': block.effectiveAction.name,
      'targetPrompt': block.targetPrompt,
      'targetWeightMultiplier': block.targetWeightMultiplier,
    };

String _nameFromIdentity(String identity, {required String fallback}) {
  final first = identity
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .firstOrNull;
  if (first != null) return first;
  final display = fallback.split('/').last.trim();
  return display.isEmpty ? '未命名角色缓存' : display;
}

String _uniqueName(String rawName, Set<String> usedNames) {
  final base = rawName.trim().isEmpty ? '未命名角色缓存' : rawName.trim();
  if (usedNames.add(base.toLowerCase())) return base;
  for (var index = 2;; index += 1) {
    final candidate = '$base $index';
    if (usedNames.add(candidate.toLowerCase())) return candidate;
  }
}

String _logicalCacheKey(RecastScriptCache cache) {
  final source = _normalizedWindowsPath(cache.sourceRootPath);
  return source.isEmpty ? 'script:${cache.scriptId}' : 'source:$source';
}

String _normalizedWindowsPath(String value) {
  return value.trim().replaceAll('/', r'\').toLowerCase();
}

Future<Map<String, String>> _loadCharacterNames(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) {
    throw const FormatException('角色素材库必须是 JSON 数组。');
  }
  return {
    for (final value in decoded)
      if (value is Map &&
          (value['id'] as String? ?? '').trim().isNotEmpty &&
          (value['name'] as String? ?? '').trim().isNotEmpty)
        (value['id'] as String).trim(): (value['name'] as String).trim(),
  };
}

Future<RoleMappingProfileLibrary> _loadLibrary(File file) async {
  if (!await file.exists()) return const RoleMappingProfileLibrary();
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('角色映射缓存总库必须是 JSON 对象。');
  }
  return RoleMappingProfileLibrary.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

Future<void> _saveLibraryAtomically(
  File target,
  RoleMappingProfileLibrary library,
) async {
  validateRoleMappingProfileNames(library.profiles);
  await target.parent.create(recursive: true);
  final temporary = File(
    '${target.path}.tmp-${DateTime.now().toUtc().microsecondsSinceEpoch}',
  );
  try {
    const encoder = JsonEncoder.withIndent('  ');
    await temporary.writeAsString('${encoder.convert(library.toJson())}\n');
    await temporary.rename(target.path);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
}

Map<String, String> _parseOptions(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw FormatException('无效参数：$argument');
    }
    final name = argument.substring(2);
    if (name == 'apply') {
      result[name] = 'true';
      continue;
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('参数缺少值：$argument');
    }
    result[name] = arguments[index + 1];
    index += 1;
  }
  return result;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('缺少参数：--$name');
  }
  return value;
}

String _timestampForPath(DateTime value) {
  return value
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .replaceAll('.', '');
}

class _RoleCandidate {
  final String groupKey;
  final String cacheFilePath;
  final String scriptId;
  final String scriptName;
  final String sourceRootPath;
  final String sourceRoleId;
  final String sourceRoleLabel;
  final DateTime updatedAt;
  final String? targetCharacterId;
  final String targetCharacterNameSnapshot;
  final String targetIdentityPrompt;
  final List<RoleMappingProfileBlock> blocks;

  const _RoleCandidate({
    required this.groupKey,
    required this.cacheFilePath,
    required this.scriptId,
    required this.scriptName,
    required this.sourceRootPath,
    required this.sourceRoleId,
    required this.sourceRoleLabel,
    required this.updatedAt,
    required this.targetCharacterId,
    required this.targetCharacterNameSnapshot,
    required this.targetIdentityPrompt,
    required this.blocks,
  });
}

class _CacheRank {
  final String filePath;
  final DateTime updatedAt;

  const _CacheRank({
    required this.filePath,
    required this.updatedAt,
  });

  bool isNewerThan(_CacheRank other) {
    final byTime = updatedAt.compareTo(other.updatedAt);
    if (byTime != 0) return byTime > 0;
    return filePath.compareTo(other.filePath) > 0;
  }
}

class _CacheRow {
  final String filePath;
  final String scriptId;
  final String scriptName;
  final String sourceRootPath;
  final DateTime updatedAt;
  final String logicalKey;
  final int frameCount;
  final int roleCount;
  final int mappedRoleCount;
  final int effectiveRuleCount;

  const _CacheRow({
    required this.filePath,
    required this.scriptId,
    required this.scriptName,
    required this.sourceRootPath,
    required this.updatedAt,
    required this.logicalKey,
    required this.frameCount,
    required this.roleCount,
    required this.mappedRoleCount,
    required this.effectiveRuleCount,
  });

  Map<String, Object?> toJson() => {
        'file': filePath,
        'scriptId': scriptId,
        'scriptName': scriptName,
        'sourceRootPath': sourceRootPath,
        'updatedAt': updatedAt.toIso8601String(),
        'logicalKey': logicalKey,
        'frameCount': frameCount,
        'roleCount': roleCount,
        'mappedRoleCount': mappedRoleCount,
        'effectiveRuleCount': effectiveRuleCount,
      };
}

class _SelectedBlock {
  final RoleMappingProfileBlock block;
  final String source;
  final DateTime updatedAt;

  const _SelectedBlock({
    required this.block,
    required this.source,
    required this.updatedAt,
  });
}

class _MergedProfile {
  final RoleMappingProfile profile;
  final Map<String, Object?> report;
  final List<Map<String, Object?>> conflicts;

  const _MergedProfile({
    required this.profile,
    required this.report,
    required this.conflicts,
  });
}
