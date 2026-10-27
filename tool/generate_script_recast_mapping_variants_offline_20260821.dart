import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart'
    show
        RoleMappingProfile,
        RoleMappingProfileApplySelection,
        RoleMappingProfileLibrary;
import 'package:novel_studio/data/studio/services/script_role_mapping_profile_service.dart';

const _defaultTargetIds = <String>[
  'legacy-character-sheet-r14',
  'legacy-character-sheet-r13',
  'legacy-character-sheet-r29',
  'legacy-character-sheet-r15',
  'legacy-character-sheet-r26',
  'roccia-wuthering-waves',
  'rossi-arknights-endfield',
];

Future<void> main(List<String> arguments) async {
  final options = _parseArgs(arguments);
  final cacheDirectory = Directory(options.cacheDirectory);
  final profileFile = File(options.profileFile);
  final characterLibraryFile = File(options.characterLibrary);
  if (!cacheDirectory.existsSync()) {
    throw StateError('Missing cache directory: ${cacheDirectory.path}');
  }
  if (!profileFile.existsSync()) {
    throw StateError('Missing profile library: ${profileFile.path}');
  }
  if (!characterLibraryFile.existsSync()) {
    throw StateError('Missing character library: ${characterLibraryFile.path}');
  }

  final profileLibrary = RoleMappingProfileLibrary.fromJson(
    _jsonObject(profileFile.readAsStringSync()),
  );
  final profiles = <RoleMappingProfile>[];
  final selectedProfileIds = <String>{};
  void addProfile(RoleMappingProfile profile) {
    if (!selectedProfileIds.add(profile.id)) return;
    if (profile.targetIdentityPrompt.trim().isEmpty ||
        profile.effectiveLayers.isEmpty ||
        !profile.blocks.any((block) => block.hasEffect)) {
      throw StateError('Global profile ${profile.name} is incomplete.');
    }
    profiles.add(profile);
  }

  for (final profileId in options.profileIds) {
    final matches = profileLibrary.profiles
        .where((profile) => profile.id == profileId)
        .toList(growable: false);
    if (matches.length != 1) {
      throw StateError(
        'Expected one global profile for id $profileId, found ${matches.length}.',
      );
    }
    addProfile(matches.single);
  }
  for (final targetId in options.targetIds) {
    final matches = profileLibrary.profiles
        .where((profile) => profile.targetCharacterId == targetId)
        .toList(growable: false);
    final profile = _profileForTargetId(targetId, matches);
    if (profile == null) {
      throw StateError(
        'Expected one global profile for $targetId, found ${matches.length}.',
      );
    }
    addProfile(profile);
  }
  final selectedTargetIds = profiles
      .map((profile) => profile.targetCharacterId)
      .whereType<String>()
      .toSet();
  final unknownRefreshIds = options.refreshTargetIds
      .where((id) => !selectedTargetIds.contains(id))
      .toList(growable: false);
  if (unknownRefreshIds.isNotEmpty) {
    throw StateError(
      'Refresh targets are not in the selected profiles: ${unknownRefreshIds.join(', ')}',
    );
  }
  final unknownRefreshProfileIds = options.refreshProfileIds
      .where((id) => !selectedProfileIds.contains(id))
      .toList(growable: false);
  if (unknownRefreshProfileIds.isNotEmpty) {
    throw StateError(
      'Refresh profile ids are not selected: ${unknownRefreshProfileIds.join(', ')}',
    );
  }

  final characterIds = _characterIds(
    jsonDecode(characterLibraryFile.readAsStringSync()),
  );
  const profileService = ScriptRoleMappingProfileService();
  final sourceRoot = _normalizePath(options.sourceRoot);
  final files = cacheDirectory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.json'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final rows = <Map<String, dynamic>>[];
  final existingVariantCounts = <String, int>{};
  final generatedVariantCounts = <String, int>{};
  final refreshedVariantCounts = <String, int>{};
  final fingerprintMismatches = <Map<String, dynamic>>[];
  final missingBefore = <Map<String, dynamic>>[];
  final refreshedBefore = <Map<String, dynamic>>[];
  final filesWithChanges = <String>[];
  var filesMatched = 0;
  var filesChanged = 0;
  var variantsBefore = 0;
  var variantsAfter = 0;
  var sourceWriteAttempts = 0;

  for (final file in files) {
    final raw = _jsonObject(file.readAsStringSync());
    final rawSourceRoot = _stringValue(raw['sourceRootPath']);
    if (!_isUnderSourceRoot(rawSourceRoot, sourceRoot)) continue;
    filesMatched += 1;

    final cache = RecastScriptCache.fromJson(raw);
    final existingRawVariants = _rawVariantList(raw['mappingVariants']);
    final existingIds = {
      for (final variant in cache.mappingVariants) variant.id,
    };
    variantsBefore += existingRawVariants.length;
    for (final variant in cache.mappingVariants) {
      existingVariantCounts[variant.name] =
          (existingVariantCounts[variant.name] ?? 0) + 1;
      if (variant.sourceFingerprint != cache.sourceFingerprint ||
          variant.sourceContentFingerprint != cache.sourceContentFingerprint) {
        fingerprintMismatches.add({
          'file': file.path,
          'variantId': variant.id,
          'name': variant.name,
        });
      }
    }

    final baseMapping = cache.mapping;
    final linkedProfileIds = {
      for (final replacement in baseMapping.rolePromptReplacements)
        if (replacement.activeMappingProfileId?.trim().isNotEmpty == true)
          replacement.activeMappingProfileId!.trim(),
    };
    // Every profile selected for this offline run is intentionally eligible
    // for every matched script.  The old code only treated --profile-id as an
    // explicit selection, so the default --target-id profiles were generated
    // only for scripts that already happened to link them.  That left entire
    // scripts without script-specific character mapping variants.
    final explicitlySelectedProfileIds = {
      ...options.profileIds,
      ...profiles.map((profile) => profile.id),
    };
    bool isEligibleProfile(RoleMappingProfile profile) {
      return linkedProfileIds.contains(profile.id) ||
          explicitlySelectedProfileIds.contains(profile.id);
    }

    final missingProfiles = [
      for (final profile in profiles)
        if (isEligibleProfile(profile) &&
            !existingIds.contains('auto-global-profile-${profile.id}'))
          profile,
    ];
    for (final profile in missingProfiles) {
      missingBefore.add({
        'file': file.path,
        'profileId': profile.id,
        'name': _targetName(profile),
      });
    }
    for (final profile in profiles) {
      final variantId = 'auto-global-profile-${profile.id}';
      if (isEligibleProfile(profile) &&
          _isProfileRefreshSelected(options, profile) &&
          existingIds.contains(variantId)) {
        refreshedBefore.add({
          'file': file.path,
          'profileId': profile.id,
          'name': _targetName(profile),
        });
      }
    }
    final profilesToGenerate = [
      for (final profile in profiles)
        if (isEligibleProfile(profile) &&
            (_isProfileRefreshSelected(options, profile) ||
                !existingIds.contains('auto-global-profile-${profile.id}')))
          profile,
    ];
    final selectedAutoVariantIds = {
      for (final profile in profiles) 'auto-global-profile-${profile.id}',
    };
    final staleSelectedVariantIds = {
      for (final variant in existingRawVariants)
        if (selectedAutoVariantIds.contains(_stringValue(variant['id'])) &&
            !linkedProfileIds.contains(
              _stringValue(variant['id']).substring(
                'auto-global-profile-'.length,
              ),
            ) &&
            !explicitlySelectedProfileIds.contains(
              _stringValue(variant['id']).substring(
                'auto-global-profile-'.length,
              ),
            ))
          _stringValue(variant['id']),
    };
    if (profilesToGenerate.isEmpty && staleSelectedVariantIds.isEmpty) {
      variantsAfter += existingRawVariants.length;
      continue;
    }

    final generated = <Map<String, dynamic>>[];
    final generatedDetails = <Map<String, dynamic>>[];
    final capturedAt = DateTime.now().toUtc();
    for (final indexed in profilesToGenerate.indexed) {
      final profile = indexed.$2;
      final variantId = 'auto-global-profile-${profile.id}';
      final isRefresh = _isProfileRefreshSelected(options, profile) &&
          existingIds.contains(variantId);
      final applicableProfile = profile.targetCharacterId != null &&
              !characterIds.contains(profile.targetCharacterId)
          ? profile.copyWith(targetCharacterId: null)
          : profile;
      // A cache may currently have the same global profile selected as its
      // active mapping. Rebase that input before refreshing the profile;
      // otherwise removed/renamed profile blocks can leak into the refreshed
      // variant and the refresh is no longer idempotent.
      final mappingBase = _mappingRebasedFromSelectedProfiles(
        baseMapping,
        profiles,
      );
      final rolePromptReplacements = <ScriptRolePromptReplacement>[];
      var selectedEntryCount = 0;
      var selectedTermCount = 0;
      var effectiveRuleCount = 0;
      var beforeEffectiveRuleCount = 0;
      for (final replacement in mappingBase.rolePromptReplacements) {
        beforeEffectiveRuleCount +=
            replacement.rules.where((rule) => rule.hasEffect).length;
        final assembly = _assemblyForRole(
          mappingBase,
          replacement.sourceRoleId,
        );
        final shouldApplyProfile =
            explicitlySelectedProfileIds.contains(profile.id) ||
                replacement.activeMappingProfileId?.trim() == profile.id.trim();
        if (!shouldApplyProfile ||
            !_profileCanApplyToRole(profile, replacement, assembly)) {
          rolePromptReplacements.add(replacement);
          effectiveRuleCount +=
              replacement.rules.where((rule) => rule.hasEffect).length;
          continue;
        }
        final preview = profileService.buildPreview(
          profile: applicableProfile,
          replacement: replacement,
          assembly: assembly,
        );
        final selections = [
          for (final entry in preview.entries)
            if (entry.selectedByDefault && entry.selectedTermIds.isNotEmpty)
              RoleMappingProfileApplySelection(
                blockId: entry.block.id,
                termIds: entry.selectedTermIds,
              ),
        ];
        selectedEntryCount += selections.length;
        selectedTermCount += selections.fold<int>(
            0, (sum, selection) => sum + selection.termIds.length);
        final appliedReplacement = profileService.applySelections(
          profile: applicableProfile,
          replacement: replacement,
          selections: selections,
          applyIdentity: true,
          linkProfile: true,
          assembly: assembly,
        );
        final materializedReplacement =
            profileService.materializeTargetIdentityReplacement(
          appliedReplacement,
        );
        final nextReplacement = profileService.deduplicateTargetOutputs(
          materializedReplacement,
          forbiddenTarget:
              profile.id == 'profile-legacy-character-sheet-r24' ? '果宝' : '',
        );
        effectiveRuleCount +=
            nextReplacement.rules.where((rule) => rule.hasEffect).length;
        rolePromptReplacements.add(nextReplacement);
      }
      final mapping = RecastMapping.fromJson(
        Map<String, dynamic>.from(
          mappingBase
              .copyWith(
                rolePromptReplacements:
                    List.unmodifiable(rolePromptReplacements),
              )
              .toJson(),
        ),
      );
      final targetName = _targetName(profile);
      final namesByRoleId = <String, String>{
        for (final replacement in mapping.rolePromptReplacements)
          if (replacement.activeMappingProfileId?.trim() == profile.id.trim())
            replacement.sourceRoleId: targetName,
      };
      final variant = RecastMappingVariant(
        id: variantId,
        name: targetName,
        scriptId: cache.scriptId,
        sourceFingerprint: cache.sourceFingerprint,
        sourceContentFingerprint: cache.sourceContentFingerprint,
        capturedAt: capturedAt.subtract(Duration(microseconds: indexed.$1)),
        mapping: mapping,
        targetCharacterNamesByRoleId: namesByRoleId,
      );
      generated.add(variant.toJson());
      generatedVariantCounts[targetName] =
          (generatedVariantCounts[targetName] ?? 0) + 1;
      if (isRefresh) {
        refreshedVariantCounts[targetName] =
            (refreshedVariantCounts[targetName] ?? 0) + 1;
      }
      generatedDetails.add({
        'profileId': profile.id,
        'name': targetName,
        'refreshed': isRefresh,
        'roleCount': mapping.rolePromptReplacements.length,
        'selectedEntryCount': selectedEntryCount,
        'selectedTermCount': selectedTermCount,
        'effectiveRulesBefore': beforeEffectiveRuleCount,
        'effectiveRulesAfter': effectiveRuleCount,
        'identityPromptHasWolfEars': targetName == '洛茜'
            ? mapping.rolePromptReplacements
                .where(
                  (replacement) =>
                      explicitlySelectedProfileIds.contains(profile.id) ||
                      replacement.activeMappingProfileId?.trim() ==
                          profile.id.trim(),
                )
                .every(
                  (replacement) =>
                      replacement.targetIdentityPrompt.contains('wolf_ears'),
                )
            : null,
      });
    }

    final generatedById = <String, Map<String, dynamic>>{
      for (final variant in generated) _stringValue(variant['id']): variant,
    };
    final nextVariants = <Map<String, dynamic>>[
      for (final variant in existingRawVariants)
        if (!staleSelectedVariantIds.contains(_stringValue(variant['id'])))
          generatedById[_stringValue(variant['id'])] ?? variant,
      for (final profile in profilesToGenerate)
        if (!existingIds.contains('auto-global-profile-${profile.id}'))
          generatedById['auto-global-profile-${profile.id}']!,
    ];
    final nextRaw = Map<String, dynamic>.from(raw);
    nextRaw['mappingVariants'] = nextVariants;
    if (staleSelectedVariantIds.contains(
      _stringValue(raw['activeMappingVariantId']),
    )) {
      nextRaw['activeMappingVariantId'] = null;
    }
    final nextVariantCount = nextVariants.length;
    variantsAfter += nextVariantCount;
    filesWithChanges.add(file.path);
    filesChanged += 1;
    rows.add({
      'file': file.path,
      'scriptId': cache.scriptId,
      'scriptName': cache.scriptName,
      'variantsBefore': existingRawVariants.length,
      'variantsAfter': nextVariantCount,
      'generated': generatedDetails,
      'activeMappingVariantIdPreserved': raw['activeMappingVariantId'],
    });

    if (options.apply) {
      final backupDirectory = Directory(options.backupDirectory);
      backupDirectory.createSync(recursive: true);
      File(
        '${backupDirectory.path}${Platform.pathSeparator}${_basename(file.path)}',
      ).writeAsStringSync(file.readAsStringSync());
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(nextRaw)}\n',
      );
    }
  }

  final report = <String, dynamic>{
    'tool': 'generate_script_recast_mapping_variants_offline_20260821',
    'api_used': false,
    'apply': options.apply,
    'source_root': sourceRoot,
    'cache_dir': cacheDirectory.path,
    'profile_file': profileFile.path,
    'character_library': characterLibraryFile.path,
    'target_ids': options.targetIds,
    'profile_ids': options.profileIds,
    'refresh_target_ids': options.refreshTargetIds,
    'refresh_profile_ids': options.refreshProfileIds,
    'selected_profile_ids': profiles.map((profile) => profile.id).toList(),
    'target_names': profiles.map(_targetName).toList(growable: false),
    'files_scanned': files.length,
    'files_matched': filesMatched,
    'files_changed_if_applied': filesChanged,
    'files_changed': options.apply ? filesChanged : 0,
    'source_write_attempts': sourceWriteAttempts,
    'variants_before': variantsBefore,
    'variants_after_if_applied': variantsAfter,
    'existing_variant_counts': existingVariantCounts,
    'generated_variant_counts_if_applied': generatedVariantCounts,
    'refreshed_variant_counts_if_applied': refreshedVariantCounts,
    'missing_before_count': missingBefore.length,
    'refreshed_before_count': refreshedBefore.length,
    'refreshed_before': refreshedBefore,
    'fingerprint_mismatch_count': fingerprintMismatches.length,
    'fingerprint_mismatches': fingerprintMismatches,
    'files': rows,
    'validation': {
      'ok': fingerprintMismatches.isEmpty && sourceWriteAttempts == 0,
      'errors': <String>[
        if (fingerprintMismatches.isNotEmpty)
          'Existing mapping variants contain source fingerprint mismatches.',
        if (sourceWriteAttempts != 0) 'The source root must remain read-only.',
      ],
    },
  };
  final reportFile = File(options.reportFile);
  reportFile.parent.createSync(recursive: true);
  reportFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if ((report['validation'] as Map)['ok'] != true) {
    exitCode = 1;
  }
}

RoleAssembly? _assemblyForRole(RecastMapping mapping, String roleId) {
  for (final assembly in mapping.roleAssemblies) {
    if (assembly.sourceRoleId == roleId) return assembly;
  }
  return null;
}

String _targetName(RoleMappingProfile profile) {
  final snapshot = profile.targetCharacterNameSnapshot.trim();
  return snapshot.isEmpty ? profile.name.trim() : snapshot;
}

RoleMappingProfile? _profileForTargetId(
  String targetId,
  List<RoleMappingProfile> matches,
) {
  if (matches.length == 1) return matches.single;
  if (targetId == 'legacy-character-sheet-r14') {
    final legacy = matches
        .where((profile) => profile.name == '佩佩（无兜帽）')
        .toList(growable: false);
    if (legacy.length == 1) return legacy.single;
  }
  return null;
}

bool _isProfileRefreshSelected(
  _Options options,
  RoleMappingProfile profile,
) {
  return options.refreshTargetIds.contains(profile.targetCharacterId) ||
      options.refreshProfileIds.contains(profile.id);
}

Set<String> _characterIds(Object? raw) {
  final values = raw is List
      ? raw
      : raw is Map && raw['characters'] is List
          ? raw['characters'] as List
          : const <dynamic>[];
  return {
    for (final value in values)
      if (value is Map && _stringValue(value['id']).trim().isNotEmpty)
        _stringValue(value['id']).trim(),
  };
}

String _basename(String value) {
  final normalized = value.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

List<Map<String, dynamic>> _rawVariantList(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return [
    for (final entry in value)
      if (entry is Map) Map<String, dynamic>.from(entry),
  ];
}

RecastMapping _mappingRebasedFromSelectedProfiles(
  RecastMapping mapping,
  Iterable<RoleMappingProfile> profiles,
) {
  final profileIds = {
    for (final profile in profiles)
      if (profile.id.trim().isNotEmpty) profile.id.trim(),
  };
  final targetCharacterIds = {
    for (final profile in profiles)
      if (profile.targetCharacterId?.trim().isNotEmpty == true)
        profile.targetCharacterId!.trim(),
  };
  if (profileIds.isEmpty && targetCharacterIds.isEmpty) return mapping;
  var changed = false;
  final replacements = <ScriptRolePromptReplacement>[];
  for (final replacement in mapping.rolePromptReplacements) {
    if (profileIds.contains(replacement.activeMappingProfileId?.trim()) ||
        targetCharacterIds.contains(replacement.targetCharacterId?.trim())) {
      changed = true;
      replacements.add(
        replacement.copyWith(
          targetCharacterId: null,
          targetIdentityPrompt: '',
          activeMappingProfileId: null,
          rules: List.unmodifiable([
            for (final rule in replacement.rules)
              rule.copyWith(
                action: rule.action == ScriptPromptReplacementAction.delete
                    ? ScriptPromptReplacementAction.delete
                    : ScriptPromptReplacementAction.none,
                targetPrompt: '',
                targetWeightMultiplier: null,
                manualPhrase: '',
              ),
          ]),
        ),
      );
    } else {
      replacements.add(replacement);
    }
  }
  return changed
      ? mapping.copyWith(
          rolePromptReplacements: List.unmodifiable(replacements),
        )
      : mapping;
}

Map<String, dynamic> _jsonObject(String text) {
  final value = jsonDecode(text);
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  return Map<String, dynamic>.from(value);
}

String _stringValue(Object? value) {
  return value is String
      ? value
      : value == null
          ? ''
          : value.toString();
}

String _normalizePath(String value) {
  return value
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '')
      .toLowerCase();
}

bool _isUnderSourceRoot(String value, String root) {
  final current = _normalizePath(value);
  return current == root || current.startsWith('$root/');
}

bool _profileCanApplyToRole(
  RoleMappingProfile profile,
  ScriptRolePromptReplacement replacement,
  RoleAssembly? assembly,
) {
  if (assembly == null ||
      !assembly.sourceAppearances.any(
        (appearance) =>
            appearance.sourceKind.trim().toLowerCase() != 'base' &&
            appearance.sourceId.trim().toLowerCase() != 'base',
      )) {
    return false;
  }
  final targetText =
      '${profile.name} ${profile.targetIdentityPrompt}'.toLowerCase();
  final targetLooksMale = RegExp(
    r'\b(?:male|man|boy|boys|guy|shota|father|husband)\b|男性|男孩|男人',
  ).hasMatch(targetText);
  if (targetLooksMale) return true;

  final identityTerms = [
    for (final rule in replacement.rules)
      for (final term in rule.sourceTerms)
        if (term.category.name == 'character') term.text,
  ];
  final sourceText = [
    replacement.sourceRoleId,
    replacement.displayLabel,
    replacement.sourcePreview,
    ...identityTerms,
  ].join(' ').toLowerCase();
  return !RegExp(
    r'\b(?:anonymous[-_ ]?male|muscular[-_ ]?male|black[-_ ]?man|fat[-_ ]?man|male|man|boy|boys|guy|shota|father|husband|sensei|teacher|commander|doodle|yuuki|caelus)\b|男性|男孩|男人|老师|教师|指挥官',
  ).hasMatch(sourceText);
}

class _Options {
  final String cacheDirectory;
  final String sourceRoot;
  final String profileFile;
  final String characterLibrary;
  final String reportFile;
  final String backupDirectory;
  final List<String> targetIds;
  final List<String> profileIds;
  final List<String> refreshTargetIds;
  final List<String> refreshProfileIds;
  final bool apply;

  const _Options({
    required this.cacheDirectory,
    required this.sourceRoot,
    required this.profileFile,
    required this.characterLibrary,
    required this.reportFile,
    required this.backupDirectory,
    required this.targetIds,
    required this.profileIds,
    required this.refreshTargetIds,
    required this.refreshProfileIds,
    required this.apply,
  });
}

_Options _parseArgs(List<String> arguments) {
  String? cacheDirectory;
  String? sourceRoot;
  String? profileFile;
  String? characterLibrary;
  String? reportFile;
  String? backupDirectory;
  final targetIds = <String>[];
  final profileIds = <String>[];
  final refreshTargetIds = <String>[];
  final refreshProfileIds = <String>[];
  var apply = false;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument == '--apply') {
      apply = true;
      continue;
    }
    if (!argument.startsWith('--') || index + 1 >= arguments.length) continue;
    final key = argument.substring(2);
    final value = arguments[++index];
    switch (key) {
      case 'cache-dir':
        cacheDirectory = value;
      case 'source-root':
        sourceRoot = value;
      case 'profile-file':
        profileFile = value;
      case 'character-library':
        characterLibrary = value;
      case 'report':
        reportFile = value;
      case 'backup-dir':
        backupDirectory = value;
      case 'target-id':
        targetIds.add(value);
      case 'profile-id':
        profileIds.add(value);
      case 'refresh-target-id':
        refreshTargetIds.add(value);
      case 'refresh-profile-id':
        refreshProfileIds.add(value);
    }
  }
  if (cacheDirectory == null ||
      sourceRoot == null ||
      profileFile == null ||
      characterLibrary == null ||
      reportFile == null) {
    throw ArgumentError(
      'Pass --cache-dir, --source-root, --profile-file, '
      '--character-library, and --report.',
    );
  }
  if (apply && (backupDirectory == null || backupDirectory.trim().isEmpty)) {
    throw ArgumentError('Pass --backup-dir when using --apply.');
  }
  return _Options(
    cacheDirectory: cacheDirectory,
    sourceRoot: sourceRoot,
    profileFile: profileFile,
    characterLibrary: characterLibrary,
    reportFile: reportFile,
    backupDirectory: backupDirectory ?? '',
    targetIds:
        targetIds.isEmpty && profileIds.isEmpty ? _defaultTargetIds : targetIds,
    profileIds: profileIds,
    refreshTargetIds: refreshTargetIds,
    refreshProfileIds: refreshProfileIds,
    apply: apply,
  );
}
